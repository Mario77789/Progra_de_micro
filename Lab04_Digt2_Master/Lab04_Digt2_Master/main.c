/*
 * Lab04_Digt2_Master.c
 *
 * Created: 1/08/2025
 * Author : mario
 */

// Lab04_Master_Turnos.c

#define F_CPU 16000000UL
#include <avr/io.h>
#include <util/delay.h>
#include <stdio.h>
#include "LCD/LCD.h"
#include "I2C/I2C.h"

#define SLAVE_CONT  0x20
#define SLAVE_ADC   0x21
#define CMD_PREP    0x01   // cualquier byte de “prepare”

char buffer[17];

int main(void) {
	LCD_Init();
	I2C_MasterInit();

	uint8_t   contador = 0xFF;
	uint16_t  adc_val  = 0xFFFF;

	LCD_Clear();
	LCD_SetCursor(0,0);
	LCD_String("S1: ADC   S2:CONT");

	while (1) {
		// ———— Contador ————
		// 1) Preparar contador
		if (I2C_Start(SLAVE_CONT << 1 | 0) == 0x18) {  // SLA+W ACK
			I2C_Write(CMD_PREP);
		}
		I2C_Stop();
		_delay_ms(5);

		// 2) Leer contador
		if (I2C_Start(SLAVE_CONT << 1 | 1) == 0x40) {  // SLA+R ACK
			uint8_t val = I2C_ReadNACK();
			I2C_Stop();
			if (val != contador) {
				contador = val;
				LCD_SetCursor(1,13);
				snprintf(buffer, sizeof(buffer), "%2u", contador);
				LCD_String(buffer);
			}
			} else {
			I2C_Stop();
			LCD_SetCursor(1,13);
			LCD_String("Err");
		}

		_delay_ms(10);

		// ———— ADC ————
		// 1) Preparar ADC
		if (I2C_Start(SLAVE_ADC << 1 | 0) == 0x18) {
			I2C_Write(CMD_PREP);
		}
		I2C_Stop();
		_delay_ms(5);

		// 2) Leer ADC (2 bytes)
		if (I2C_Start(SLAVE_ADC << 1 | 1) == 0x40) {
			uint8_t high = I2C_ReadACK();
			uint8_t low  = I2C_ReadNACK();
			I2C_Stop();
			uint16_t val = ((uint16_t)high << 8) | low;
			if (val != adc_val) {
				adc_val = val;
				LCD_SetCursor(1,4);
				snprintf(buffer, sizeof(buffer), "%4u", adc_val);
				LCD_String(buffer);
			}
			} else {
			I2C_Stop();
			LCD_SetCursor(1,4);
			LCD_String("Err ");
		}

		_delay_ms(100);
	}
}
