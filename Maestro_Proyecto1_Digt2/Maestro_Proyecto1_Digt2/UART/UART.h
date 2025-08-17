/*
 * UART.h
 *
 * Created: 10/08/2025 18:18:37
 *  Author: mario
 */ 


#ifndef UART_H_
#define UART_H_

#include <avr/io.h>
#include <stdint.h>

// Inicializa UART0 a la velocidad indicada (baudrate)
void UART_init(uint32_t baud);

// Env�a un car�cter por UART
void UART_sendChar(char c);

// Recibe un car�cter (bloqueante)
char UART_receiveChar(void);

// Devuelve 1 si hay datos por leer, 0 si no
uint8_t UART_available(void);

// Env�a una cadena de caracteres terminada en '\0'
void UART_sendString(const char *s);

// Env�a una cadena seguida de salto de l�nea '\n'
void UART_sendLine(const char *s);

// Env�a un n�mero entero sin signo (0�65535) como texto
void UART_sendU16(uint16_t v);

#endif /* UART_H_ */