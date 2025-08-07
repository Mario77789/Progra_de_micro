/*
 * Lab03_Digt2_Slave.c
 *
 * Created: 25/07/2025 11:11:49
 * Author : mario
 */ 

#define F_CPU 16000000UL

#include <avr/io.h>
#include <avr/interrupt.h>

#include "ADC/ADC.h"
#include "SPI/SPI.h"

void mostrarEnLEDs(uint8_t valor) {
	PORTD = (PORTD & 0b00000011) | (valor << 2);  // D2–D7
	PORTB = (PORTB & 0b11111100) | (valor >> 6);  // D8–D9
}

ISR(SPI_STC_vect) {
	static uint8_t estado = 0;
	uint8_t recibido = SPDR;
	uint8_t respuesta = 0x00;

	if (estado == 0 && (recibido == 'A' || recibido == 'B')) {
		if (recibido == 'A')
		respuesta = ADC_Read(7) >> 2;
		else
		respuesta = ADC_Read(6) >> 2;

		SPDR = respuesta;
		estado = 1;
	}
	else {
		// Interpretar cualquier otro valor como dato LED
		mostrarEnLEDs(recibido);
		SPDR = 0x00;
		estado = 0;
	}
}

int main(void) {
	SPI_SlaveInit();
	ADC_Init();

	DDRD |= 0b11111100; // D2–D7
	DDRB |= (1 << PB0) | (1 << PB1); // D8–D9

	SPDR = 0x00;
	SPCR |= (1 << SPIE);
	sei();

	while (1) {
		// Todo se gestiona en la ISR
	}
}