/*
 * Lab02_Digital.c
 * Lectura de dos potenciómetros y control USART
 * Autor: mario
 */

#define F_CPU 16000000UL

#include <avr/io.h>
#include <util/delay.h>
#include <stdio.h>

#include "LCD/LCD.h"
#include "ADC/ADC.h"
#include "UART/UART.h"

char s1buf[6];
char s2buf[6];
int16_t S3 = 0;

void mostrarVoltajes(void);
void sendPrompt(void);
void setup(void);

int main(void)
{
	setup();
	sendPrompt();

	while (1)
	{
		mostrarVoltajes();
		_delay_ms(300);

		if (UART_available())
		{
			char c = UART_receiveChar();
			if (c == '+') S3++;
			else if (c == '-') S3--;
			sendPrompt();
		}
	}
}

void setup(void)
{
	ADC_Init();
	LCD_Init();
	UART_init(9600);

	LCD_Clear();
	LCD_SetCursor(0, 0);
	LCD_String("S1:   S2:   S3:");
}

void mostrarVoltajes(void)
{
	uint16_t adc1 = ADC_Read(2); 
	uint16_t adc2 = ADC_Read(5); 

	float v1 = adc1 * 5.0 / 1023.0;
	float v2 = adc2 * 5.0 / 1023.0;

	char temp[6];

	dtostrf(v1, 4, 2, temp);
	snprintf(s1buf, 6, "%sV", temp);
	LCD_SetCursor(1, 0);
	LCD_String(s1buf);

	dtostrf(v2, 4, 2, temp);
	snprintf(s2buf, 6, "%sV", temp);
	LCD_SetCursor(1, 6);
	LCD_String(s2buf);

	char s3buf[5];
	snprintf(s3buf, sizeof(s3buf), "%4d", S3);
	LCD_SetCursor(1, 12);
	LCD_String(s3buf);
}

void sendPrompt(void)
{
	UART_sendString("S1: "); UART_sendString(s1buf);
	UART_sendString(", S2: "); UART_sendString(s2buf);
	UART_sendString(", S3: ");

	char tmp[8];
	snprintf(tmp, sizeof(tmp), "%d", S3);
	UART_sendString(tmp);
	UART_sendString("    ¿ Desea incrementar S3 (+) o decrementarlo (-) ?\r\n");
}
