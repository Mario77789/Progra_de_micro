/*  
 * ContadorBinario.c  
 *  
 * Created: 31/03/2025  
 * Author: Mario  
 * Description: Contador binario de 8 bits con antirebote por interrupciones  
 *              y medición de voltaje con potenciómetro  
 */  
//  
// Encabezado (Libraries)  
#include <avr/io.h>  
#include <avr/interrupt.h>  

// Variables globales  
uint8_t counter_value = 0;        // Valor del contador de 8 bits  
uint8_t counter_10ms = 0;         // Contador para temporizador  
uint8_t debounce_counter_pc4 = 0; // Contador antirebote para PC4  
uint8_t debounce_counter_pc5 = 0; // Contador antirebote para PC5  
uint8_t button_state_pc4 = 0;     // Estado actual del botón PC4  
uint8_t button_state_pc5 = 0;     // Estado actual del botón PC5  
uint8_t button_pressed_pc4 = 0;   // Flag para botón PC4 presionado  
uint8_t button_pressed_pc5 = 0;   // Flag para botón PC5 presionado  

// Variables para ADC y display  
uint8_t adc_value = 0;           // Valor leído del ADC (ADCH solamente)  
uint8_t display_digit[2];         // Dígitos para mostrar (0-F)  
uint8_t current_display = 0;      // Display actualmente activo (0 o 1)  

// Tabla de conversión para display de 7 segmentos (común cátodo)  
// Segmentos: DP G F E D C B A (0 = apagado, 1 = encendido)  
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
            counter_value++;    // Incrementar contador  
            update_leds();      // Actualizar LEDs  
            button_pressed_pc4 = 0; // Limpiar flag  
        }  
        
        if (button_pressed_pc5)  
        {  
            counter_value--;    // Decrementar contador  
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
    cli(); // Deshabilitar interrupciones globales  
    
    // Desactivar USART (TX/RX)  
    UCSR0B = 0x00;  // Deshabilita el transmisor y receptor USART  
    
    // Configurar puertos  
    DDRB = 0x3F;   // PB0-PB5 como salidas (0b00111111)  
    PORTB = 0x00;  // Inicialmente todos apagados  
    
    DDRC = 0x0F;   // PC0-PC3 como salidas, PC4-PC6 como entradas (0b00001111)  
    PORTC = 0x30;  // Pull-ups en PC4-PC5 (0x30), PC0-PC3 inicialmente apagados  
    
    DDRD = 0xFF;   // PD0-PD7 como salidas para los segmentos de los displays  
    PORTD = 0x00;  // Inicialmente todos apagados  
    
    // Configurar Timer0 para polling de botones cada 10ms  
    TCCR0A = 0x00;  // Modo normal  
    TCCR0B = (1 << CS02) | (1 << CS00); // Prescaler 1024  
    TCNT0 = 100;    // Valor inicial para ~10ms @16MHz  
    TIMSK0 = (1 << TOIE0); // Habilitar interrupción por overflow  
    
    // Configurar interrupciones para botones (PCINT)  
    PCICR = (1 << PCIE1);       // Habilitar PCINT para PORTC  
    PCMSK1 = (1 << PCINT12) | (1 << PCINT13); // Habilitar para PC4 y PC5  
    
    // Configurar ADC con ADLAR=1 para alinear el resultado a la izquierda  
    // De esta manera los 8 bits más significativos estarán en ADCH  
    ADMUX = (1 << REFS0) | (1 << ADLAR) | (1 << MUX2) | (1 << MUX1); // Referencia AVcc, alineación izquierda, seleccionar ADC6 (PC6)  
    ADCSRA = (1 << ADEN) | (1 << ADIE) | (1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0); // Habilitar ADC, habilitar interrupción ADC, prescaler 128  
    
    // Inicializar display  
    display_digit[0] = 0;  
    display_digit[1] = 0;  
    current_display = 0;  
    
    counter_10ms = 0;  
    update_leds(); // Inicializar LEDs con el valor actual  
    
    sei(); // Habilitar interrupciones globales  
    
    // Iniciar primera conversión ADC  
    start_adc_conversion();  
}  

// Actualiza el estado de los LEDs basado en el valor del contador   
// Mapeo:  
// PB2 = bit 5, PB3 = bit 6, PB4 = bit 7, PB5 = bit 4  
// PC0 = bit 3, PC1 = bit 2, PC2 = bit 1, PC3 = bit 0  
void update_leds()  
{  
    uint8_t portb_value = 0;  
    uint8_t portc_value = 0;  
    
    // Mapeo para puerto B  
    if (counter_value & (1 << 5)) portb_value |= (1 << 2); // Bit 5 -> PB2  
    if (counter_value & (1 << 6)) portb_value |= (1 << 3); // Bit 6 -> PB3  
    if (counter_value & (1 << 7)) portb_value |= (1 << 4); // Bit 7 -> PB4  
    if (counter_value & (1 << 4)) portb_value |= (1 << 5); // Bit 4 -> PB5  
    
    // Guardar estado de PB0 y PB1 (para los displays)  
    portb_value |= (PORTB & 0x03);  
    
    // Mapeo para puerto C  
    if (counter_value & (1 << 3)) portc_value |= (1 << 0); // Bit 3 -> PC0  
    if (counter_value & (1 << 2)) portc_value |= (1 << 1); // Bit 2 -> PC1  
    if (counter_value & (1 << 1)) portc_value |= (1 << 2); // Bit 1 -> PC2  
    if (counter_value & (1 << 0)) portc_value |= (1 << 3); // Bit 0 -> PC3  
    
    PORTB = portb_value;  
    
    // Asegurar que los pull-ups de PC4 y PC5 se mantienen activos  
    PORTC = portc_value | 0x30;  
}  

// Inicia una conversión ADC  
void start_adc_conversion() {  
    ADCSRA |= (1 << ADSC);  // Iniciar conversión ADC  
}  

// Actualiza los displays de 7 segmentos  
void update_display() {  
    // Apagar ambos displays  
    PORTB &= ~0x03;  // Limpiar PB0 y PB1  
    
    // Alternar entre los displays  
    current_display = !current_display;  
    
    // Mostrar el dígito actual sin punto decimal  
    PORTD = seven_seg[display_digit[current_display]];  
    
    // Activar el display actual  
    PORTB |= (1 << current_display);  
}  

// Convierte el valor del ADC a dígitos hexadecimales para el display  
void convert_adc_to_hex_digits() {  
    // Extraer dígitos hexadecimales de ADCH  
    display_digit[0] = (adc_value >> 4) & 0x0F;  // Dígito hexadecimal alto (bits 7-4)  
    display_digit[1] = adc_value & 0x0F;         // Dígito hexadecimal bajo (bits 3-0)  
}  

//  
// Interrupt routines  
ISR(TIMER0_OVF_vect)  
{  
    TCNT0 = 100; // Reiniciar el timer  
    
    // Manejar antirebote para PC4  
    if (debounce_counter_pc4 > 0)  
    {  
        debounce_counter_pc4--;  
        if (debounce_counter_pc4 == 0 && button_state_pc4 == 0)  
        {  
            // Botón estable y presionado  
            button_pressed_pc4 = 1;  
        }  
    }  
    
    // Manejar antirebote para PC5  
    if (debounce_counter_pc5 > 0)  
    {  
        debounce_counter_pc5--;  
        if (debounce_counter_pc5 == 0 && button_state_pc5 == 0)  
        {  
            // Botón estable y presionado  
            button_pressed_pc5 = 1;  
        }  
    }  
    
    counter_10ms++;  
    
    // Actualizar display (multiplexar)  
    update_display();  
}  

// Interrupción para cambios en PORTC (botones)  
ISR(PCINT1_vect)  
{  
    // Leer estado actual de los botones (invertido debido a pull-up)  
    uint8_t pc4_current = !(PINC & (1 << PINC4));  
    uint8_t pc5_current = !(PINC & (1 << PINC5));  
    
    // Si hay cambio en PC4 y no está en periodo de antirebote  
    if (pc4_current != button_state_pc4 && debounce_counter_pc4 == 0)  
    {  
        button_state_pc4 = pc4_current;  
        debounce_counter_pc4 = 5; // 50ms antirebote (5 * 10ms)  
    }  
    
    // Si hay cambio en PC5 y no está en periodo de antirebote  
    if (pc5_current != button_state_pc5 && debounce_counter_pc5 == 0)  
    {  
        button_state_pc5 = pc5_current;  
        debounce_counter_pc5 = 5; // 50ms antirebote (5 * 10ms)  
    }  
}  

// Interrupción para conversión ADC completada  
ISR(ADC_vect) {  
    // Leer solamente ADCH (registro alto del ADC)  
    adc_value = ADCH;  
    
    // Convertir valor ADC a dígitos hexadecimales para el display  
    convert_adc_to_hex_digits();  
}  