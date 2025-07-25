/*
 * UART.c
 *
 * Created: 24/07/2025 23:26:34
 *  Author: mario
 */ 



#define F_CPU 16000000UL  

#include <avr/io.h>
#include "UART.h"

void UART_init(uint16_t baud) {
	uint16_t ubrr = F_CPU / 16 / baud - 1;
	UBRR0H = (ubrr >> 8);
	UBRR0L = ubrr;
	UCSR0B = (1 << TXEN0) | (1 << RXEN0);
	UCSR0C = (1 << UCSZ01) | (1 << UCSZ00); // 8 bits
}

void UART_sendChar(char c) {
	while (!(UCSR0A & (1 << UDRE0)));
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


