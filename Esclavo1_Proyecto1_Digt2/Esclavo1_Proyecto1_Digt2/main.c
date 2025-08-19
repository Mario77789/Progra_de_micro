/*
 * Esclavo1_Proyecto1_Digt2.c
 *
 * Created: 16/08/2025 20:12:27
 * Author : mario
 */ 


#define F_CPU 16000000UL
#include <avr/io.h>
#include <util/delay.h>
#include <stdint.h>
#include "I2C/I2C.h"

// --- Pines SRF05 ---
#define TRIG_PIN   PD7
#define ECHO_PIN   PD2
#define TRIG_DDR   DDRD
#define TRIG_PORT  PORTD
#define ECHO_DDR   DDRD
#define ECHO_PINR  PIND

// SERVO (D9 / PB1 / OC1A)
static void  servo_init(void){
    DDRB |= (1<<PB1);
    TCCR1A = (1<<COM1A1) | (1<<WGM11);
    TCCR1B = (1<<WGM13)  | (1<<WGM12) | (1<<CS11);  // /8
    ICR1   = 39999; // 20 ms
}
static void  servo_set_angle(uint8_t angle){
    const uint16_t min_ticks = 1200; // 0.6 ms
    const uint16_t max_ticks = 4800; // 2.4 ms
    uint16_t ticks = min_ticks + ((uint32_t)(max_ticks - min_ticks) * angle) / 180;
    OCR1A = ticks;
}

static void gpio_init(void){
    // TRIG salida
    TRIG_DDR  |=  (1<<TRIG_PIN);
    TRIG_PORT &= ~(1<<TRIG_PIN);
    // ECHO entrada
    ECHO_DDR  &= ~(1<<ECHO_PIN);
    // Timer2 clk/8
    TCCR2A=0; TCCR2B=(1<<CS21); TCNT2=0;
}

static uint8_t medir_distancia_cm(void){
    // Pulso TRIG
    TRIG_PORT &= ~(1<<TRIG_PIN); _delay_us(2);
    TRIG_PORT |=  (1<<TRIG_PIN); _delay_us(10);
    TRIG_PORT &= ~(1<<TRIG_PIN);

    // Esperar subida
    uint32_t guard=0;
    while (!(ECHO_PINR & (1<<ECHO_PIN))) { if (++guard>60000UL) return 0xFF; }

    // Medir alto con Timer2 + OVF
    uint16_t ovf=0; TCNT2=0; TIFR2 |= (1<<TOV2);
    while (ECHO_PINR & (1<<ECHO_PIN)) {
        if (TIFR2 & (1<<TOV2)) { TIFR2 |= (1<<TOV2); if (++ovf>240) return 0xFF; }
    }
    uint16_t ticks = TCNT2 + (ovf*256U);
    uint32_t us = ticks/2U;           // 0.5 us/tick
    uint32_t cm = us / 58U;           // aproximación
    if (cm>255U) cm=255U;
    return (uint8_t)cm;
}

int main(void){
    gpio_init();
    servo_init();
    I2C_SlaveInit(0x20);

    uint8_t last_cm = 0xFF;

    while(1){
        // Espera comando del maestro
        uint8_t cmd = I2C_SlaveReceive();
        if (cmd == 0x01){
            last_cm = medir_distancia_cm();

            // Lógica servo: <5 cm -> 90°, si no -> 0°
            if (last_cm != 0xFF && last_cm < 5) servo_set_angle(90);
            else                                 servo_set_angle(0);

            // Responde cuando el maestro haga SLA+R
            I2C_SlaveTransmit(last_cm);
        }
        _delay_ms(1);
    }
}

