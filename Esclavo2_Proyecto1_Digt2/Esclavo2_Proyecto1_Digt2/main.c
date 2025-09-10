/*
 * Esclavo2_Proyecto1_Digt2.c
 *
 * Created: 10/08/2025 19:04:59
 *  Author: mario
 */ 

#define F_CPU 16000000UL
#include <avr/io.h>
#include <util/delay.h>
#include <avr/interrupt.h>
#include "I2C/I2C.h"

#define DHT11_PIN     PD5        
#define SLAVE_ADDRESS 0x21       
#define STATUS_LED    PB5
#define MOTOR_PIN     PB1        

#define CMD_PREPARE   0x01
#define CMD_FORCE_TEMP 0x11
#define CMD_MODE_AUTO  0x12

#define STATUS_OK     0x00
#define STATUS_BUSY   0xFE
#define STATUS_INIT   0xFF

volatile int8_t  temperature = 0;
volatile uint8_t status_code = STATUS_INIT;

volatile uint8_t tx_buf[2]   = {STATUS_INIT, 0};  // [status, temp]
volatile uint8_t tx_idx      = 0;
volatile uint8_t data_len    = 2;

volatile uint8_t request_measure = 0;  // pedido desde ISR
volatile uint8_t ready            = 0;  // dato listo (OK o error)

// NUEVO: control forzado
volatile uint8_t force_mode = 0; // 0=AUTO, 1=FORCE
volatile uint8_t force_val  = 0; // 0=OFF, 1=ON

// recepción de par comando+dato
volatile uint8_t i2c_expect_data = 0;
volatile uint8_t i2c_last_cmd    = 0;
volatile uint8_t i2c_data_byte   = 0;
volatile uint8_t i2c_have_pair   = 0;

static inline void set_led(uint8_t state) {
    DDRB |= (1 << STATUS_LED);
    if (state) PORTB |= (1 << STATUS_LED);
    else       PORTB &= ~(1 << STATUS_LED);
}

static void blink_pattern(uint8_t code) {
    for (uint8_t i = 0; i < code; i++) {
        set_led(1); _delay_ms(200);
        set_led(0); _delay_ms(200);
    }
}

static int8_t read_dht11(void) {
    uint8_t data[5] = {0};
    uint16_t timeout;

    DDRD  |=  (1 << DHT11_PIN);
    PORTD &= ~(1 << DHT11_PIN);
    _delay_ms(18);
    PORTD |=  (1 << DHT11_PIN);
    _delay_us(40);
    DDRD  &= ~(1 << DHT11_PIN);  // entrada

    timeout = 1000;
    while ((PIND & (1 << DHT11_PIN)) && timeout--) _delay_us(1);
    if (!timeout) return -1;

    timeout = 1000;
    while (!(PIND & (1 << DHT11_PIN)) && timeout--) _delay_us(1);
    if (!timeout) return -2;

    timeout = 1000;
    while ((PIND & (1 << DHT11_PIN)) && timeout--) _delay_us(1);
    if (!timeout) return -3;

    for (uint8_t i = 0; i < 5; i++) {
        for (uint8_t j = 0; j < 8; j++) {
            while (!(PIND & (1 << DHT11_PIN))) {;}
            _delay_us(30);
            if (PIND & (1 << DHT11_PIN)) {
                data[i] |= (1 << (7 - j));
                while (PIND & (1 << DHT11_PIN)) {;}
            }
        }
    }

    if (data[4] != (uint8_t)(data[0] + data[1] + data[2] + data[3])) return -4;

    return (int8_t) data[2]; // °C entero
}

// ISR TWI
ISR(TWI_vect) {
    uint8_t st = TWSR & 0xF8;

    switch (st) {
        case 0x60:  // own SLA+W
        case 0x68:
        case 0x70:
        case 0x78:
            TWCR = (1<<TWEN)|(1<<TWIE)|(1<<TWINT)|(1<<TWEA);
            break;

        case 0x80:  // data received; ACK
        case 0x90: {
            uint8_t byte = TWDR;

            if (!i2c_expect_data){
                // primer byte = comando
                i2c_last_cmd = byte;

                if (byte == CMD_PREPARE){
                    ready = 0;
                    status_code = STATUS_BUSY;
                    tx_buf[0] = STATUS_BUSY;
                    tx_buf[1] = (uint8_t)temperature; // último conocido
                    request_measure = 1;
                }
                else if (byte == CMD_FORCE_TEMP){
                    i2c_expect_data = 1;   // espera el valor 0/1
                }
                else if (byte == CMD_MODE_AUTO){
                    force_mode = 0;        // vuelve a automático
                }
                // otros: ignorar
            } else {
                // segundo byte = dato del comando previo
                i2c_data_byte  = byte;
                i2c_have_pair  = 1;
                i2c_expect_data= 0;
            }

            TWCR = (1<<TWEN)|(1<<TWIE)|(1<<TWINT)|(1<<TWEA);
        } break;

        case 0xA8:  // own SLA+R
        case 0xB0:
            tx_idx = 0;
            if (ready) {
                tx_buf[0] = status_code;          // 0 si OK, >0 si error
                tx_buf[1] = (uint8_t)temperature;
            } else {
                tx_buf[0] = STATUS_BUSY;
                tx_buf[1] = (uint8_t)temperature;
            }
            TWDR = tx_buf[tx_idx++];
            TWCR = (1<<TWEN)|(1<<TWIE)|(1<<TWINT)|(1<<TWEA);
            break;

        case 0xB8:  // Data transmitted; ACK
            if (tx_idx < data_len) {
                TWDR = tx_buf[tx_idx++];
            }
            TWCR = (1<<TWEN)|(1<<TWIE)|(1<<TWINT)|(1<<TWEA);
            break;

        case 0xC0:  // Data transmitted; NACK
        case 0xC8:  // last data transmitted; ACK
            TWCR = (1<<TWEN)|(1<<TWIE)|(1<<TWINT)|(1<<TWEA);
            break;

        default:
            TWCR = (1<<TWEN)|(1<<TWIE)|(1<<TWINT)|(1<<TWEA);
            break;
    }
}

int main(void) {
    // Motor: salida en PB1 (D9)
    DDRB  |= (1 << MOTOR_PIN);
    PORTB &= ~(1 << MOTOR_PIN); // apagado al inicio

    set_led(0);

    I2C_SlaveInit(SLAVE_ADDRESS);
    TWCR = (1<<TWEN)|(1<<TWEA)|(1<<TWIE)|(1<<TWINT);
    sei();

    while (1) {
        // ¿Llegó un par comando+dato?
        if (i2c_have_pair){
            if (i2c_last_cmd == CMD_FORCE_TEMP){
                force_mode = 1;
                force_val  = (i2c_data_byte ? 1 : 0);
                if (force_val) PORTB |=  (1 << MOTOR_PIN);
                else           PORTB &= ~(1 << MOTOR_PIN);
            }
            i2c_have_pair = 0;
        }

        if (request_measure) {
            int8_t result = read_dht11();

            if (result >= 0) {
                temperature = result;
                status_code = STATUS_OK;
                ready = 1;

                set_led(1); _delay_ms(50); set_led(0);

                // Control motor:
                if (force_mode){
                    if (force_val) PORTB |=  (1 << MOTOR_PIN);
                    else           PORTB &= ~(1 << MOTOR_PIN);
                } else {
                    // AUTO: temp >= 27 -> ON
                    if (temperature >= 27) PORTB |=  (1 << MOTOR_PIN);
                    else                    PORTB &= ~(1 << MOTOR_PIN);
                }

                tx_buf[0] = STATUS_OK;
                tx_buf[1] = (uint8_t)temperature;
            } else {
                status_code = (uint8_t)(-result);
                ready = 1;
                tx_buf[0] = status_code;
                tx_buf[1] = (uint8_t)temperature;
                blink_pattern(status_code);
            }

            request_measure = 0;
            _delay_ms(1000); // DHT11: mínimo 1 s entre lecturas
        }
    }
    return 0;
}
