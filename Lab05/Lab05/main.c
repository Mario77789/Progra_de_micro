/*  
 * Lab5.c  
 *  
 * Created: 08/04/2025  
 * Author: Mario   
 * Description: PWM con dos servos 
 */  
//  
// Encabezado (Libraries)  
#define F_CPU 16000000  
#include <avr/io.h>  
#include <avr/interrupt.h>  
#include <util/delay.h>  

// Rango de valores PWM para servos   
#define SERVO_MIN 125    // 0°  
#define SERVO_MAX 625    //180°  
#define SERVO_MID ((SERVO_MIN + SERVO_MAX)/2)  

// Modos de operación  
#define MODE_NORMAL 0      // Control directo por potenciómetros  
#define MODE_MIRROR 1      // Servo 2 refleja movimiento del Servo 1  
#define MODE_SEQUENCE 2    // Secuencia automática de movimientos  
#define MODE_OPPOSITE 3    // Servos se mueven en dirección opuesta  

uint8_t current_mode = MODE_NORMAL;  
uint16_t servo1_pos = SERVO_MID;  
uint16_t servo2_pos = SERVO_MID;  
uint8_t led_intensity = 0;  
uint8_t sequence_step = 0;  
volatile uint16_t counter = 0;  // Contador para implementar delays variables  

//  
// Function prototypes  
void setup();  
void init_PWMSERV();  
void init_ADC();  
void init_timer2();  
uint16_t L_ADC(uint8_t channel);  
uint16_t conversionServo(uint16_t adc_val);  
void PWM_LED();  
void update_servos_mode();  
void run_sequence();  
void custom_delay(uint16_t ms);  

// Main Function  
int main(void)  
{  
    setup();  
    
    while (1)  
    {  
        // Leer ADC7 para controlar velocidad y LED  
        uint16_t adc7_val = L_ADC(7);  
        led_intensity = adc7_val >> 2; // Convertir 10-bit a 8-bit (1023/4=255)  
        OCR0A = led_intensity;  
        
        // Calcular velocidad basada en ADC7 (menor valor = más rápido)  
        uint16_t delay_ms = 10 + ((1023 - adc7_val) * 90) / 1023;  
        
        // Leer ADC4 para seleccionar modo (dividido en 4 rangos)  
        uint16_t adc4_val = L_ADC(4);  
        if (adc4_val < 256) {  
            current_mode = MODE_NORMAL;  
        } else if (adc4_val < 512) {  
            current_mode = MODE_MIRROR;  
        } else if (adc4_val < 768) {  
            current_mode = MODE_SEQUENCE;  
        } else {  
            current_mode = MODE_OPPOSITE;  
        }  
        
        // Leer ADC5 para posición principal  
        uint16_t adc5_val = L_ADC(5);  
        
        // Actualizar posiciones de servos según el modo actual  
        update_servos_mode(adc5_val);  
        
        // Actualizar registros de PWM con las posiciones calculadas  
        OCR1A = servo1_pos;  
        OCR1B = servo2_pos;  
        
        // Usar un retraso fijo en lugar de variable  
        _delay_ms(20);  // Retraso fijo de 20ms  
    }  
}  

void update_servos_mode(uint16_t adc5_val) {  
    switch(current_mode) {  
        case MODE_NORMAL:  
            // Modo normal: ADC5 controla Servo 1  
            servo1_pos = conversionServo(adc5_val);  
            // ADC4 controla indirectamente Servo 2 a través del modo  
            break;  
            
        case MODE_MIRROR:  
            // Modo espejo: Servo 2 imita exactamente a Servo 1  
            servo1_pos = conversionServo(adc5_val);  
            servo2_pos = servo1_pos;  
            break;  
            
        case MODE_SEQUENCE:  
            // Modo secuencia: Ejecutar una secuencia automática  
            run_sequence();  
            break;  
            
        case MODE_OPPOSITE:  
            // Modo opuesto: Servo 2 se mueve en dirección opuesta a Servo 1  
            servo1_pos = conversionServo(adc5_val);  
            servo2_pos = SERVO_MAX - (servo1_pos - SERVO_MIN);  
            break;  
    }  
}  

void run_sequence() {  
    // Ejecutar secuencia predefinida de movimientos  
    sequence_step = (sequence_step + 1) % 20;  
    
    if (sequence_step < 5) {  
        // Posición 1: Ambos en mínimo  
        servo1_pos = SERVO_MIN;  
        servo2_pos = SERVO_MIN;  
    } else if (sequence_step < 10) {  
        // Posición 2: Servo 1 máximo, Servo 2 mínimo  
        servo1_pos = SERVO_MAX;  
        servo2_pos = SERVO_MIN;  
    } else if (sequence_step < 15) {  
        // Posición 3: Servo 1 mínimo, Servo 2 máximo  
        servo1_pos = SERVO_MIN;  
        servo2_pos = SERVO_MAX;  
    } else {  
        // Posición 4: Ambos en máximo  
        servo1_pos = SERVO_MAX;  
        servo2_pos = SERVO_MAX;  
    }  
}  

//  
// NON-Interrupt subroutines  
void setup()  
{  
    cli();   
  
    PWM_LED();  
    init_PWMSERV();  
    init_ADC();  
      
    // Configurar pines de servo como salidas  
    DDRB |= (1 << PB1) | (1 << PB2);  

    sei();   
}  

void PWM_LED() {  
    DDRD |= (1 << PD6); // Configura PD6 como salida  
      
    // Modo Fast PWM, TOP = 0xFF, PWM no-invertido en OC0A  
    TCCR0A = (1 << COM0A1) | (1 << WGM01) | (1 << WGM00);  
      
    // Prescaler 64   
    TCCR0B = (1 << CS01) | (1 << CS00);  
      
    OCR0A = 0; // Inicia con LED apagado  
}  

void init_PWMSERV() {  
    TCCR1A = (1 << COM1A1) | (1 << COM1B1) | (1 << WGM11);  
    TCCR1B = (1 << WGM13) | (1 << WGM12) | (1 << CS11) | (1 << CS10); // Prescaler 64  
      
    ICR1 = 4999; // Período de 20ms   
      
    // Posición inicial centrada  
    OCR1A = SERVO_MID; // Servo 1  
    OCR1B = SERVO_MID; // Servo 2  
}  
      
void init_ADC() {  
    ADCSRA = (1 << ADEN) | (1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0); // Prescaler 128  
    ADMUX = (1 << REFS0); // Referencia AVcc  
      
    // Deshabilitar entradas digitales para ADC4, ADC5 y ADC7  
    DIDR0 = (1 << 4) | (1 << 5) | (1 << 7);  
}  

uint16_t L_ADC(uint8_t channel) {  
    ADMUX = (1 << REFS0) | (channel & 0x07);  
    ADCSRA |= (1 << ADSC);  
    while (ADCSRA & (1 << ADSC));  
    return ADC;  
}  

uint16_t conversionServo(uint16_t adc_val) {  
    // Convertir valor ADC (0-1023) a posición de servo (SERVO_MIN a SERVO_MAX)  
    return SERVO_MIN + ((uint32_t)adc_val * (SERVO_MAX - SERVO_MIN)) / 1023;  
}  