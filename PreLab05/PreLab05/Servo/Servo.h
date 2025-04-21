#ifndef SERVO_H
#define SERVO_H

#define F_CPU 16000000
#include <avr/io.h>
#include <avr/interrupt.h>
#include <util/delay.h>

// ---- DEFINICIONES ----

// Canales ADC
#define ADC_SERVO1_CHANNEL 6  // A6: Controla Servo 1 en D9
#define ADC_SERVO2_CHANNEL 7  // A7: Controla Servo 2 en D10
#define ADC_LED_CHANNEL    5  // A5: Controla el brillo del LED

// Pines
#define LED_PIN     PD6       // LED en D6 (OC0A)
#define SERVO1_PIN  PB1       // Servo 1 en D9
#define SERVO2_PIN  PB2       // Servo 2 en D10

// Rango de valores PWM para servos
#define SERVO_MIN 125    // 0°
#define SERVO_MAX 625    // 180°

// Factor de suavizado ADC
#define ADC_SMOOTH_FACTOR 3

// ---- PROTOTIPOS DE FUNCIONES ----

// Configuración general
void controller_init(void);

// Funciones de LED
void led_init(void);
void set_led_brightness(uint8_t brightness);

// Funciones de servo
void servo_init(void);
void set_servo1_position(uint16_t position);
void set_servo2_position(uint16_t position);
uint16_t adc_to_servo(uint16_t adc_val);

// Funciones ADC
void adc_init(void);
uint16_t adc_read(uint8_t channel);
uint16_t adc_filter(uint8_t canal, uint16_t nuevo_valor);

#endif /* SERVO_H */