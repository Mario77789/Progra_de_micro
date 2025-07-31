/*
 * UART.c
 *
 * Created: 25/07/2025 11:16:05
 *  Author: mario
 */ 
/*
 * UART.c
 * Adaptado para Lab 3 – Comunicación SPI + UART
 * Autor: mario
 */

#define F_CPU 16000000UL

#include <avr/io.h>
#include <stdlib.h> // Para itoa
#include "UART.h"

void UART_init(uint16_t baud) {
	uint16_t ubrr = F_CPU / 16 / baud - 1;
	UBRR0H = (ubrr >> 8);
	UBRR0L = ubrr;
	UCSR0B = (1 << TXEN0) | (1 << RXEN0); // Habilita TX y RX
	UCSR0C = (1 << UCSZ01) | (1 << UCSZ00); // 8 bits, sin paridad, 1 bit de parada
}

void UART_sendChar(char c) {
	while (!(UCSR0A & (1 << UDRE0))); // Espera buffer vacío
	UDR0 = c;
}

void UART_sendString(const char* str) {
	while (*str) UART_sendChar(*str++);
}

bool UART_available(void) {
	return (UCSR0A & (1 << RXC0));
}

char UART_receiveChar(void) {
	while (!UART_available());
	return UDR0;
}

// NUEVA FUNCIÓN para enviar números como texto
void UART_sendNumber(uint16_t num) {
	char buffer[6]; // Hasta 5 dígitos + null
	itoa(num, buffer, 10); // Convierte a decimal
	UART_sendString(buffer);
}
