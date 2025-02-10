;************************************************************  
; Universidad del Valle de Guatemala  
; IE2023: Programación de Microcontroladores  
; ContadorBinarioDoble.asm  
;  
; Author  : Mario Fernando Cano Itzep  
; Proyecto: Contador Binario Dual + Suma y Carry  
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

    ; Configurar Puerto C como salida (Contador 2 LEDs y suma)  
    LDI     R16, 0xFF  
    OUT     DDRC, R16  

    ; Configurar PD7 como salida (LED de carry/overflow)  
    SBI     DDRD, 7            ; Configura PD7 como salida  

    ; Inicializar contadores en 0  
    CLR     R18                ; Contador 1 (R18)  
    CLR     R19                ; Contador 2 (R19)  
    CLR     R20                ; Registro para la suma de los contadores  
    CLR     R21                ; Registro para el LED de carry/overflow  

    RJMP    MAIN  

; ----------------------------------------------------------  
; Bucle principal  
MAIN:  
    RCALL   CONTADOR_1         ; Manejar Contador 1  
    RCALL   CONTADOR_2         ; Manejar Contador 2  
    RCALL   MOSTRAR_SUMA       ; Manejar y mostrar suma cuando sea necesario  
    OUT     PORTB, R18         ; Mostrar Contador 1 en LEDs (PORTB)  
    OUT     PORTC, R19         ; Mostrar Contador 2 en LEDs (PORTC)  
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
    SBIS    PIND, 2            ; Si el botón en PD2 está presionado:  
    RCALL   INC_CONTADOR1      

    ; Decrementar Contador 1 (PD3)  
    SBIS    PIND, 3            ; Si el botón en PD3 está presionado:  
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
    RCALL   ANTIRREBOTE        ; Elimina el rebote del botón  
    SBIC    PIND, 2            ; Verifica si el botón sigue presionado  
    RET  
    INC     R18                ; Incrementa el valor en el registro R18  
    ANDI    R18, 0x0F          ; Limita el valor a 4 bits (0-15)  
    RET  

DEC_CONTADOR1:  
    RCALL   ANTIRREBOTE  
    SBIC    PIND, 3  
    RET  
    CPI     R18, 0x00          ; Compara: ¿R18 = 0?  
    BRNE    DEC1               ; Si no es 0, decrementa  
    LDI     R18, 0x0F          ; Si es 0, lo envuelve a 15  
    RET  
DEC1:  
    DEC     R18  
    ANDI    R18, 0x0F          ; Limita el valor a 4 bits  
    RET  

; ----------------------------------------------------------  
; Subrutinas para incrementar y decrementar Contador 2  
INC_CONTADOR2:  
    RCALL   ANTIRREBOTE  
    SBIC    PIND, 4  
    RET  
    INC     R19  
    ANDI    R19, 0x0F  
    RET  

DEC_CONTADOR2:  
    RCALL   ANTIRREBOTE  
    SBIC    PIND, 5  
    RET  
    CPI     R19, 0x00          ; ¿Contador en 0?  
    BRNE    DEC2  
    LDI     R19, 0x0F  
    RET  
DEC2:  
    DEC     R19  
    ANDI    R19, 0x0F  
    RET  

; ----------------------------------------------------------  
; Subrutina para manejar y mostrar la suma
MOSTRAR_SUMA:  
    SBIS    PIND, 6            ; Verificar si el botón de suma (PD6) está presionado  
    RET                        ; Si no está presionado, salir de la rutina  

    RCALL   ANTIRREBOTE        ; Eliminar rebote del botón  
    CLR     R20                ; Limpia el registro donde se almacenará la suma  
    MOV     R22, R18           ; Copiar el valor del Contador 1 al registro temporal R22  
    MOV     R23, R19           ; Copiar el valor del Contador 2 al registro temporal R23  

    ; Limitar ambos valores a 4 bits  
    ANDI    R22, 0x0F          ; Limitar R22 a 4 bits bajos  
    ANDI    R23, 0x0F          ; Limitar R23 a 4 bits bajos  

    ; Realizar la suma  
    ADD     R20, R22           ; Sumar Contador 1 al acumulador  
    ADD     R20, R23           ; Sumar Contador 2 al acumulador  

    ; Verificar el carry y manejar el LED en PD7  
    BRCC    SIN_CARRY          ; Si no hay carry, saltar  
    SBI     PORTD, 7           ; Encender LED de carry en PD7  
    RJMP    MOSTRAR_RESULTADO  

SIN_CARRY:  
    CBI     PORTD, 7           ; Apagar LED de carry en PD7  

MOSTRAR_RESULTADO:  
    ANDI    R20, 0x0F          ; Limitar la suma a 4 bits  
    OUT     PORTC, R20         ; Mostrar la suma en PORTC  
    RET  

; ----------------------------------------------------------  
; Subrutina de antirrebote  
ANTIRREBOTE:  
    LDI     R20, 40  
DELAY_LOOP:  
    DEC     R20  
    BRNE    DELAY_LOOP  
    RET