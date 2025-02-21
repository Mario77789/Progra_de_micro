;***********************************************************  
; Universidad del Valle de Guatemala  
; IE2023: Programación de Microcontroladores  
; Autor: Mario Fernando Cano Itzep
; PreLab03: Contador binario con botones y LEDs  
;***********************************************************  

.include "m328Pdef.inc"  

.org 0x0000                  ; Dirección de reset  
    rjmp START                ; Salto a la rutina de inicio  

.org PCI1addr                ; Dirección de interrupción PCINT1 (Puerto C)  
    rjmp ISR_BUTTON           ; Salto a la rutina de interrupción  

START:  
    ; Inicializar pila  
    LDI R16, LOW(RAMEND)      
    OUT SPL, R16  
    LDI R16, HIGH(RAMEND)     
    OUT SPH, R16  

    ; Configuración del MCU  
    CLI                       ; Deshabilitar interrupciones globales  

    ; Configurar pull-ups en botones (PC0 y PC1 como entradas con pull-up)  
    LDI R16, (1 << PC0) | (1 << PC1)  
    OUT PORTC, R16            ; Habilitar pull-ups en PC0 y PC1  

    ; Configurar interrupciones de cambio en PC0 y PC1  
    LDI R16, (1 << PCIE1)     ; Habilitar PCINT1 (Puerto C)  
    STS PCICR, R16  
    
    LDI R16, (1 << PCINT8) | (1 << PCINT9) ; Habilitar PC0 y PC1  
    STS PCMSK1, R16  

    ; Configurar LEDs como salida (PB0-PB3)  
    LDI R16, 0x0F            
    OUT DDRB, R16             

    ; Inicializar contador  
    CLR R16                  ; Contador inicial en 0  
    OUT PORTB, R16           ; Apagar LEDs  

    SEI                       ; Habilitar interrupciones globales  

MAIN_LOOP:  
    RJMP MAIN_LOOP            ; Bucle principal  

ISR_BUTTON:  
    ; Guardar estado de SREG  
    IN R17, SREG             
    PUSH R17                 

    ; Leer estado actual de PINC  
    IN R17, PINC              

    ; Verificar botón de incremento (PC0 presionado = bajo)  
    SBRS R17, PC0            ; Salta si PC0 está alto (no presionado)  
    INC R16                  ; Incrementa si está bajo (presionado)  

    ; Verificar botón de decremento (PC1 presionado = bajo)  
    SBRS R17, PC1            ; Salta si PC1 está alto (no presionado)  
    DEC R16                  ; Decrementa si está bajo (presionado)  

    ; Aplicar máscara de 4 bits y actualizar LEDs  
    ANDI R16, 0x0F           
    OUT PORTB, R16           

    ; Restaurar SREG  
    POP R17                  
    OUT SREG, R17            

    RETI                     ; Retornar de interrupción  