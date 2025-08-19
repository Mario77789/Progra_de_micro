/*
 * I2C.h
 *
 * Created: 16/08/2025 20:13:29
 *  Author: mario
 */ 

#ifndef I2C_H
#define I2C_H

#include <avr/io.h>
#include <util/twi.h>

#define F_CPU    16000000UL
#define F_SCL    100000UL
#define PRESCALER 1
#define TWBR_VAL (((F_CPU / F_SCL) - 16) / (2 * PRESCALER))

// Maestro
void    I2C_MasterInit(void);
uint8_t I2C_Start(uint8_t address);
void    I2C_Stop(void);
uint8_t I2C_Write(uint8_t data);
uint8_t I2C_ReadACK(void);
uint8_t I2C_ReadNACK(void);

// Esclavo
void    I2C_SlaveInit(uint8_t address);
uint8_t I2C_SlaveReceive(void);
void    I2C_SlaveTransmit(uint8_t data);

#endif
