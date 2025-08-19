/*
 * Esclavo2_Proyecto1_Digt2.c
 *
 * Created: 12/08/2025 01:05:09
 * Author : mario
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

ISR(TWI_vect) {
    uint8_t st = TWSR & 0xF8;

    switch (st) {
        case 0x60:  // own SLA+W
        case 0x68:  // arbitration lost; own SLA+W
        case 0x70:  // general call (no usado)
        case 0x78:  // arb lost; general call
            TWCR = (1<<TWEN)|(1<<TWIE)|(1<<TWINT)|(1<<TWEA);
            break;

        case 0x80:  // data received; ACK
        case 0x90:  // data after general call; ACK
        {
            uint8_t cmd = TWDR;
            if (cmd == CMD_PREPARE) {
                ready = 0;
                status_code = STATUS_BUSY;
                tx_buf[0] = STATUS_BUSY;
                tx_buf[1] = (uint8_t)temperature; // último conocido
                request_measure = 1;               // el loop hará la lectura
            }
            TWCR = (1<<TWEN)|(1<<TWIE)|(1<<TWINT)|(1<<TWEA);
        } break;

        case 0xA8:  // own SLA+R
        case 0xB0:  // arbitration lost; own SLA+R
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

        case 0xB8:  // data transmitted; ACK
            if (tx_idx < data_len) {
                TWDR = tx_buf[tx_idx++];
            }
            TWCR = (1<<TWEN)|(1<<TWIE)|(1<<TWINT)|(1<<TWEA);
            break;

        case 0xC0:  // data transmitted; NACK
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

    // Setup original
    set_led(0);

    I2C_SlaveInit(SLAVE_ADDRESS);   // deja esta llamada como la tienes
    TWCR = (1<<TWEN)|(1<<TWEA)|(1<<TWIE)|(1<<TWINT); // habilita TWIE
    sei();

    while (1) {
        if (request_measure) {
            int8_t result = read_dht11();

            if (result >= 0) {
                temperature = result;
                status_code = STATUS_OK;
                ready = 1;

                set_led(1); _delay_ms(50); set_led(0);

                // Motor ON si temperatura == 29 °C, OFF en otro caso
                if (temperature >= 27) PORTB |=  (1 << MOTOR_PIN);
                else                    PORTB &= ~(1 << MOTOR_PIN);

                tx_buf[0] = STATUS_OK;
                tx_buf[1] = (uint8_t)temperature;
            } else {
                status_code = (uint8_t)(-result);  // 1..4 típicos
                ready = 1;
                // Sin cambios adicionales de lógica: motor conserva su último estado
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
