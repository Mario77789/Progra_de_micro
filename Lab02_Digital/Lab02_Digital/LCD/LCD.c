/*
 * LCD.c
 *
 * Modo 8 bits
 * Author: mario
 */

#define F_CPU 16000000UL
#include "LCD.h"
#include <util/delay.h>

void LCD_EnablePulse(void) {
	PORTC |= (1 << LCD_E);
	_delay_us(1);
	PORTC &= ~(1 << LCD_E);
	_delay_us(100);
}

void LCD_SendByte(uint8_t data) {
	// D0–D5 en PD2–PD7
	for (uint8_t i = 0; i < 6; i++) {
		if (data & (1 << i))
		PORTD |= (1 << (i + 2));
		else
		PORTD &= ~(1 << (i + 2));
	}
	// D6 ? PB0
	if (data & (1 << 6)) PORTB |= (1 << PB0);
	else PORTB &= ~(1 << PB0);

	// D7 ? PB1
	if (data & (1 << 7)) PORTB |= (1 << PB1);
	else PORTB &= ~(1 << PB1);

	LCD_EnablePulse();
}

void LCD_Command(uint8_t cmd) {
	PORTC &= ~(1 << LCD_RS);
	LCD_SendByte(cmd);
	_delay_ms(2);
}

void LCD_Char(char data) {
	PORTC |= (1 << LCD_RS);
	LCD_SendByte(data);
	_delay_us(100);
}

void LCD_String(const char *str) {
	while (*str) LCD_Char(*str++);
}

void LCD_SetCursor(uint8_t row, uint8_t col) {
	uint8_t pos = (row == 0) ? col : (0x40 + col);
	LCD_Command(0x80 | pos);
}

void LCD_Clear(void) {
	LCD_Command(0x01);
	_delay_ms(2);
}

void LCD_Init(void) {
	DDRC |= (1 << LCD_RS) | (1 << LCD_E);
	DDRD |= 0b11111100; // PD2–PD7
	DDRB |= (1 << PB0) | (1 << PB1); // D6, D7

	_delay_ms(50);
	LCD_Command(0x38); // 8 bits, 2 líneas
	LCD_Command(0x0C); // Display ON
	LCD_Command(0x06); // Auto-incremento
	LCD_Clear();
}
