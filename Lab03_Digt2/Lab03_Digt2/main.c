/*
 * Lab03_Digt2.c
 *
 * Created: 25/07/2025 11:01:21
 * Author : mario
 */ 

#define F_CPU 16000000UL

#include <avr/io.h>
#include <util/delay.h>
#include <stdlib.h>

#include "UART/UART.h"
#include "SPI/SPI.h"

uint8_t modo = 'R';

void mostrarEnLEDs(uint8_t valor) {
	PORTD = (PORTD & 0b00000011) | (valor << 2);  // D2–D7
	PORTB = (PORTB & 0b11111100) | (valor >> 6);  // D8–D9
}

void limpiarBufferUART(void) {
	while (UART_available()) {
		UART_receiveChar();
		_delay_us(100);
	}
}

int main(void) {
	UART_init(9600);
	SPI_MasterInit();

	DDRD |= 0b11111100;
	DDRB |= (1 << PB0) | (1 << PB1) | (1 << PB2);
	PORTB |= (1 << PB2);  // SS HIGH

	uint8_t pot1 = 0, pot2 = 0;

	while (1) {
		if (UART_available()) {
			char c = UART_receiveChar();

			if (c == 'R' || c == 'r') {
				modo = 'R';
				UART_sendString("Modo Lectura Activado\r\n");
				limpiarBufferUART();
				continue;
			}

			else if (c == 'E' || c == 'e') {
				modo = 'E';
				UART_sendString("Modo Envío Activado\r\n");
				limpiarBufferUART();

				UART_sendString("Ingresa un valor (0-255): ");
				char buffer[5] = {0};
				uint8_t i = 0;

				while (1) {
					char c_in = UART_receiveChar();
					if (c_in == '\r' || c_in == '\n') break;
					if (i < 4) {
						buffer[i++] = c_in;
						UART_sendChar(c_in);
					}
				}
				buffer[i] = '\0';

				uint16_t num = atoi(buffer);
				if (num > 255) num = 255;

				UART_sendString("\r\nValor ingresado: ");
				UART_sendNumber(num);
				UART_sendString("\r\n");

				mostrarEnLEDs((uint8_t)num);
				PORTB &= ~(1 << PB2);
				SPI_Exchange((uint8_t)num);
				PORTB |= (1 << PB2);

				continue;
			}
		}

		if (modo == 'R') {
			PORTB &= ~(1 << PB2);
			SPI_Exchange('A');           // Comando para leer potenciómetro 1
			_delay_us(100);
			pot1 = SPI_Exchange(0x00);   // Leer respuesta
			PORTB |= (1 << PB2);

			_delay_ms(5);

			PORTB &= ~(1 << PB2);
			SPI_Exchange('B');           // Comando para leer potenciómetro 2
			_delay_us(100);
			pot2 = SPI_Exchange(0x00);
			PORTB |= (1 << PB2);

			UART_sendString("P1: ");
			UART_sendNumber(pot1);
			UART_sendString(" | P2: ");
			UART_sendNumber(pot2);
			UART_sendString("\r\n");

			_delay_ms(500);
		}
	}
}