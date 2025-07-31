/*
 * SPI.c
 *
 * Created: 25/07/2025 11:14:32
 *  Author: mario
 */ 
#include "SPI.h"

void SPI_MasterInit(void) {
	// SS (PB2), MOSI (PB3), SCK (PB5) como salidas
	DDRB |= (1 << PB2) | (1 << PB3) | (1 << PB5);
	// MISO (PB4) como entrada
	DDRB &= ~(1 << PB4);

	// Habilitar SPI, modo maestro, reloj fosc/16
	SPCR = (1 << SPE) | (1 << MSTR) | (1 << SPR0);
}

void SPI_SlaveInit(void) {
	// MISO (PB4) como salida
	DDRB |= (1 << PB4);
	// MOSI, SCK, SS como entradas
	DDRB &= ~((1 << PB2) | (1 << PB3) | (1 << PB5));

	// Habilitar SPI en modo esclavo
	SPCR = (1 << SPE);
}

uint8_t SPI_Exchange(uint8_t data) {
	SPDR = data; // Carga el dato a enviar
	while (!(SPSR & (1 << SPIF))); // Espera hasta que se complete
	return SPDR; // Devuelve el dato recibido
}
