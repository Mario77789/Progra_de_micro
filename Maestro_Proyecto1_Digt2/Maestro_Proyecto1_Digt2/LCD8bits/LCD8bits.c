/*
 * LCD8bits.c
 *
 * Created: 10/08/2025 18:18:01
 *  Author: mario
 */ 

#include "LCD8bits.h"

// Pulso de habilitación
static void pulse_enable(void)
{
	PORTC |=  (1 << LCD_E);
	_delay_us(1);
	PORTC &= ~(1 << LCD_E);
	_delay_ms(2);
}

// Escribe 8 bits repartidos en PORTD y PORTB
static void write8bits(uint8_t val)
{
	// D0–D5 ? PD2–PD7
	PORTD = (PORTD & 0x03) | ((val & 0x3F) << 2);
	// D6 ? PB0
	if (val & (1 << 6)) PORTB |=  (1 << PB0);
	else                PORTB &= ~(1 << PB0);
	// D7 ? PB1
	if (val & (1 << 7)) PORTB |=  (1 << PB1);
	else                PORTB &= ~(1 << PB1);
}

void LCD_sendCommand(uint8_t cmd)
{
	PORTC &= ~(1 << LCD_RS);  // RS=0
	write8bits(cmd);
	pulse_enable();
}

void LCD_sendChar(char data)
{
	PORTC |=  (1 << LCD_RS);  // RS=1
	write8bits((uint8_t)data);
	pulse_enable();
}

void LCD_sendString(const char* str)
{
	while (*str) LCD_sendChar(*str++);
}

void LCD_clear(void)
{
	LCD_sendCommand(0x01);
	_delay_ms(2);
}

void LCD_setCursor(uint8_t row, uint8_t col)
{
	uint8_t pos = (row == 0) ? 0x00 : 0x40;
	LCD_sendCommand(0x80 + pos + col);
}

void LCD_sendStringXY(uint8_t row, uint8_t col, const char* str)
{
	LCD_setCursor(row, col);
	LCD_sendString(str);
}

void LCD_init(void)
{
	// Configurar pines de control
	DDRC |= (1 << LCD_RS) | (1 << LCD_E);
	// Configurar pines de datos PD2–PD7 y PB0–PB1
	DDRD |= 0xFC;
	DDRB |= (1 << PB0) | (1 << PB1);

	_delay_ms(20); // Se espera para la inicialización despues de setear puertos

	// Secuencia de inicialización 8-bits
	LCD_sendCommand(0x38); _delay_ms(5);
	LCD_sendCommand(0x38); _delay_us(100);
	LCD_sendCommand(0x38);

	LCD_sendCommand(0x0C); _delay_us(100);
	LCD_sendCommand(0x01); _delay_ms(2);
	LCD_sendCommand(0x06); _delay_us(100);
}