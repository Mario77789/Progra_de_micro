#define F_CPU 16000000UL
#include <avr/io.h>
#include <util/delay.h>

// Pines de control
#define LCD_RS PC0
#define LCD_E  PC1

void LCD_EnablePulse(void) {
	PORTC |= (1 << LCD_E);
	_delay_us(20);           // ?? Aumentado de 1 us a 10 us
	PORTC &= ~(1 << LCD_E);
	_delay_us(200);          // ?? Aumentado de 100 us a 200 us
}

void LCD_SendByte(uint8_t data) {
	// D0–D5 ? PD2–PD7
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
	PORTC &= ~(1 << LCD_RS);  // RS = 0 (modo comando)
	LCD_SendByte(cmd);
	_delay_ms(5);             // ?? Aumentado de 2 ms a 5 ms
}

void LCD_Char(char data) {
	PORTC |= (1 << LCD_RS);   // RS = 1 (modo dato)
	LCD_SendByte(data);
	_delay_ms(2);             // ?? Aumentado de 100 us a 2 ms
}

void LCD_String(const char *str) {
	while (*str) {
		LCD_Char(*str++);
	}
}

void LCD_SetCursor(uint8_t row, uint8_t col) {
	uint8_t pos = (row == 0) ? col : (0x40 + col);
	LCD_Command(0x80 | pos);
}

void LCD_Clear(void) {
	LCD_Command(0x01);
	_delay_ms(5);             // ?? Aumentado de 2 ms a 5 ms
}

void LCD_Init(void) {
	DDRC |= (1 << LCD_RS) | (1 << LCD_E); // RS y E como salidas
	DDRD |= 0b11111100;                   // PD2–PD7 como salidas (D0–D5)
	DDRB |= (1 << PB0) | (1 << PB1);      // PB0 y PB1 como salidas (D6 y D7)

	_delay_ms(100);           // ?? Aumentado a 100 ms tras encendido

	LCD_Command(0x38);        // Modo 8 bits, 2 líneas, 5x8 puntos
	LCD_Command(0x0C);        // Display ON, cursor OFF
	LCD_Command(0x06);        // Auto-incremento
	LCD_Clear();              // Limpia pantalla
}

int main(void) {
	LCD_Init();

	LCD_SetCursor(0, 0);
	LCD_String("Hola");

	while (1);
}
