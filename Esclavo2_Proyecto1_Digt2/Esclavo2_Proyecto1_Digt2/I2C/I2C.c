/*
 * I2C.c
 *
 * Created: 12/08/2025 01:06:28
 *  Author: mario
 */ 

#include "I2C.h"

// ------------------ Maestro ------------------

void I2C_MasterInit(void) {
	TWSR = 0x00;                  // Prescaler = 1
	TWBR = (uint8_t)TWBR_VAL;     // Bit rate
	TWCR = (1 << TWEN);           // Enable TWI
}

uint8_t I2C_Start(uint8_t address) {
	// Genera START
	TWCR = (1 << TWSTA) | (1 << TWEN) | (1 << TWINT);
	while (!(TWCR & (1 << TWINT)));
	// Envía dirección + R/W
	TWDR = address;
	TWCR = (1 << TWEN) | (1 << TWINT);
	while (!(TWCR & (1 << TWINT)));
	return (TWSR & 0xF8);
}

void I2C_Stop(void) {
	// Genera STOP
	TWCR = (1 << TWSTO) | (1 << TWINT) | (1 << TWEN);
	while (TWCR & (1 << TWSTO));
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

// ------------------ Esclavo ------------------

void I2C_SlaveInit(uint8_t address) {
	TWAR = address << 1;                    // Dirección de esclavo
	TWCR = (1 << TWEN) | (1 << TWEA) | (1 << TWINT);
}

uint8_t I2C_SlaveReceive(void) {
	// Espera escritura del maestro
	while (!(TWCR & (1 << TWINT)));
	return TWDR;
}

void I2C_SlaveTransmit(uint8_t data) {
	TWDR = data;
	TWCR = (1 << TWEN) | (1 << TWINT) | (1 << TWEA);
	while (!(TWCR & (1 << TWINT)));
}