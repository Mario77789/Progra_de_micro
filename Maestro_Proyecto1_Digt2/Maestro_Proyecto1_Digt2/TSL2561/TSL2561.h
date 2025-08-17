/*
 * TSL2561.h
 *
 * Created: 10/08/2025 19:04:59
 *  Author: mario
 */ 


#ifndef TSL2561_H
#define TSL2561_H

#include <avr/io.h>
#include <stdint.h>
#include <stdbool.h>

// Dirección por defecto del GY-2561 (TSL2561) cuando ADDR está flotante
#define TSL2561_ADDR_DEFAULT  0x39  // también puede ser 0x29 o 0x49

// Bits de comando
#define TSL2561_CMD           0x80
#define TSL2561_CMD_WORD      0x20  // lectura palabra (opcional)
#define TSL2561_CMD_BLOCK     0x10  // lectura bloque (opcional)

// Registros
#define TSL2561_REG_CONTROL   0x00
#define TSL2561_REG_TIMING    0x01
#define TSL2561_REG_ID        0x0A
#define TSL2561_REG_DATA0L    0x0C
#define TSL2561_REG_DATA0H    0x0D
#define TSL2561_REG_DATA1L    0x0E
#define TSL2561_REG_DATA1H    0x0F

// Control
#define TSL2561_POWER_ON      0x03
#define TSL2561_POWER_OFF     0x00

// Timing (integración) bits [1:0]
typedef enum {
    TSL2561_INTEG_13MS  = 0x00,  // ~13.7 ms
    TSL2561_INTEG_101MS = 0x01,  // ~101 ms
    TSL2561_INTEG_402MS = 0x02   // ~402 ms (recomendado)
} tsl2561_integration_t;

// Gain (bit 4 del registro TIMING)
typedef enum {
    TSL2561_GAIN_1X  = 0x00,
    TSL2561_GAIN_16X = 0x10
} tsl2561_gain_t;

bool    tsl2561_init(uint8_t i2c_addr, tsl2561_gain_t gain, tsl2561_integration_t integ);
bool    tsl2561_read_raw(uint8_t i2c_addr, uint16_t* ch0, uint16_t* ch1);
float   tsl2561_calculate_lux(uint16_t ch0, uint16_t ch1, tsl2561_gain_t gain, tsl2561_integration_t integ);

#endif
