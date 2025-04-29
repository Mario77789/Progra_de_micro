/*  
 * Comunicación serial.c  
 *  
 * Created: 31/03/2025  
 * Author: Mario  
 * Description: Comunicador serial
 */  
//  
// Encabezado (Libraries)  
#include <avr/io.h>
#include <avr/interrupt.h>

//  Prototype
void setup();
void initUART();
void writeChar(char caracter);
// Main Function  
int main(void)  
{  
    setup();  
    writeChar("H");
	writeChar("O");
	writeChar("L");
	writeChar("A");
    while (1)  
    {
		  
	}
}  

//  
// NON-Interrupt subroutines  
void setup()  
{  
    cli(); 
    
	initUART();
    
    
    sei(); 
}  

void initUART()
{
	DDRD |= (1<<DDD1);
	DDRD &=	~(1<<DDD0);
	
	UCSR0A = 0;
	
	UCSR0B = (1<<RXCIE0)  | (1<<RXEN0) | (1<<TXEN0);
	
	UCSR0C = (1<< UCSZ01) | (1<<UCSZ00);
	 
	UBRR0 = 103;	
}

void writeChar(char caracter)
{
	while((UCSR0A & (1<< UDRE0)) == 0)
	{
		
	}
	
		UDR0 = caracter;

	
	
}
//  
// Interrupt routines  
void ISR(USART_RX_vect)
{
	uint8_t temporal = UDR0;
	writeChar(temporal);
	};