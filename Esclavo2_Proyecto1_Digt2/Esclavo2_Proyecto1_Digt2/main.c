/*
 * Esclavo2_Proyecto1_Digt2.c
 *
 * Created: 12/08/2025 01:05:09
 * Author : mario
 */ 



#define F_CPU 16000000UL
#include <avr/io.h>
#include <util/delay.h>
#include <stdint.h>
#include "I2C/I2C.h"

#define DHT_PORT  PORTD
#define DHT_DDR   DDRD
#define DHT_PINR  PIND
#define DHT_BIT   PD5          // D5

#define CMD_MEASURE 0x01

static void dht_pin_output(void){ DHT_DDR |=  (1<<DHT_BIT); }
static void dht_pin_input(void) { DHT_DDR &= ~(1<<DHT_BIT); }
static void dht_pin_high(void)  { DHT_PORT |=  (1<<DHT_BIT); } // pull-up si input
static void dht_pin_low(void)   { DHT_PORT &= ~(1<<DHT_BIT); }

static uint8_t dht11_read(uint8_t* tC){
    uint8_t data[5] = {0,0,0,0,0};
    uint8_t i, j;

    // Inicio: pull bajo >=18ms
    dht_pin_output(); dht_pin_low();
    _delay_ms(20);
    dht_pin_input(); dht_pin_high(); // liberar línea, pull-up

    // Respuesta: ~80us low + 80us high
    uint16_t guard=0;
    while ((DHT_PINR & (1<<DHT_BIT))){ if (++guard > 10000) return 0; _delay_us(1); }
    guard=0;
    while (!(DHT_PINR & (1<<DHT_BIT))){ if (++guard > 10000) return 0; _delay_us(1); }
    guard=0;
    while ((DHT_PINR & (1<<DHT_BIT))){ if (++guard > 10000) return 0; _delay_us(1); }

    // 40 bits
    for (i=0; i<5; i++){
        for (j=0; j<8; j++){
            guard=0;
            while (!(DHT_PINR & (1<<DHT_BIT))){ if (++guard > 10000) return 0; _delay_us(1); }
            uint16_t width=0;
            while ((DHT_PINR & (1<<DHT_BIT))){
                _delay_us(1);
                if (++width > 200) break;
            }
            data[i] <<= 1;
            if (width > 40) data[i] |= 1;  // >~40us => '1'
        }
    }

    uint8_t sum = (uint8_t)(data[0] + data[1] + data[2] + data[3]);
    if (sum != data[4]) return 0;

    *tC = data[2]; // entero °C (DHT11)
    return 1;
}

int main(void){
    // Entrada con pull-up
    dht_pin_input(); dht_pin_high();

    // Inicia esclavo I2C con tu librería
    I2C_SlaveInit(0x21);

    uint8_t last_temp_c = 0xFF;

    while(1){
        // Espera comando del maestro (bloqueante hasta SLA+W y dato)
        uint8_t cmd = I2C_SlaveReceive();

        if (cmd == CMD_MEASURE){
            // Medir DHT11
            uint8_t tC=0;
            uint8_t ok = dht11_read(&tC);
            last_temp_c = ok ? tC : 0xFF;

            // Responder al siguiente SLA+R del maestro (bloqueante hasta que lea)
            I2C_SlaveTransmit(last_temp_c);
        }
        // Si recibes otros comandos, puedes ignorarlos o extender protocolo
        _delay_ms(1);
    }
}
