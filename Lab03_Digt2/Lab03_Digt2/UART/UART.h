/*
 * UART.h
 *
 * Created: 25/07/2025 11:15:54
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
void UART_sendNumber(uint16_t num);

#endif