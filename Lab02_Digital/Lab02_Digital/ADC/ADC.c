/*
 * ADC.c
 *
 * Created: 18/07/2025 11:03:00
 * Author: mario
 */

#include "ADC.h"

void ADC_Init(void) {
	ADMUX = (1 << REFS0); // Referencia AVcc con capacitor en AREF
	ADCSRA = (1 << ADEN) | (1 << ADPS2) | (1 << ADPS1); // Prescaler 64
}

uint16_t ADC_Read(uint8_t channel) {
	// Mantiene la referencia AVcc (REFS0) y cambia solo los bits del canal (MUX[3:0])
	ADMUX = (ADMUX & 0xF0) | (channel & 0x0F);  
	ADCSRA |= (1 << ADSC); // Inicia conversión
	while (ADCSRA & (1 << ADSC)); // Espera a que termine
	return ADC;
}


