#define F_CPU 16000000UL
#include <avr/io.h>
#include <util/delay.h>
#include <stdio.h>

// Control LCD
#define LCD_RS PC0  // A0
#define LCD_E  PC1  // A1

// Datos LCD
#define LCD_D0 PD2  // D2
#define LCD_D1 PD3  // D3
#define LCD_D2 PD4  // D4
#define LCD_D3 PD5  // D5
#define LCD_D4 PD6  // D6
#define LCD_D5 PD7  // D7
#define LCD_D6 PB0  // D8
#define LCD_D7 PB1  // D9

// ------------------- LCD -------------------

void LCD_EnablePulse(void) {
	PORTC |= (1 << LCD_E);
	_delay_us(1);
	PORTC &= ~(1 << LCD_E);
	_delay_us(100);
}

void LCD_SendByte(uint8_t data) {
	// Limpiar pines
	PORTD &= ~((1 << LCD_D0)|(1 << LCD_D1)|(1 << LCD_D2)|(1 << LCD_D3)|(1 << LCD_D4)|(1 << LCD_D5));
	PORTB &= ~((1 << LCD_D6)|(1 << LCD_D7));

	// PORTD: D0–D5
	if (data & (1 << 0)) PORTD |= (1 << LCD_D0);
	if (data & (1 << 1)) PORTD |= (1 << LCD_D1);
	if (data & (1 << 2)) PORTD |= (1 << LCD_D2);
	if (data & (1 << 3)) PORTD |= (1 << LCD_D3);
	if (data & (1 << 4)) PORTD |= (1 << LCD_D4);
	if (data & (1 << 5)) PORTD |= (1 << LCD_D5);

	// PORTB: D6–D7
	if (data & (1 << 6)) PORTB |= (1 << LCD_D6);
	if (data & (1 << 7)) PORTB |= (1 << LCD_D7);

	LCD_EnablePulse();
}

void LCD_Command(uint8_t cmd) {
	PORTC &= ~(1 << LCD_RS); // RS = 0
	LCD_SendByte(cmd);
	_delay_ms(2);
}

void LCD_Char(char data) {
	PORTC |= (1 << LCD_RS); // RS = 1
	LCD_SendByte(data);
	_delay_us(100);
}

void LCD_String(const char *str) {
	while (*str) LCD_Char(*str++);
}

void LCD_SetCursor(uint8_t row, uint8_t col) {
	uint8_t pos = (row == 0) ? col : 0x40 + col;
	LCD_Command(0x80 | pos);
}

void LCD_Clear(void) {
	LCD_Command(0x01);
	_delay_ms(2);
}

void LCD_Init(void) {
	_delay_ms(50);
	LCD_Command(0x38); // 8-bit, 2 líneas
	LCD_Command(0x0C); // Display ON
	LCD_Command(0x06); // Entrada automática
	LCD_Clear();
}

// ------------------- ADC -------------------

void ADC_Init(void) {
	ADMUX = (1 << REFS0); // AVcc
	ADCSRA = (1 << ADEN) | (1 << ADPS2) | (1 << ADPS1); // Prescaler 64
}

uint16_t ADC_Read(uint8_t channel) {
	ADMUX = (ADMUX & 0xF0) | (channel & 0x0F); // Canal ADCx
	ADCSRA |= (1 << ADSC);
	while (ADCSRA & (1 << ADSC));
	return ADC;
}

// ------------------- Mostrar voltaje -------------------

void LCD_PrintVoltFormatted(uint8_t channel, uint8_t col) {
	char buffer[8];
	uint16_t adc_value = ADC_Read(channel);
	uint16_t mv = (adc_value * 5000UL) / 1023; // milivoltios
	uint8_t entero = mv / 1000;
	uint8_t decimal = (mv % 1000) / 10;

	snprintf(buffer, sizeof(buffer), "%1d.%02uV", entero, decimal);
	LCD_SetCursor(1, col);
	LCD_String(buffer);
}

// ------------------- MAIN -------------------

int main(void) {
	// Configurar pines LCD
	DDRC |= (1 << LCD_RS) | (1 << LCD_E);
	DDRD |= (1 << LCD_D0) | (1 << LCD_D1) | (1 << LCD_D2) |
	(1 << LCD_D3) | (1 << LCD_D4) | (1 << LCD_D5);
	DDRB |= (1 << LCD_D6) | (1 << LCD_D7);

	LCD_Init();
	ADC_Init();

	while (1) {
		LCD_SetCursor(0, 0);
		LCD_String("S1:   S2:");

		LCD_PrintVoltFormatted(2, 0);  // A2
		LCD_PrintVoltFormatted(5, 6);  // A5

		_delay_ms(500);
	}
}
