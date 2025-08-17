/*
 * LCD8bits.h
 *
 * Created: 10/08/2025 18:18:16
 *  Author: mario
 */ 


#ifndef LCD8BITS_H_
#define LCD8BITS_H_

#include <avr/io.h>
#include <util/delay.h>

// Pines de control
#define LCD_RS PC0
#define LCD_E  PC1

void LCD_init(void);
void LCD_sendCommand(uint8_t cmd);
void LCD_sendChar(char data);
void LCD_sendString(const char* str);
void LCD_clear(void);
void LCD_setCursor(uint8_t row, uint8_t col);
void LCD_sendStringXY(uint8_t row, uint8_t col, const char* str);

#endif /* LCD8BITS_H_ */