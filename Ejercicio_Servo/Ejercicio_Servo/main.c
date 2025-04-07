/*  
 * ContadorBinario.c  
 *  
 * Created: 04/04/2025  
 * Author: Mario  
 * Description: PWM
 */  
//  
// Encabezado (Libraries)  
#define F_CPU 16000000
#include <avr/io.h>  
#include <avr/interrupt.h>  
#include <util/delay.h>
uint8_t duty = 63;
//  
// Function prototypes  
void setup();  

#define inverted 1
#define not_inverted 0
void initPDWM0A(uint8_t invertido, uint16_t prescaler);
void initPDWM0B(uint8_t invertido, uint16_t prescaler);
void updateDutyClycleA(uint8_t dutyCycle); 
// Main Function  
int main(void)  
{  
    setup();  
    
    while (1)  
    {  
      updateDutyClycleA(duty);
	  duty++;
	  _delay_ms(1);
    }  
}  

//  
// NON-Interrupt subroutines  
void setup()  
{  
    cli(); 
    
	CLKPR		= (1<< CLKPCE);
	CLKPR		= (1<< CLKPS2);
	
	initPDWM0A(not_inverted, 64);
    
    sei(); 
}  

void initPDWM0A(uint8_t invertido, uint16_t prescaler)
{
	DDRD |= (1<<DDD6);
	
	TCCR0A &= ~((1<< COM0A1) | (1<<COM0A0));
	
	if (invertido == inverted)
	{
		TCCR0A |= (1<< COM0A1) | (1<<COM0A0);
	}
	else{
		TCCR0A |= (1<< COM0A1);
	}
	

	TCCR0A |= (1<< WGM01) | (1<<WGM00); //FAST PWM CON TOP = 0xFF
	
	TCCR0B = 0;
	
	switch(prescaler)
	{
		case 1:
			TCCR0B |= (1<< CS00);
			break;
		case 8:
			TCCR0B |= (1<< CS01);
			break;
		case 64:
			TCCR0B |= (1<< CS01) | (1<< CS00);
			break;
		case 256:
			TCCR0B |= (1<< CS02);
			break;
		case 1024:
			TCCR0B |= (1<< CS02) | (1<< CS00);
			break;
		default:
			TCCR0B |= (1<< CS00);
	}
	
	
	
	
}

void initPDWM0B(uint8_t invertido, uint16_t prescaler)
{
	DDRD |= (1<<DDD5);
	
	TCCR0B &= ~((1<< COM0B1) | (1<<COM0B0));
	
	if (invertido == inverted)
	{
		TCCR0B |= (1<< COM0B1) | (1<<COM0B0);
	}
	else{
		TCCR0A |= (1<< COM0B1);
	}
	
	TCCR0A |= (1<< WGM01) | (1<<WGM00); //FAST PWM CON TOP = 0xFF
	
	TCCR0B = 0;
	
	switch(prescaler)
	{
		case 1:
			TCCR0B |= (1<< CS00);
			break;
		case 8:
			TCCR0B |= (1<< CS01);
			break;
		case 64:
			TCCR0B |= (1<< CS01) | (1<< CS00);
			break;
		case 256:
			TCCR0B |= (1<< CS02);
			break;
		case 1024:
			TCCR0B |= (1<< CS02) | (1<< CS00);
			break;
		default:
		TCCR0B |= (1<< CS00);
	}
}	

void updateDutyClycleA(uint8_t dutyCycle)
{
	OCR0A = dutyCycle;
}

//  
// Interrupt routines  


