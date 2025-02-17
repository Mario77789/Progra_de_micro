;************************************************************  
; Universidad del Valle de Guatemala  
; IE2023: Programación de Microcontroladores  
;  
; Author  : Mario Fernando Cano Itzep  
; Proyecto: Prelab02 Modificado  
; Hardware: ATmega328P  
; Creado  : 11/02/2025  
;************************************************************   
.include "m328pdef.inc"  

// Definiciones y variables  
.cseg  
.org 0x0000                  ; Establecer la dirección de inicio del código  
.def    TEMP    = R16        ; Definir el registro TEMP para uso temporal  
.def    COUNTER = R17        ; Contador para 100 ms  
.def    SECOND_COUNTER = R18  ; Contador para segundos  
.def    HEX_COUNT = R19       ; Contador hexadecimal que se incrementa con botones  
.def    BUTTON_STATE = R20    ; Estado de los botones (no utilizado en este código)  
.def    LED_STATE = R21       ; Estado del LED indicador  
.def    DECISECONDS = R22     ; Contador de décimas de segundo (no utilizado)  

// Tabla de conversión para display de 7 segmentos (cátodo común)  
SEGMENT_TABLE:  
    .db 0b00111111, 0b00000110, 0b01011011, 0b01001111  ; 0-3  
    .db 0b01100110, 0b01101101, 0b01111101, 0b00000111  ; 4-7  
    .db 0b01111111, 0b01101111, 0b01110111, 0b01111100  ; 8-B  
    .db 0b00111001, 0b01011110, 0b01111001, 0b01110001  ; C-F  

// Configuración del Stack  
LDI     TEMP, LOW(RAMEND)    ; Cargar la parte baja de RAMEND en TEMP  
OUT     SPL, TEMP            ; Establecer la parte baja del puntero de pila  
LDI     TEMP, HIGH(RAMEND)   ; Cargar la parte alta de RAMEND en TEMP  
OUT     SPH, TEMP            ; Establecer la parte alta del puntero de pila  

SETUP:  
    ; Configurar el reloj -> Prescaler a 16 (1 MHz)  
    LDI     TEMP, (1 << CLKPCE)    ; Habilitar el cambio de prescaler  
    STS     CLKPR, TEMP            ; Escribir en el registro CLKPR  
    LDI     TEMP, 0b00000100       ; Configurar prescaler a 16  
    STS     CLKPR, TEMP            ; Escribir en el registro CLKPR  

    ; Configurar Timer 0 -> Prescaler a 64  
    LDI     TEMP, (1 << CS01) | (1 << CS00)  ; Configurar prescaler a 64  
    OUT     TCCR0B, TEMP            ; Escribir en el registro de control del Timer 0  
    
    ; Inicializar registros  
    LDI     TEMP, 100              ; Cargar 100 en TEMP para el Timer  
    OUT     TCNT0, TEMP            ; Inicializar el Timer 0 con 100  
    CLR     COUNTER                ; Inicializar el contador de 100 ms en 0  
    CLR     SECOND_COUNTER         ; Inicializar el contador de segundos en 0  
    CLR     HEX_COUNT              ; Inicializar el contador hexadecimal en 0  
    CLR     BUTTON_STATE           ; Inicializar el estado de los botones en 0  
    CLR     LED_STATE              ; Inicializar el estado del LED en 0  

    ; Configurar PB0-PB3 como salidas para el contador binario  
    ; y PB4 para el LED indicador  
    LDI     TEMP, 0b00011111       ; Configurar PB0-PB3 como salidas y PB4 como salida para el LED  
    OUT     DDRB, TEMP             ; Escribir en el registro de dirección de puerto B  
    OUT     PORTB, SECOND_COUNTER   ; Mostrar el contador de segundos en PORTB    

    ; Configurar PC0 y PC1 como entradas para los botones con pull-up  
    CBI     DDRC, PC0              ; Configurar PC0 como entrada  
    CBI     DDRC, PC1              ; Configurar PC1 como entrada  
    SBI     PORTC, PC0             ; Activar resistencia pull-up en PC0  
    SBI     PORTC, PC1             ; Activar resistencia pull-up en PC1  

    ; Configurar PD0-PD7 como salidas para el display  
    LDI     TEMP, 0b11111111       ; Configurar PD0-PD7 como salidas  
    OUT     DDRD, TEMP             ; Escribir en el registro de dirección de puerto D  

    RCALL   UPDATE_DISPLAY          ; Actualizar el display inicialmente  

MAIN_LOOP:  
    RCALL   CHECK_TIMER             ; Verificar el temporizador  
    RCALL   CHECK_BUTTONS           ; Verificar el estado de los botones  
    RJMP    MAIN_LOOP               ; Repetir el ciclo principal  

CHECK_TIMER:  
    IN      TEMP, TIFR0            ; Leer el registro de interrupción del Timer 0  
    SBRS    TEMP, TOV0              ; Si no hay desbordamiento, salir  
    RET                             ; Salir de la función  

    ; Limpiar bandera y recargar Timer 0  
    SBI     TIFR0, TOV0            ; Limpiar la bandera de desbordamiento  
    LDI     TEMP, 100              ; Cargar 100 en TEMP para el Timer  
    OUT     TCNT0, TEMP            ; Reiniciar el Timer 0  

    ; Incrementar contador cada 100ms  
    INC     COUNTER                ; Incrementar el contador de 100 ms  
    CPI     COUNTER, 10            ; Comparar con 10 (1 segundo)  
    BRNE    TIMER_END              ; Si no es igual, salir  

    ; Han pasado 1 segundo  
    CLR     COUNTER                ; Reiniciar el contador de 100 ms  
    
    ; Incrementar contador de segundos y mantenerlo en 4 bits  
    INC     SECOND_COUNTER         ; Incrementar el contador de segundos  
    ANDI    SECOND_COUNTER, 0x0F   ; Asegurar que se mantenga en 4 bits  
    
    ; Mostrar valor actual en PORTB (excluyendo PB4)  
    MOV     TEMP, SECOND_COUNTER   ; Mover el valor del contador de segundos a TEMP  
    OUT     PORTB, TEMP            ; Mostrar el valor en PORTB  

    ; Comparar contador de segundos con contador hexadecimal  
    MOV     TEMP, SECOND_COUNTER    ; Mover el contador de segundos a TEMP  
    CP      TEMP, HEX_COUNT        ; Comparar con el contador hexadecimal  
    BRNE    TIMER_END              ; Si no son iguales, salir  

    ; Si son iguales, reiniciar contador de segundos  
    CLR     SECOND_COUNTER          ; Reiniciar el contador de segundos  
    
    ; Toggle LED en PB4  
    IN      TEMP, PORTB            ; Leer estado actual de PORTB  
    LDI     LED_STATE, (1 << PB4)  ; Cargar el valor para cambiar el estado del LED  
    EOR     TEMP, LED_STATE         ; Cambiar el estado del LED (toggle)  
    OUT     PORTB, TEMP            ; Actualizar salida de PORTB  

TIMER_END:  
    RET                             ; Salir de la función  

CHECK_BUTTONS:  
    ; Verificar botón de incremento (PC0)  
    SBIC    PINC, PC0              ; Si PC0 está presionado, continuar  
    RJMP    CHECK_DEC               ; Si no, verificar decremento  
    
    RCALL   DEBOUNCE                ; Llamar a la rutina de debounce  
    SBIC    PINC, PC0              ; Verificar de nuevo si PC0 está presionado  
    RJMP    CHECK_DEC               ; Si no, ir a verificar decremento  
    
    INC     HEX_COUNT               ; Incrementar el contador hexadecimal  
    ANDI    HEX_COUNT, 0x0F         ; Asegurar que se mantenga en 4 bits  
    RCALL   UPDATE_DISPLAY           ; Actualizar el display de 7 segmentos  
    
WAIT_INC:  
    RCALL   CHECK_TIMER              ; Verificar el temporizador  
    SBIS    PINC, PC0               ; Si PC0 no está presionado, esperar  
    RJMP    WAIT_INC                 ; Repetir hasta que se suelte el botón  

CHECK_DEC:  
    SBIC    PINC, PC1               ; Si PC1 está presionado, continuar  
    RET                             ; Si no, salir  
    
    RCALL   DEBOUNCE                 ; Llamar a la rutina de debounce  
    SBIC    PINC, PC1               ; Verificar de nuevo si PC1 está presionado  
    RET                             ; Si no, salir  
    
    DEC     HEX_COUNT                ; Decrementar el contador hexadecimal  
    ANDI    HEX_COUNT, 0x0F         ; Asegurar que se mantenga en 4 bits  
    RCALL   UPDATE_DISPLAY           ; Actualizar el display de 7 segmentos  
    
WAIT_DEC:  
    RCALL   CHECK_TIMER              ; Verificar el temporizador  
    SBIS    PINC, PC1               ; Si PC1 no está presionado, esperar  
    RJMP    WAIT_DEC                 ; Repetir hasta que se suelte el botón  
    
    RET                             ; Salir de la función  

UPDATE_DISPLAY:  
    MOV     ZL, HEX_COUNT           ; Mover el contador hexadecimal a ZL  
    LDI     ZH, HIGH(SEGMENT_TABLE << 1)  ; Cargar la parte alta de la tabla de segmentos  
    LDI     ZL, LOW(SEGMENT_TABLE << 1)   ; Cargar la parte baja de la tabla de segmentos  
    ADD     ZL, HEX_COUNT           ; Sumar el contador hexadecimal para obtener la dirección  
    LPM     TEMP, Z                 ; Cargar el valor del display desde la memoria  
    OUT     PORTD, TEMP             ; Mostrar el valor en el display  
    RET                             ; Salir de la función  

DEBOUNCE:  
    LDI     TEMP, 100               ; Cargar un valor de espera para el debounce  
DEBOUNCE_LOOP:  
    DEC     TEMP                    ; Decrementar el contador de espera  
    BRNE    DEBOUNCE_LOOP           ; Repetir hasta que TEMP llegue a 0  
    RET                             ; Salir de la función