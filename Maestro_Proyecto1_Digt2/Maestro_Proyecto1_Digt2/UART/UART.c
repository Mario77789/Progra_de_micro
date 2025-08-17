/*
 * UART.c
 *
 * Created: 10/08/2025 18:18:26
 *  Author: mario
 */ 

#ifndef F_CPU
#define F_CPU 16000000UL
#endif

#include <util/delay.h>
#include "UART.h"

void UART_init(uint32_t baud)
{
	// Calcula UBRR para 16 MHz y modo normal (divisor 16)
	uint16_t ubrr = (F_CPU / (16UL * baud)) - 1;
	UBRR0H = (uint8_t)(ubrr >> 8);
	UBRR0L = (uint8_t)ubrr;

	// Habilita transmisión y recepción
	UCSR0B = (1 << TXEN0) | (1 << RXEN0);

	// Frame: 8 bits de datos, 1 bit de parada, sin paridad
	UCSR0C = (1 << UCSZ01) | (1 << UCSZ00);
}

void UART_sendChar(char c)
{
	// Espera a que el buffer de transmisión esté listo
	while (!(UCSR0A & (1 << UDRE0)));
	UDR0 = c;
}

char UART_receiveChar(void)
{
	// Espera a que haya datos recibidos
	while (!(UCSR0A & (1 << RXC0)));
	return UDR0;
}

uint8_t UART_available(void)
{
	// Comprueba si hay datos pendientes de lectura
	return (UCSR0A & (1 << RXC0)) != 0;
}

void UART_sendString(const char *s)
{
	while (*s)
	UART_sendChar(*s++);
}

void UART_sendLine(const char *s)
{
	UART_sendString(s);
	UART_sendChar('\n');  // Solo LF (para Serial Plotter)
	// Si prefieres CR+LF: UART_sendChar('\r'); UART_sendChar('\n');
}

void UART_sendU16(uint16_t v)
{
	char buf[6]; // hasta 65535 + '\0'
	uint8_t i = 0;

	if (v == 0)
	{
		UART_sendChar('0');
		return;
	}

	while (v > 0 && i < sizeof(buf) - 1)
	{
		buf[i++] = '0' + (v % 10);
		v /= 10;
	}

	while (i--)
	UART_sendChar(buf[i]);
}