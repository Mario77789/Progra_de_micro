/*
 * ADC.c
 *
 * Created: 4/08/2025 22:36:24
 *  Author: mario
 */ 

#include <avr/io.h>

void ADC_Init(void) {
	ADMUX = (1 << REFS0);  // Referencia AVCC (5V)
	ADCSRA = (1 << ADEN)               // Habilita ADC
	| (1 << ADPS2) | (1 << ADPS1); // Prescaler de 64 (~250kHz @16MHz)

	// Deshabilita entrada digital en ADC6 (bit 6 de DIDR0)
	DIDR0 |= (1 << 6);  // Más claro usar ADC6D que "6"
}

uint16_t ADC_Read(uint8_t canal) {
	ADMUX = (ADMUX & 0xF0) | (canal & 0x0F); // Mantiene bits REFS0 y limpia MUX
	ADCSRA |= (1 << ADSC);                  // Inicia conversión
	while (ADCSRA & (1 << ADSC));           // Espera a que termine
	return ADC;                             // Devuelve el valor de 10 bits
}


