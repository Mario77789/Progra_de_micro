;************************************************************  
; Universidad del Valle de Guatemala  
; IE2023: Programación de Microcontroladores  
; ContadorBinarioDoble.asm  
;  
; Author  : Mario Fernando Cano Itzep  
; Proyecto: Contador Binario Dual + Antirrebote  
; Hardware: ATmega328P  
; Creado  : 04/02/2025  
;************************************************************  
.INCLUDE "M328PDEF.inc"  

.cseg  
.org 0x0000  

; ----------------------------------------------------------  
; Configuración de pila  
RESET:  
    LDI     R16, LOW(RAMEND)   ; Inicializa la pila  
    OUT     SPL, R16  
    LDI     R16, HIGH(RAMEND)  
    OUT     SPH, R16  

; ----------------------------------------------------------  
; Configuración inicial del MCU  
SETPU:  
    ; Configurar Puerto D como entrada con pull-ups (botones)  
    LDI     R16, 0x00          ; Entradas para botones en PORTD  
    OUT     DDRD, R16  
    LDI     R16, 0xFF          ; Activa pull-ups en entradas  
    OUT     PORTD, R16  

    ; Configurar Puerto B como salida (Contador 1 LEDs)  
    LDI     R16, 0xFF  
    OUT     DDRB, R16  

    ; Configurar Puerto C como salida (Contador 2 LEDs)  
    LDI     R16, 0xFF  
    OUT     DDRC, R16  

    ; Inicializar contadores en 0  
    CLR     R18                ; Contador 1 (R18)  
    CLR     R19                ; Contador 2 (R19)  

    RJMP    MAIN  

; ----------------------------------------------------------  
; Bucle principal  
MAIN:  
    RCALL   CONTADOR_1         ; Manejar Contador 1  
    RCALL   CONTADOR_2         ; Manejar Contador 2  
    OUT     PORTB, R18         ; Mostrar Contador 1 en LEDs  
    OUT     PORTC, R19         ; Mostrar Contador 2 en LEDs  
    RJMP    MAIN  

; ----------------------------------------------------------  
; Subrutina para manejar el Contador 1  
CONTADOR_1:  
    RCALL   LEER_BOTONES_C1    ; Verifica los botones del Contador 1  
    RET  

; Subrutina para manejar el Contador 2  
CONTADOR_2:  
    RCALL   LEER_BOTONES_C2    ; Verifica los botones del Contador 2  
    RET  

; ----------------------------------------------------------  
; Subrutina para leer botones del Contador 1  
LEER_BOTONES_C1:  
    ; Incrementar Contador 1 (PD2)  
    SBIS    PIND, 2  
    RCALL   INC_CONTADOR1  

    ; Decrementar Contador 1 (PD3)  
    SBIS    PIND, 3  
    RCALL   DEC_CONTADOR1  

    RET  

; Subrutina para leer botones del Contador 2  
LEER_BOTONES_C2:  
    ; Incrementar Contador 2 (PD4)  
    SBIS    PIND, 4  
    RCALL   INC_CONTADOR2  

    ; Decrementar Contador 2 (PD5)  
    SBIS    PIND, 5  
    RCALL   DEC_CONTADOR2  

    RET  

; ----------------------------------------------------------  
; Subrutinas para incrementar y decrementar Contador 1  
INC_CONTADOR1:  
    RCALL   ANTIRREBOTE        ; Llama al antirrebote para el botón 1  
    SBIC    PIND, 2            ; Verifica si el botón sigue presionado  
    RET  
    INC     R18                ; Incrementa el contador 1  
    ANDI    R18, 0x0F          ; Limita a 4 bits  
    RET  

DEC_CONTADOR1:  
    RCALL   ANTIRREBOTE        ; Llama al antirrebote  
    SBIC    PIND, 3            ; Verifica si el botón sigue presionado  
    RET  
    CPI     R18, 0x00          ; ¿El contador está en 0?  
    BRNE    DEC1               ; Si no, decrementa  
    LDI     R18, 0x0F          ; Si está en 0, envuélvelo a 15  
    RET  
DEC1:  
    DEC     R18                ; Decrementa el contador  
    ANDI    R18, 0x0F          ; Limita a 4 bits  
    RET  

; ----------------------------------------------------------  
; Subrutinas para incrementar y decrementar Contador 2  
INC_CONTADOR2:  
    RCALL   ANTIRREBOTE        ; Llama al antirrebote para el botón  
    SBIC    PIND, 4            ; Verifica si el botón sigue presionado  
    RET  
    INC     R19                ; Incrementa el contador 2  
    ANDI    R19, 0x0F          ; Limita a 4 bits  
    RET  

DEC_CONTADOR2:  
    RCALL   ANTIRREBOTE        ; Llama al antirrebote  
    SBIC    PIND, 5            ; Verifica si el botón sigue presionado  
    RET  
    CPI     R19, 0x00          ; ¿El contador está en 0?  
    BRNE    DEC2               ; Si no, decrementa  
    LDI     R19, 0x0F          ; Si está en 0, envuélvelo a 15  
    RET  
DEC2:  
    DEC     R19                ; Decrementa el contador  
    ANDI    R19, 0x0F          ; Limita a 4 bits  
    RET  

; ----------------------------------------------------------  
; Subrutina de antirrebote  
ANTIRREBOTE:  
    LDI     R20, 210           ; Retardo estimado de 20 ms  
B1:  
    LDI     R21, 255  
B2:  
    LDI     R22, 50  
B3:  
    DEC     R22  
    BRNE    B3  
    DEC     R21  
    BRNE    B2  
    DEC     R20  
    BRNE    B1  
    RET