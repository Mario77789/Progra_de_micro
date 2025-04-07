/*  
 * ContadorBinario.c  
 *  
 * Created: 31/03/2025  
 * Author: Mario  
 * Description: Contador binario de 8 bits 
 *            
 */  
//  
// Encabezado (Libraries)  
#include <avr/io.h>  
#include <avr/interrupt.h>  

// Variables globales  
uint8_t counter_value = 0;        // Valor del contador de 8 bits  
uint8_t counter_10ms = 0;         // Contador para temporizador  
uint8_t antirrebote_counter_pc4 = 0; // Contador antirebote para PC4  
uint8_t antirrebote_counter_pc5 = 0; // Contador antirebote para PC5  
uint8_t button_state_pc4 = 0;     // Estado actual del botón PC4  
uint8_t button_state_pc5 = 0;     // Estado actual del botón PC5  
uint8_t button_pressed_pc4 = 0;   
uint8_t button_pressed_pc5 = 0;   

// Variables para ADC y display  
uint8_t adc_value = 0;           // Valor leído del ADC 
uint8_t display_digit[2];         // Dígitos para mostrar (0-F)  
uint8_t current_display = 0;      // Display actualmente activo (0 o 1)  

// Tabla de conversión para display de 7 segmentos 
const uint8_t seven_seg[] = {  
    0x3F,  // 0  
    0x06,  // 1  
    0x5B,  // 2  
    0x4F,  // 3  
    0x66,  // 4  
    0x6D,  // 5  
    0x7D,  // 6  
    0x07,  // 7  
    0x7F,  // 8  
    0x6F,  // 9  
    0x77,  // A  
    0x7C,  // b  
    0x39,  // C  
    0x5E,  // d  
    0x79,  // E  
    0x71   // F  
};  

//  
// Function prototypes  
void setup();  
void update_counter();  
void update_leds();  
void start_adc_conversion();  
void update_display();  

//  
// Main Function  
int main(void)  
{  
    setup();  
    
    while (1)  
    {  
        // Verificar si algún botón fue presionado  
        if (button_pressed_pc4)  
        {  
            counter_value++;     
            update_leds();      // Actualizar LEDs  
            button_pressed_pc4 = 0; // Limpiar flag  
        }  
        
        if (button_pressed_pc5)  
        {  
            counter_value--;      
            update_leds();      // Actualizar LEDs  
            button_pressed_pc5 = 0; // Limpiar flag  
        }  
        
        // Iniciar nueva conversión ADC cada ~500ms  
        if (counter_10ms % 50 == 0) {  
            start_adc_conversion();  
        }  
    }  
}  

//  
// NON-Interrupt subroutines  
void setup()  
{  
    cli();  
    
    // Desactivar USART (TX/RX)  
    UCSR0B = 0x00;  
    
    // Configurar puertos  
    DDRB = 0x3F;   // PB como salidas
    PORTB = 0x00;    
    
    DDRC = 0x0F;   // PC0-PC3 como salidas, PC4-PC6 como entradas 
    PORTC = 0x30;  
    
    DDRD = 0xFF;   // PD0-PD7 como salidas para los segmentos de los displays  
    PORTD = 0x00;  
    
    // Configurar Timer0 
    TCCR0A = 0x00;  // Modo normal  
    TCCR0B = (1 << CS02) | (1 << CS00); // Prescaler 1024  
    TCNT0 = 100;    // Valor inicial para ~10ms 
    TIMSK0 = (1 << TOIE0);  
    
    // Configurar interrupciones para botones (PCINT)  
    PCICR = (1 << PCIE1);       // Habilitar PCINT para PORTC  
    PCMSK1 = (1 << PCINT12) | (1 << PCINT13); // Habilitar para PC4 y PC5  
    
   
    ADMUX = (1 << REFS0) | (1 << ADLAR) | (1 << MUX2) | (1 << MUX1); // Referencia AVCC, alineación izquierda, seleccionar ADC6 
    ADCSRA = (1 << ADEN) | (1 << ADIE) | (1 << ADPS2) | (1 << ADPS1); // Habilitar ADC, habilitar interrupción ADC, prescaler 64 
    
    // Inicializar display  
    display_digit[0] = 0;  
    display_digit[1] = 0;  
    current_display = 0;  
    
    counter_10ms = 0;  
    update_leds(); // Inicializar LEDs con el valor actual  
    
    sei(); 
    
	
     
    start_adc_conversion();  
}  

void update_leds()  
{  
    uint8_t portb_value = 0;  
    uint8_t portc_value = 0;  
    
    // Mapeo para puerto B  
    if (counter_value & (1 << 5)) portb_value |= (1 << 2);
    if (counter_value & (1 << 6)) portb_value |= (1 << 3);  
    if (counter_value & (1 << 7)) portb_value |= (1 << 4);   
    if (counter_value & (1 << 4)) portb_value |= (1 << 5);   
    
    // Guardar estado de PB0 y PB1 (para los transitores del display displays)  
    portb_value |= (PORTB & 0x03);  
    
    // Mapeo para puerto C  
    if (counter_value & (1 << 3)) portc_value |= (1 << 0);  
    if (counter_value & (1 << 2)) portc_value |= (1 << 1);  
    if (counter_value & (1 << 1)) portc_value |= (1 << 2);  
    if (counter_value & (1 << 0)) portc_value |= (1 << 3);   
    
    PORTB = portb_value;  
    
    // Asegura que los pull-ups de PC4 y PC5 se mantienen activos  
    PORTC = portc_value | 0x30;  
}  

// Inicia una conversión ADC  
void start_adc_conversion() {  
    ADCSRA |= (1 << ADSC);  // Inicia ADC  
}  

// Actualiza los displays de 7 segmentos  
void update_display() {  
      
    PORTB &= ~0x03;  // Limpiar PB0 y PB1  
    
    // Alternar entre los displays  
    current_display = !current_display;  
    
     
    PORTD = seven_seg[display_digit[current_display]];  
	
	if (counter_value < adc_value)
	{
		PORTD |= (1 << PD7);
	}
    
    // Activar el display actual  
    PORTB |= (1 << current_display);  
}  

// Convertir valores decimales a hexadecimales en el ADC 
void convert_adc_to_hex_digits() {  
	
    // Extraer dígitos hexadecimales de ADCH  
    display_digit[0] = (adc_value >> 4) & 0x0F;  // Dígito hexadecimal alto   
    display_digit[1] = adc_value & 0x0F;         // Dígito hexadecimal bajo   
}  

//  
// Interrupt routines  
ISR(TIMER0_OVF_vect)  
{  
    TCNT0 = 100; // Reiniciar el timer  
    
    // Maneja antirebote para PC4  
    if (antirrebote_counter_pc4 > 0)  
    {  
        antirrebote_counter_pc4--;  
        if (antirrebote_counter_pc4 == 0 && button_state_pc4 == 0)  
        {  
            // Botón presionado  
            button_pressed_pc4 = 1;  
        }  
    }  
    
    // Maneja antirebote para PC5  
    if (antirrebote_counter_pc5 > 0)  
    {  
        antirrebote_counter_pc5--;  
        if (antirrebote_counter_pc5 == 0 && button_state_pc5 == 0)  
        {  
            // Botón presionado  
            button_pressed_pc5 = 1;  
        }  
    }  
    
    counter_10ms++;  
    
    
    update_display();  
}  

// Interrupción para cambios en botones 
ISR(PCINT1_vect)  
{  
    // Leer estado actual de los botones 
    uint8_t pc4_current = !(PINC & (1 << PINC4));  
    uint8_t pc5_current = !(PINC & (1 << PINC5));  
    
    // Si hay cambio en PC4 
    if (pc4_current != button_state_pc4 && antirrebote_counter_pc4 == 0)  
    {  
        button_state_pc4 = pc4_current;  
        antirrebote_counter_pc4 = 5; // 50ms antirebote (5 * 10ms)  
    }  
    
    // Si hay cambio en PC5  
    if (pc5_current != button_state_pc5 && antirrebote_counter_pc5 == 0)  
    {  
        button_state_pc5 = pc5_current;  
        antirrebote_counter_pc5 = 5; // 50ms antirebote (5 * 10ms)  
    }  
}  

// Interrupción para conversión ADC completada  
ISR(ADC_vect) {  
    // Leer solamente ADCH 
    adc_value = ADCH;  
    
    // Convertir valor ADC a dígitos hexadecimales para el display  
    convert_adc_to_hex_digits();  
}  