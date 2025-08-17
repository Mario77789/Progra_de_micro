/*
 * TSL2561.c
 *
 * Created: 10/08/2025 19:04:31
 *  Author: mario
 */ 


#include "TSL2561.h"
#include "../I2C/I2C.h"
#include <util/delay.h>
#include <math.h>   

// Helpers locales
static bool tsl2561_write8(uint8_t addr, uint8_t reg, uint8_t val)
{
    uint8_t st = I2C_Start((addr << 1) | TW_WRITE);
    if (st != TW_MT_SLA_ACK) { I2C_Stop(); return false; }

    st = I2C_Write(TSL2561_CMD | reg);
    if (st != TW_MT_DATA_ACK) { I2C_Stop(); return false; }

    st = I2C_Write(val);
    if (st != TW_MT_DATA_ACK) { I2C_Stop(); return false; }

    I2C_Stop();
    return true;
}

static bool tsl2561_read8(uint8_t addr, uint8_t reg, uint8_t* val)
{
    uint8_t st = I2C_Start((addr << 1) | TW_WRITE);
    if (st != TW_MT_SLA_ACK) { I2C_Stop(); return false; }

    st = I2C_Write(TSL2561_CMD | reg);
    if (st != TW_MT_DATA_ACK) { I2C_Stop(); return false; }

    st = I2C_Start((addr << 1) | TW_READ);
    if (st != TW_MR_SLA_ACK) { I2C_Stop(); return false; }

    *val = I2C_ReadNACK();
    I2C_Stop();
    return true;
}

static bool tsl2561_read16(uint8_t addr, uint8_t regL, uint16_t* val)
{
    // Leemos dos registros consecutivos: L y H
    uint8_t st = I2C_Start((addr << 1) | TW_WRITE);
    if (st != TW_MT_SLA_ACK) { I2C_Stop(); return false; }

    st = I2C_Write(TSL2561_CMD | regL);
    if (st != TW_MT_DATA_ACK) { I2C_Stop(); return false; }

    st = I2C_Start((addr << 1) | TW_READ);
    if (st != TW_MR_SLA_ACK) { I2C_Stop(); return false; }

    uint8_t lo = I2C_ReadACK();
    uint8_t hi = I2C_ReadNACK();
    I2C_Stop();

    *val = (uint16_t)((hi << 8) | lo);
    return true;
}

bool tsl2561_init(uint8_t i2c_addr, tsl2561_gain_t gain, tsl2561_integration_t integ)
{
    // Power ON
    if (!tsl2561_write8(i2c_addr, TSL2561_REG_CONTROL, TSL2561_POWER_ON))
        return false;

    _delay_ms(5);

    // Set timing: integración + ganancia
    uint8_t timing = (uint8_t)integ | (uint8_t)gain;  // gain va en bit 4
    if (!tsl2561_write8(i2c_addr, TSL2561_REG_TIMING, timing))
        return false;

    // Pequeña espera para que el primer muestreo complete según integración
    switch (integ) {
        case TSL2561_INTEG_13MS:  _delay_ms(14); break;
        case TSL2561_INTEG_101MS: _delay_ms(110); break;
        default:
        case TSL2561_INTEG_402MS: _delay_ms(410); break;
    }

    return true;
}

bool tsl2561_read_raw(uint8_t i2c_addr, uint16_t* ch0, uint16_t* ch1)
{
    if (!tsl2561_read16(i2c_addr, TSL2561_REG_DATA0L, ch0)) return false;
    if (!tsl2561_read16(i2c_addr, TSL2561_REG_DATA1L, ch1)) return false;
    return true;
}

// Cálculo de lux basado en la hoja de datos de TSL2561 (coeficientes estándar para 402 ms)
float tsl2561_calculate_lux(uint16_t ch0, uint16_t ch1, tsl2561_gain_t gain, tsl2561_integration_t integ)
{
    if (ch0 == 0) return 0.0f;       // evita división por cero
    if (ch0 == 0xFFFF || ch1 == 0xFFFF) {
        // saturación; devolver 0 o un valor sentinel; aquí devolvemos 0
        return 0.0f;
    }

    // Ajuste por ganancia (si 16x ? escalar hacia 1x)
    float ch0f = (float)ch0;
    float ch1f = (float)ch1;
    if (gain == TSL2561_GAIN_16X) {
        ch0f /= 16.0f;
        ch1f /= 16.0f;
    }

    // Ajuste por tiempo de integración (referencia 402 ms)
    switch (integ) {
        case TSL2561_INTEG_13MS:
            ch0f *= (402.0f / 13.7f);
            ch1f *= (402.0f / 13.7f);
            break;
        case TSL2561_INTEG_101MS:
            ch0f *= (402.0f / 101.0f);
            ch1f *= (402.0f / 101.0f);
            break;
        default:
        case TSL2561_INTEG_402MS:
            // ya está en 402 ms
            break;
    }

    float ratio = ch1f / ch0f;
    float lux;

    // Fórmulas piecewise de la app note (402 ms, gain 1x)
    if (ratio <= 0.5f) {
        lux = (0.0304f * ch0f) - (0.062f * ch0f * powf(ratio, 1.4f));
    } else if (ratio <= 0.61f) {
        lux = (0.0224f * ch0f) - (0.031f * ch1f);
    } else if (ratio <= 0.80f) {
        lux = (0.0128f * ch0f) - (0.0153f * ch1f);
    } else if (ratio <= 1.30f) {
        lux = (0.00146f * ch0f) - (0.00112f * ch1f);
    } else {
        lux = 0.0f;
    }

    if (lux < 0.0f) lux = 0.0f;
    return lux;
}
