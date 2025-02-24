;
; Timer1.asm
;
; Created: 21/02/2025 17:27:31
; Author : Mario
;


; Replace with your application code
start:
	LDI     R16, LOW(RAMEND)    ; Cargar el valor más bajo de RAM a R16  
    OUT     SPL, R16            ; Establecer SPL  
    LDI     R16, HIGH(RAMEND)   ; Cargar el valor más alto de RAM a R16  
    OUT     SPH, R16            ; Establecer SPH  

SETUP:
	CLI		

	LDI		R16, 