/*  
 * ContadorBinario.c  
 *  
 * Created: 31/03/2025  
 * Author: Mario  
 * Description: Contador binario de 8 bits 
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
uint8_t button_pressed_pc4 = 0;   // Flag para botón PC4 presionado  
uint8_t button_pressed_pc5 = 0;   // Flag para botón PC5 presionado  

//  
// Function prototypes  
void setup();  
void update_counter();  
void update_leds();  

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
            counter_value++;    // Incrementar contador  
            update_leds();      // Actualizar LEDs  
            button_pressed_pc4 = 0;
        }  
        
        if (button_pressed_pc5)  
        {  
            counter_value--;    // Decrementar contador  
            update_leds();      // Actualizar LEDs  
            button_pressed_pc5 = 0; 
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
    DDRB = 0x3C;     
    PORTB = 0x00;  
    
    DDRC = 0x0F;    
    PORTC = 0x30;  
    
    // Configurar Timer0  
    TCCR0A = 0x00;  
    TCCR0B = (1 << CS02) | (1 << CS00); //  
    TCNT0 = 100;   
    TIMSK0 = (1 << TOIE0); //
    
    // Configurar interrupciones para botones (PCINT)  
    PCICR = (1 << PCIE1);       
    PCMSK1 = (1 << PCINT12) | (1 << PCINT13); 
    
    counter_10ms = 0;  
    update_leds(); // Inicializar LEDs con el valor actual  
    
    sei(); // Habilitar interrupciones globales  
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
    
    // Mapeo para puerto C  
    if (counter_value & (1 << 3)) portc_value |= (1 << 0); 
    if (counter_value & (1 << 2)) portc_value |= (1 << 1); 
    if (counter_value & (1 << 1)) portc_value |= (1 << 2); 
    if (counter_value & (1 << 0)) portc_value |= (1 << 3);  
    
    PORTB = portb_value;  
    
    
    PORTC = portc_value | 0x30;  
}  

//  
// Interrupt routines  
ISR(TIMER0_OVF_vect)  
{  
    TCNT0 = 100; // Reiniciar el timer  
    
    // Manejar antirebote para PC4  
    if (antirrebote_counter_pc4 > 0)  
    {  
        antirrebote_counter_pc4--;  
        if (antirrebote_counter_pc4 == 0 && button_state_pc4 == 0)  
        {  
            // Botón estable y presionado  
            button_pressed_pc4 = 1;  
        }  
    }  
    
    // Manejar antirebote para PC5  
    if (antirrebote_counter_pc5 > 0)  
    {  
        antirrebote_counter_pc5--;  
        if (antirrebote_counter_pc5 == 0 && button_state_pc5 == 0)  
        {  
            // Botón estable y presionado  
            button_pressed_pc5 = 1;  
        }  
    }  
}  

// Interrupción para cambios en PORTC (botones)  
ISR(PCINT1_vect)  
{  
    // Leer estado actual de los botones   
    uint8_t pc4_current = !(PINC & (1 << PINC4));  
    uint8_t pc5_current = !(PINC & (1 << PINC5));  
    
    // Si hay cambio en PC4 y no está en periodo de antirebote  
    if (pc4_current != button_state_pc4 && antirrebote_counter_pc4 == 0)  
    {  
        button_state_pc4 = pc4_current;  
        antirrebote_counter_pc4 = 5; // 50ms antirebote (5 * 10ms)  
    }  
    
    // Si hay cambio en PC5 y no está en periodo de antirebote  
    if (pc5_current != button_state_pc5 && antirrebote_counter_pc5 == 0)  
    {  
        button_state_pc5 = pc5_current;  
        antirrebote_counter_pc5 = 5; // 50ms antirebote (5 * 10ms)  
    }  
}  