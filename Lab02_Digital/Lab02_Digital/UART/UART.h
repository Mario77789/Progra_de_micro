/*
 * UART.h
 *
 * Created: 24/07/2025 23:26:44
 *  Author: mario
 */ 



#ifndef UART_H
#define UART_H

#include <avr/io.h>
#include <stdbool.h>

void UART_init(uint16_t baud);
void UART_sendChar(char c);
void UART_sendString(const char* str);
bool UART_available(void);
char UART_receiveChar(void);

#endif

