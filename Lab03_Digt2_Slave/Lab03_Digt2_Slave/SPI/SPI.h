/*
 * SPI.h
 *
 * Created: 25/07/2025 11:14:51
 *  Author: mario
 */ 

#ifndef SPI_H_
#define SPI_H_

#include <avr/io.h>

// Inicializa SPI como maestro
void SPI_MasterInit(void);

// Inicializa SPI como esclavo
void SPI_SlaveInit(void);

// Intercambia un byte por SPI (envía y recibe simultáneamente)
uint8_t SPI_Exchange(uint8_t data);

#endif /* SPI_H_ */