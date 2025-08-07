/*
 * I2C.c
 *
 * Created: 1/08/2025 09:03:44
 *  Author: mario
 */ 



#include "I2C.h"
#include <util/delay.h>

// ----------- Maestro -----------

void I2C_MasterInit(void) {
	TWSR = 0x00;                  // Prescaler = 1
	TWBR = (uint8_t)TWBR_VAL;     // Baud rate
	TWCR = (1 << TWEN);           // Habilita TWI
}

uint8_t I2C_Start(uint8_t address) {
	// Enviar condición de inicio
	TWCR = (1 << TWSTA) | (1 << TWEN) | (1 << TWINT);
	while (!(TWCR & (1 << TWINT)));

	// Enviar dirección
	TWDR = address;
	TWCR = (1 << TWEN) | (1 << TWINT);
	while (!(TWCR & (1 << TWINT)));

	return (TWSR & 0xF8);
}

void I2C_Stop(void) {
	TWCR = (1 << TWSTO) | (1 << TWINT) | (1 << TWEN);
	// No esperar a que se borre TWSTO, solo dar margen de tiempo
	_delay_us(10);
}

uint8_t I2C_Write(uint8_t data) {
	TWDR = data;
	TWCR = (1 << TWEN) | (1 << TWINT);
	while (!(TWCR & (1 << TWINT)));

	return (TWSR & 0xF8);
}

uint8_t I2C_ReadACK(void) {
	TWCR = (1 << TWEN) | (1 << TWINT) | (1 << TWEA);
	while (!(TWCR & (1 << TWINT)));
	return TWDR;
}

uint8_t I2C_ReadNACK(void) {
	TWCR = (1 << TWEN) | (1 << TWINT);
	while (!(TWCR & (1 << TWINT)));
	return TWDR;
}

// ----------- Esclavo -----------

void I2C_SlaveInit(uint8_t address) {
	TWAR = (address << 1);  // Dirección del esclavo
	TWCR = (1 << TWEN) | (1 << TWEA) | (1 << TWINT);
}

uint8_t I2C_SlaveReceive(void) {
	while (!(TWCR & (1 << TWINT)));
	return TWDR;
}

void I2C_SlaveTransmit(uint8_t data) {
	// Esperar solicitud de lectura
	while (!(TWCR & (1 << TWINT)));
	uint8_t estado = TWSR & 0xF8;

	if (estado == 0xA8 || estado == 0xB8) {
		TWDR = data;
		TWCR = (1 << TWEN) | (1 << TWINT) | (1 << TWEA);
		while (!(TWCR & (1 << TWINT)));
	}

	TWCR = (1 << TWEN) | (1 << TWEA) | (1 << TWINT);
}