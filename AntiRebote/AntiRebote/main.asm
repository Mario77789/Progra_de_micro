;
; AntiRebote.asm
;
; Created: 31/01/2025 18:18:38
; Author : Mario
;

//Encabezado
.INCLUDE "M328PDEF.inc"
.cseg
.org	0x0000

//Configuración de pila // 0X08FF
LDI		R16, LOW(RAMEND) // CARGAR 0XFF A R16
OUT		SPL, R16		//CARGAR 0XFF A SPL
LDI		R16, HIGH(RAMEND)
OUT		SPH, R16		//CARGAR 0X08 A SPH

// Configuración de MCU

SETPU:
	// DDRX, PORTx, PINx
	// CONFIGURAR PUERTO D COMO ENTRADA CON PULL-UPS HABILITADOS
	LDI		R16, 0x00
	OUT		DDRD, R16		//seteamos todo el puerto d como entrada
	LDI		R16, 0xFF
	OUT		PORTD, R16		//HABILITAMOS PULL-UPS EN TODO EL PUERTO D
	

	//CONFIGURAR PUERTO B COMO SALIDA Y CON PB0 COMO SALIDA
	LDI		R16, 0xFF
	OUT		DDRB, R16		//seteamos todo el puerto B como SALIDA
	LDI		R16, 0b00000001
	OUT		PORTB, R16		//SETEAR 1 EL PB0


	//GUARDAR ESTADO ACTUAL DE LOS BOTONES EN R17
	LDI		R17, 0xFF		// 0b11111111


	//SBI	DDRD, 2

//LOOP PRINCIPAL

LOOP:
	IN		R16, PIND		//LEER EL PUERTO 
	CP		R17, R16		//COMPARAR ESTADO VIEJO CON ACTUAL
	BREQ	LOOP
	CALL	DELAY	//AGREGAR UN DELAY //RECOMENDACION VOLVER A LEER
	IN		R16, PIND		//LEER EL PUERTO 
	CP		R17, R16		//COMPARAR ESTADO VIEJO CON ACTUAL
	BREQ	LOOP
	MOV		R17, R16		//GUARDO ESTADO ACTUAL EN R17
	SBRC	R16, 2		//REVISANDO SI EL BIT ESTÁ APACHADO = 0 LÓGICO
	RJMP	LOOP
	SBI		PINB, 0		//TOGGLE DE PB0
	RJMP	LOOP

// Subrutinas (no de interrupcción)
DELAY:
	LDI		R18, 0
SUBDELAY1:
	INC		R18
	CPI		R18, 0
	BRNE	SUBDELAY1
	RET 


// Subrutinas (de interrupcción)
