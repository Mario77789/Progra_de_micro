/*
 * Lab04_Digt2_Slave2.c
 *
 * Created: 4/08/2025 22:35:23
 * Author : mario
 */ 

// Lab04_ADC_Slave.c

#define F_CPU 16000000UL
#include <avr/io.h>
#include <util/delay.h>
#include "I2C/I2C.h"
#include "ADC/ADC.h"

#define CMD_PREP 0x01

static uint16_t adc_last = 0;

int main(void) {
	ADC_Init();
	I2C_SlaveInit(0x21);

	while (1) {
		if (!(TWCR & (1<<TWINT))) continue;
		uint8_t status = TWSR & 0xF8;
		switch (status) {
			case 0x60: // SLA+W recibida
			TWCR = (1<<TWINT)|(1<<TWEN)|(1<<TWEA);
			break;
			case 0x80: { // byte de comando recibido
				uint8_t cmd = TWDR;
				TWCR = (1<<TWINT)|(1<<TWEN)|(1<<TWEA);
				if (cmd == CMD_PREP) {
					adc_last = ADC_Read(6);
				}
				break;
			}
			case 0xA8: // SLA+R recibida
			TWDR = (adc_last >> 8);
			TWCR = (1<<TWINT)|(1<<TWEN)|(1<<TWEA);
			break;
			case 0xB8: // DAT transmitido + ACK
			TWDR = (adc_last & 0xFF);
			TWCR = (1<<TWINT)|(1<<TWEN)|(1<<TWEA);
			break;
			case 0xC0: // DAT transmitido + NACK
			case 0xA0: // STOP
			default:
			TWCR = (1<<TWINT)|(1<<TWEN)|(1<<TWEA);
			break;
		}
	}
}
