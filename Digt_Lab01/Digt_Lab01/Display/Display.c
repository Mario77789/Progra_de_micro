/*
 * Display.c
 *
 * Created: 11/07/2025 11:21:36
 *  Author: mario
 */ 

#include "Display.h"

// Segmentos del display a–g conectados en PD0 a PD6
static const uint8_t numeros[10] = {
	63,  // 0
	6,   // 1
	91,  // 2
	79,  // 3
	102, // 4
	109, // 5
	125, // 6
	7,   // 7
	127, // 8
	111  // 9
};

void mostrar_display(uint8_t valor) {
	if (valor > 9) return;
	PORTD = numeros[valor];  // PD0–PD6 segmentos (a-g)
}
