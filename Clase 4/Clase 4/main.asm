;***********************************************************  
; Universidad del Valle de Guatemala  
; IE2023: Programación de Microcontroladores  
; ContadorBinario.asm  
;  
; Created: 11/02/25  
; Author : Mario Fernando Cano Itzep  
; Descripción: Contador Binario Dual con anti-rebote y suma de 4 bits  
;***********************************************************  
;Tmr -> 10mx -> incrementar un contador
.INCLUDE "M328PDEF.INC" ; Incluir definiciones específicas del ATmega328P  

.CSEG  
.ORG 0x0000             ; La memoria del programa empieza desde la dirección 0x0000  
		JMP START		; SALTA A DOND ENCUENTRES LA ETIQUETA DE "START"
.ORG	0VF0addr		; DIRECCIÓN DEL "RESET VECTOR" ES 0X000. CÓDIGO INICIA 
	JMP TMR0_ISR		;ESTABLECER LA DIRECCIOÓN DONDE SE ENCUENTRA LA RUTINA DE INTERRUPCIÓN
; ----------------------------------------------------------  
; Configuración de la pila para subrutinas y manejo correcto  
START:
LDI     R16, LOW(RAMEND) ; Cargar el valor bajo de la dirección final de la RAM  
OUT     SPL, R16         ; Configurar el puntero de pila bajo (SP)  
LDI     R16, HIGH(RAMEND) ; Cargar el valor alto de la dirección final de la RAM  
OUT     SPH, R16         ; Configurar el puntero de pila alto (SP)  

SETUP:
CLI

	LDI		R16, (1<< CLKPCE)
	STS		CLKR, R16
	LDI		RD16, 0b00000100
	STS		CLKPR, R16

	LDI		R16, (1<< CS01) | (1<<CS00)
	OUT		TCCR0B, R16
	LDI		R16, 100
	OUT		TCNT0, R16

	LDI		R16, (1<< TOIE0)
	STS		TIMSK0, R16

	SBI		DDRB, PB5
	SBI		DDRB, PB0
	CBI		PORTB, PB5
	CBI		PORTB, PB0

	LDI		R20, 0
	SEI

MAIN_LOOP:
	CPI		R20, 50
	BRNE	MAIN_LOOP
	CLR		R20
	SBI		PINB, PB5
	SBI		PINB, PB0
	RJMP	MAIN_LOOP

TMR0_ISR:
	LDI		R16, 100
	OUT		TCNT0, R16
	INC		R20

	RETI 