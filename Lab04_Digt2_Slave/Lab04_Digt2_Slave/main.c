/*
 * Lab04_Digt2_Slave.c
 *
 * Created: 1/08/2025 08:53:26
 * Author : mario
 */ 

// Lab04_Counter_Slave.c

#define F_CPU 16000000UL
#include <avr/io.h>
#include <avr/interrupt.h>
#include "I2C/I2C.h"

#define BTN_INC PB0
#define BTN_DEC PB1
#define CMD_PREP 0x01

volatile uint8_t contador = 0;

void actualizarLEDs(void) {
	PORTD = (PORTD & 0xF0) | (contador & 0x0F);
}

ISR(PCINT0_vect) {
	static uint8_t prev = 0xFF;
	uint8_t curr = PINB & ((1<<BTN_INC)|(1<<BTN_DEC));
	uint8_t diff = prev ^ curr;
	if ((diff & (1<<BTN_INC)) && !(curr & (1<<BTN_INC)) && contador < 15) contador++;
	if ((diff & (1<<BTN_DEC)) && !(curr & (1<<BTN_DEC)) && contador > 0)  contador--;
	prev = curr;
	actualizarLEDs();
}

int main(void) {
	// Pines LEDs y botones
	DDRD |= 0x0F;
	DDRB &= ~((1<<BTN_INC)|(1<<BTN_DEC));
	PORTB |= (1<<BTN_INC)|(1<<BTN_DEC);
	PCICR |= (1<<PCIE0);
	PCMSK0 |= (1<<PCINT0)|(1<<PCINT1);
	sei();

	I2C_SlaveInit(0x20);

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
					// No hay acción extra: el contador ya está actualizado
				}
				break;
			}
			case 0xA8: // SLA+R recibida
			TWDR = contador;
			TWCR = (1<<TWINT)|(1<<TWEN)|(1<<TWEA);
			break;
			case 0xB8: // DAT transmitido + ACK
			case 0xC0: // DAT transmitido + NACK
			case 0xA0: // STOP o repeated START
			default:
			TWCR = (1<<TWINT)|(1<<TWEN)|(1<<TWEA);
			break;
		}
	}
}

