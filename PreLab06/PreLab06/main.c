/*  
 * PreLab06.c  
 *  
 * Created: 22/04/2025  
 * Author: Mario  
 * Description: Comunicador serial   
 */  

//  
// Encabezado (Libraries)  
#include <avr/io.h>  
#include <avr/interrupt.h>  

//  
// Function prototypes  
void setup(void);  
void usart_init(void);  
void usart_transmit(uint8_t data);  

//  
// Main Function  
int main(void)  
{  
    setup();  

    // ----------- PARTE 1 --------------  
    // Envío del carácter al iniciar  
    usart_transmit('A'); // Puedes cambiar el carácter a enviar  

    while (1)  
    {  
        // ----------- PARTE 2 -----------  
        // Si llegó un caracter, mostrarlo en PORTB y apagar la bandera  
        if (char_received_flag)  
        {  
            PORTB = received_char;  
            char_received_flag = 0;  
        }  
    }  
}  

//  
// NON-Interrupt subroutines  
volatile uint8_t received_char = 0;  
volatile uint8_t char_received_flag = 0;  

void setup(void)  
{  
    cli();            // Deshabilita las interrupciones globales  
    DDRB = 0xFF;      // Configura PORTB como salida  
    PORTB = 0x00;     // Inicializa PORTB en 0  
    usart_init();     // Inicializa UART  
    sei();            // Habilita las interrupciones globales  
}  

void usart_init(void)  
{  
    // PD1 como salida (TX), PD0 como entrada (RX)  
    DDRD |= (1 << DDD1);    // TX (salida)  
    DDRD &= ~(1 << DDD0);   // RX (entrada)  

    // 9600 baudios, F_CPU=16MHz -> UBRR0=103  
    UBRR0H = 0;  
    UBRR0L = 103;  

    // Habilitar TX, RX y RX Complete Interrupt  
    UCSR0B = (1 << RXEN0) | (1 << TXEN0) | (1 << RXCIE0);  

    // 8 bits, 1 bit stop, sin paridad  
    UCSR0C = (1 << UCSZ01) | (1 << UCSZ00);  
}  

void usart_transmit(uint8_t data)  
{  
    while (!(UCSR0A & (1 << UDRE0)))  
        ; // Espera a que el buffer esté listo  

    UDR0 = data; // Envía el carácter  
}  

//  
// Interrupt routines  
ISR(USART_RX_vect)  
{  
    received_char = UDR0;      // Guarda el carácter recibido  
    char_received_flag = 1;    // Activa la bandera  
}  