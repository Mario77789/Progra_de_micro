/*
 * LCD.h
 *
 * Created: 18/07/2025 11:03:31
 *  Author: mario
 */ 
#ifndef LCD_H
#define LCD_H

#include <avr/io.h>

#define LCD_RS PC0  // 
#define LCD_E  PC1  //

void LCD_Init(void);
void LCD_Command(uint8_t cmd);
void LCD_Char(char data);
void LCD_String(const char *str);
void LCD_Clear(void);
void LCD_SetCursor(uint8_t row, uint8_t col);

#endif
