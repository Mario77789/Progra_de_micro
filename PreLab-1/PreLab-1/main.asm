;************************************************************  
; Universidad del Valle de Guatemala  
; IE2023: Programación de Microcontroladores  
; ContadorBinario4.asm  
;  
; Author  : Mario Fernando Cano Itzep  
; Proyecto: PreLab1  
; Hardware: ATmega328P  
; Creado  : 03/02/2025  
;************************************************************  
.INCLUDE "M328PDEF.inc"  

.cseg  
.org 0x0000  

; Configuración de pila  
LDI     R16, LOW(RAMEND)  
OUT     SPL, R16  
LDI     R16, HIGH(RAMEND)  
OUT     SPH, R16  

; Configuración del MCU  
SETPU:  
    ; Configurar Puerto D como entrada con pull-ups  
    LDI     R16, 0x00  
    OUT     DDRD, R16  
    LDI     R16, 0xFF  
    OUT     PORTD, R16  

    ; Configurar Puerto B como salida  
    LDI     R16, 0xFF  
    OUT     DDRB, R16  
    LDI     R16, 0x00  
    OUT     PORTB, R16  

    LDI     R18, 0x00       ; Inicializar contador (R18) en 0  

    RJMP    MAIN  

; --- Bucle principal ---  
MAIN:  
    RCALL   LEER_BOTONES  
    OUT     PORTB, R18      ; Actualiza LEDs en cada iteración  
    RJMP    MAIN  

; --- Subrutina para leer botones con antirrebote ---  
LEER_BOTONES:  
    ; *Incrementar (PD2)*  
    SBIS    PIND, 2          ; *Salta si PD2 está en 1 (no presionado)  
    RCALL   PROC_INCREMENTAR ; Si está en 0 (presionado), procesar  

    ; *Decrementar (PD3)*  
    SBIS    PIND, 3          ; *Salta si PD3 está en 1 (no presionado)  
    RCALL   PROC_DECREMENTAR ; Si está en 0 (presionado), procesar  

    RET  

; --- Procesar incremento ---  
PROC_INCREMENTAR:  
    RCALL   ANTIRREBOTE      ; Espera a que el botón se estabilice  
    SBIC    PIND, 2          ; *Verificar nuevamente:   
                            ; Si PD2=1 (se soltó), retornar  
    RET  
    INC     R18  
    ANDI    R18, 0x0F        ; Limitar a 4 bits (0-15)  
    RET  

; --- Procesar decremento ---  
PROC_DECREMENTAR:  
    RCALL   ANTIRREBOTE      ; Espera 20ms  
    SBIC    PIND, 3          ; *Verificar nuevamente: si PD3=1, retornar   
    RET  
    CPI     R18, 0x00        ; ¿Contador es 0?  
    BRNE    DEC_CONTADOR      
    LDI     R18, 0x0F        ; Si es 0, recargar a 15  
    RET  
DEC_CONTADOR:  
    DEC     R18  
    ANDI    R18, 0x0F        ; Asegurar 4 bits  
    RET  

; --- Antirrebote robusto (20ms) ---  
ANTIRREBOTE:  
    LDI     R19, 210  
BUCLE1:  
    LDI     R20, 255  
BUCLE2:  
    LDI     R21, 25  
BUCLE3:  
    DEC     R21  
    BRNE    BUCLE3  
    DEC     R20  
    BRNE    BUCLE2  
    DEC     R19  
    BRNE    BUCLE1  
    RET