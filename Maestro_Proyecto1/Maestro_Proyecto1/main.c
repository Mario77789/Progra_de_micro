/*
 * Maestro_Proyecto1.c
 *
 * Created: 10/08/2025 17:06:06
 * Author : mario
 */ 



#define F_CPU 16000000UL
#include <avr/io.h>
#include <util/delay.h>
#include <avr/interrupt.h>
#include <stdbool.h>
#include "I2C.h"        

// ------------------- Pines SRF05 -------------------
#define TRIG_PIN   PD7     // D7 -> Trigger
#define ECHO_PIN   PD2     // D2 -> Echo
#define TRIG_DDR   DDRD
#define TRIG_PORT  PORTD
#define ECHO_DDR   DDRD
#define ECHO_PINR  PIND

// ------------------- Estado I2C/Medición -------------------
volatile uint8_t  last_distance_cm = 0xFF;  // último dato listo para servir
volatile uint8_t  measure_request  = 0;     // 1 = medir en el loop principal
volatile uint8_t  tx_byte          = 0xFF;  // byte a transmitir al maestro
volatile uint8_t  rx_byte          = 0x00;  // último comando recibido

// ------------------- Prototipos -------------------
static void  gpio_init(void);
static void  timer2_init(void);
static uint8_t medir_distancia_cm(void);    // 0..255; 0xFF si timeout/error
static void  i2c_slave_poll(void);          // manejador por sondeo de estados TWI

// SERVO (D9 / PB1 / OC1A)
static void  servo_init(void);
static void  servo_set_angle(uint8_t angle);

// ------------------- Inicializaciones -------------------
static void gpio_init(void)
{
    // TRIG salida (en bajo)
    TRIG_DDR  |=  (1 << TRIG_PIN);
    TRIG_PORT &= ~(1 << TRIG_PIN);

    // ECHO entrada, sin pull-up
    ECHO_DDR  &= ~(1 << ECHO_PIN);
}

static void timer2_init(void)
{
    // Timer2: clk/8 -> 2 MHz => 0.5 us por tick
    TCCR2A = 0x00;
    TCCR2B = (1 << CS21);
    TCNT2  = 0;
}

// ------------------- SERVO (Timer1 @ 50 Hz) -------------------
static void servo_init(void)
{
    DDRB |= (1 << PB1);  // D9 como salida

    // Fast PWM, TOP = ICR1, canal A no invertido, prescaler = 8
    TCCR1A = (1 << COM1A1) | (1 << WGM11);
    TCCR1B = (1 << WGM13)  | (1 << WGM12) | (1 << CS11);  // CS11 => /8
    ICR1   = 39999; // 20 ms @ 16 MHz / 8  (0.5 us/tick * 40000 = 20 ms)

    // Inicial en 0°
    servo_set_angle(0);
}

static void servo_set_angle(uint8_t angle)
{
    // Mapeo solicitado: 0.6 ms (0°) -> 2.4 ms (180°)
    // 0.5 us por tick -> 0.6 ms = 1200 ticks, 2.4 ms = 4800 ticks
    const uint16_t min_ticks = 1200; // 0.6 ms
    const uint16_t max_ticks = 4800; // 2.4 ms
    uint16_t ticks = min_ticks + ((uint32_t)(max_ticks - min_ticks) * angle) / 180;
    OCR1A = ticks;
}

// ------------------- Medición SRF05 -------------------
static uint8_t medir_distancia_cm(void)
{
    // 1) Pulso TRIG de 10 us
    TRIG_PORT &= ~(1 << TRIG_PIN);
    _delay_us(2);
    TRIG_PORT |=  (1 << TRIG_PIN);
    _delay_us(10);
    TRIG_PORT &= ~(1 << TRIG_PIN);

    // 2) Esperar flanco de subida en ECHO (timeout)
    uint32_t guard = 0;
    while (!(ECHO_PINR & (1 << ECHO_PIN))) {
        if (++guard > 60000UL) return 0xFF;  // ~>30 ms
    }

    // 3) Medir tiempo alto con Timer2 + conteo de overflow
    uint16_t ovf = 0;
    TCNT2 = 0;
    TIFR2 |= (1 << TOV2);  // limpia flag

    while (ECHO_PINR & (1 << ECHO_PIN)) {
        if (TIFR2 & (1 << TOV2)) {
            TIFR2 |= (1 << TOV2);
            if (++ovf > 240) return 0xFF;   // ~30.7 ms
        }
    }

    uint16_t ticks = TCNT2 + (ovf * 256U);
    uint32_t us = ticks / 2U;      // 0.5 us/tick
    uint32_t cm = us / 58U;        // aproximación estándar
    if (cm > 255U) cm = 255U;
    return (uint8_t)cm;
}

// ------------------- Manejador I2C por sondeo -------------------
static void i2c_slave_poll(void)
{
    // Si no hay evento TWI pendiente, salir
    if (!(TWCR & (1 << TWINT))) return;

    switch (TWSR & 0xF8) {

        // SLA+W recibido (maestro quiere escribir)
        case TW_SR_SLA_ACK:
        case TW_SR_GCALL_ACK:
            // Listo para recibir datos del maestro
            TWCR = (1 << TWEN) | (1 << TWEA) | (1 << TWINT);
            break;

        // Dato recibido tras SLA+W
        case TW_SR_DATA_ACK:
        case TW_SR_GCALL_DATA_ACK:
            rx_byte = TWDR;
            if (rx_byte == 0x01) {
                measure_request   = 1;     // pedir medición en el loop
                last_distance_cm  = 0xFF;  // “ocupado/no listo” hasta medir
            }
            // Seguir aceptando más datos o STOP
            TWCR = (1 << TWEN) | (1 << TWEA) | (1 << TWINT);
            break;

        // STOP o repeated START
        case TW_SR_STOP:
            TWCR = (1 << TWEN) | (1 << TWEA) | (1 << TWINT);
            break;

        // SLA+R recibido (maestro quiere leer)
        case TW_ST_SLA_ACK:
        case TW_ST_DATA_ACK:
            tx_byte = last_distance_cm; // servir el último disponible
            TWDR = tx_byte;
            // Preparar siguiente byte (aunque nuestro protocolo es 1 byte)
            TWCR = (1 << TWEN) | (1 << TWEA) | (1 << TWINT);
            break;

        // Maestro terminó (NACK) o último dato
        case TW_ST_DATA_NACK:
        case TW_ST_LAST_DATA:
            TWCR = (1 << TWEN) | (1 << TWEA) | (1 << TWINT);
            break;

        default:
            // Recuperación defensiva
            TWCR = (1 << TWEN) | (1 << TWEA) | (1 << TWINT);
            break;
    }
}

// ------------------- MAIN -------------------
int main(void)
{
    gpio_init();
    timer2_init();
    servo_init();                 // D9 listo con mapeo 0.6–2.4 ms

    // Inicializa I2C en modo esclavo con tu librería
    I2C_SlaveInit(0x20);          // I²C @ 0x20
    sei();

    while (1) {

        // Atiende eventos I2C por sondeo (sin ISR)
        i2c_slave_poll();

        // Si el maestro pidió medición, realiza y publica
        if (measure_request) {
            uint8_t d = medir_distancia_cm();
            last_distance_cm = d;       // publica dato para el maestro

            // Lógica local del SERVO:
            // < 5 cm -> 90° ; si no (incluye error 0xFF) -> 0°
            if (d != 0xFF && d < 5) {
                servo_set_angle(90);
            } else {
                servo_set_angle(0);
            }

            measure_request = 0;
        }

        _delay_ms(1);
    }
}
