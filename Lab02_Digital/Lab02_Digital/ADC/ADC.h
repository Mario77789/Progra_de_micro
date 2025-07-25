/*
 * ADC.h
 *
 * Created: 18/07/2025 11:03:10
 *  Author: mario
 */ 

#ifndef ADC_H
#define ADC_H

#include <avr/io.h>

void ADC_Init(void);
uint16_t ADC_Read(uint8_t channel);

#endif
