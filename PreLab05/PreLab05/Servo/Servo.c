#include "Servo.h"

void controller_init(void) {
	cli();
	
	// Configurar reloj a 16MHz
	CLKPR = (1 << CLKPCE);
	CLKPR = 0;
	
	// Inicializar subsistemas
	led_init();
	servo_init();
	adc_init();
	
	sei();
}

// ---- CONTROL DEL LED ----

void led_init(void) {
	// Configurar pin como salida
	DDRD |= (1 << LED_PIN);
	
	// Confirmar que el pin está en bajo inicialmente
	PORTD &= ~(1 << LED_PIN);
	
	// Modo Fast PWM, TOP = 0xFF, PWM no-invertido en OC0A
	TCCR0A = (1 << COM0A1) | (0 << COM0A0) | (1 << WGM01) | (1 << WGM00);
	
	// Prescaler 64
	TCCR0B = (0 << WGM02) | (0 << CS02) | (1 << CS01) | (1 << CS00);
	
	// Asegurar que el registro OCR0A inicia en 0 (LED apagado)
	OCR0A = 0;
}

void set_led_brightness(uint8_t brightness) {
	OCR0A = brightness;
}

// ---- CONTROL DE SERVOS ----

void servo_init(void) {
	// Configurar pines como salidas
	DDRB |= (1 << SERVO1_PIN) | (1 << SERVO2_PIN);
	
	// Modo Fast PWM 14 (ICR1 como TOP)
	TCCR1A = (1 << COM1A1) | (1 << COM1B1) | (1 << WGM11);
	TCCR1B = (1 << WGM13) | (1 << WGM12) | (1 << CS11) | (1 << CS10); // Prescaler 64
	
	// Período de 20ms (50Hz)
	ICR1 = 4999; // 16MHz/64/50Hz - 1 = 4999
	
	// Posición inicial centrada
	OCR1A = (SERVO_MIN + SERVO_MAX)/2; // Servo 1
	OCR1B = (SERVO_MIN + SERVO_MAX)/2; // Servo 2
}

void set_servo1_position(uint16_t position) {
	if (position < SERVO_MIN) position = SERVO_MIN;
	if (position > SERVO_MAX) position = SERVO_MAX;
	OCR1A = position;
}

void set_servo2_position(uint16_t position) {
	if (position < SERVO_MIN) position = SERVO_MIN;
	if (position > SERVO_MAX) position = SERVO_MAX;
	OCR1B = position;
}

uint16_t adc_to_servo(uint16_t adc_val) {
	// Convertir valor ADC (0-1023) a rango de servo (SERVO_MIN-SERVO_MAX)
	return SERVO_MIN + ((uint32_t)adc_val * (SERVO_MAX - SERVO_MIN)) / 1023;
}

// ---- FUNCIONES ADC ----

void adc_init(void) {
	// Configuración del ADC
	ADCSRA = (1 << ADEN) | (1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0); // Prescaler 128
	ADMUX = (1 << REFS0); // Referencia AVcc
	
	// Deshabilitar entradas digitales para ADC5, ADC6 y ADC7
	DIDR0 = (1 << ADC_LED_CHANNEL) | (1 << ADC_SERVO1_CHANNEL) | (1 << ADC_SERVO2_CHANNEL);
}

uint16_t adc_read(uint8_t channel) {
	// Configurar canal
	ADMUX = (ADMUX & 0xF8) | (channel & 0x07);
	
	// Iniciar conversión
	ADCSRA |= (1 << ADSC);
	
	// Esperar fin de la conversión
	while (ADCSRA & (1 << ADSC));
	
	return ADC;
}

uint16_t adc_filter(uint8_t canal, uint16_t nuevo_valor) {
	// Array estático para guardar últimos valores por canal
	static uint16_t valores_previos[8] = {0};
	
	// Aplicar filtro (promedio ponderado)
	valores_previos[canal] = (valores_previos[canal] * ADC_SMOOTH_FACTOR + nuevo_valor) / (ADC_SMOOTH_FACTOR + 1);
	
	return valores_previos[canal];
}