/*  
 * Lab5.c  
 *  
 * Created: 07/04/2025  
 * Author: Mario  
 * Description: Control de servos y LED mediante potenciómetros  
 */  

#include "Servo/Servo.h"  

int main(void) {  
    // Inicializar todo el sistema  
    controller_init();  
    
    // Variables para almacenar valores filtrados  
    static uint16_t ultimo_servo1 = 0;  
    static uint16_t ultimo_servo2 = 0;  
    static uint16_t ultimo_led = 0;  
    
    // Posición inicial del LED (para diagnóstico)  
    set_led_brightness(5); // LED al 50% para verificar que PWM funciona  
    _delay_ms(50);         // Esperar medio segundo  
    set_led_brightness(0);  // Apagar LED  
    
    // Para limitar la frecuencia de lectura sin usar delays  
    uint16_t contador = 0;  
    
    while (1) {  
        // Ejecutar cada N iteraciones para evitar lecturas demasiado frecuentes  
        contador++;  
        if (contador >= 500) { // Reducido para mayor frecuencia de actualización  
            contador = 0;  
            
            // Leer y controlar LED (A5 -> D6)  
            uint16_t adc5_val = adc_read(ADC_LED_CHANNEL);  
            ultimo_led = adc_filter(ADC_LED_CHANNEL, adc5_val);  
            
            // Conversión directa a 8 bits  
            uint8_t brillo = ultimo_led >> 2; // De 0-1023 a 0-255  
            set_led_brightness(brillo);  
            
            // Leer y controlar Servo 1 (A6 -> D9)  
            uint16_t adc6_val = adc_read(ADC_SERVO1_CHANNEL);  
            ultimo_servo1 = adc_filter(ADC_SERVO1_CHANNEL, adc6_val);  
            set_servo1_position(adc_to_servo(ultimo_servo1));  
            
            // Leer y controlar Servo 2 (A7 -> D10)  
            uint16_t adc7_val = adc_read(ADC_SERVO2_CHANNEL);  
            ultimo_servo2 = adc_filter(ADC_SERVO2_CHANNEL, adc7_val);  
            set_servo2_position(adc_to_servo(ultimo_servo2));  
        }  
    }  
    
    return 0;  
}  