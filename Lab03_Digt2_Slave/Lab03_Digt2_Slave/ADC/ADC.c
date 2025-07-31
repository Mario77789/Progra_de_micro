/*
 * ADC.c
 *
 * Created: 25/07/2025 11:15:22
 *  Author: mario
 */ 
#include <avr/io.h>

void ADC_Init(void) {
	ADMUX = (1 << REFS0);              // Referencia AVCC
	ADCSRA = (1 << ADEN)               // Habilita el ADC
	| (1 << ADPS2) | (1 << ADPS1); // Prescaler 64 (250 kHz)
}

uint16_t ADC_Read(uint8_t canal) {
	ADMUX = (ADMUX & 0xF0) | (canal & 0x0F); // Seleccionar canal
	ADCSRA |= (1 << ADSC);                  // Iniciar conversión
	while (ADCSRA & (1 << ADSC));           // Esperar
	return ADC;                             // Retornar resultado (10 bits)
}

