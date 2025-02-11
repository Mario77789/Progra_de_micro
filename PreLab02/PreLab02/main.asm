;************************************************************  
; Universidad del Valle de Guatemala  
; IE2023: Programación de Microcontroladores  
;  
; Author  : Mario Fernando Cano Itzep  
; Proyecto: Prelab02  
; Hardware: ATmega328P  
; Creado  : 11/02/2025  
;************************************************************  

.include "m328pdef.inc"  

;  
; Definiciones y variables  
.cseg  
.org 0x0000                 ; Dirección de Reset (inicio del programa)  
.def    TEMP    = R16       ; Registro temporal  
.def    COUNTER = R17       ; Contador para incrementar cada 100 ms  
.def    BINARY_COUNT = R18  ; Registro para almacenar el valor del contador binario  

;  
; Configuración del Stack  
LDI     TEMP, LOW(RAMEND)   ; Cargar valor bajo de la RAM  
OUT     SPL, TEMP           ; Configurar pila inferior  
LDI     TEMP, HIGH(RAMEND)  ; Cargar valor alto de la RAM  
OUT     SPH, TEMP           ; Configurar pila superior  

;  
; Configuración del microcontrolador  
SETUP:  
    ; Configurar el reloj -> Prescaler a 16 (1 MHz)  
    LDI     TEMP, (1 << CLKPCE)    ; Habilitar cambio de prescaler  
    STS     CLKPR, TEMP  
    LDI     TEMP, 0b00000100       ; Prescaler a 16  
    STS     CLKPR, TEMP  

    ; Configurar Timer 0 -> Prescaler a 64  
    LDI     TEMP, (1 << CS01) | (1 << CS00)  
    OUT     TCCR0B, TEMP           ; Prescaler de Timer 0 = 64  
    
    ; Inicializar registros  
    LDI     TEMP, 131              ; Cargar valor inicial en TCNT0 (para 10 ms)  
    OUT     TCNT0, TEMP  
    CLR     COUNTER                ; Inicializar contador  
    CLR     BINARY_COUNT           ; Inicializar valor binario del contador  

    ; Configurar PD4-PD7 como salidas para el contador  
    LDI     TEMP, 0b11110000       ; Configurar los bits PD4-PD7 como salida  
    OUT     DDRD, TEMP             ; Hacer efectiva la configuración en DDRD  
    OUT     PORTD, BINARY_COUNT    ; Inicializar puerto PORTD en 0  

;  
; Loop principal  
MAIN_LOOP:  
    ; Esperar por el desbordamiento del Timer 0  
WAIT_OVERFLOW:  
    IN      TEMP, TIFR0            ; Leer el registro de interrupciones  
    SBRS    TEMP, TOV0             ; Saltar si TOV0 no está configurado  
    RJMP    WAIT_OVERFLOW          ; Esperar hasta que el Timer se desborde  
    SBI     TIFR0, TOV0            ; Limpiar la bandera TOV0  

    ; Recargar el Timer 0 para 10 ms  
    LDI     TEMP, 131              
    OUT     TCNT0, TEMP  

    ; Incrementar el contador cada 10 ms  
    INC     COUNTER                ; Incrementar el contador de tiempos de 10 ms  
    CPI     COUNTER, 10            ; ¿Hemos llegado a 100 ms? (10 x 10 ms)  
    BRNE    MAIN_LOOP              ; No -> regresar al inicio del loop  

    ; Reiniciar el contador de tiempos y actualizar la salida  
    CLR     COUNTER                ; Reiniciar el contador de tiempos  
    INC     BINARY_COUNT           ; Incrementar el conteo del contador binario (4 bits)  
    ANDI    BINARY_COUNT, 0x0F     ; Asegurar que sólo usaremos los 4 bits menos significativos  

    ; Actualizar la salida en PORTD (PD4-PD7)  
    MOV     TEMP, BINARY_COUNT     ; Copiar el valor del contador binario a TEMP  
    LSL     TEMP                   ; Desplazar izquierda (1 bit)  
    LSL     TEMP                   ; Segundo desplazamiento  
    LSL     TEMP                   ; Tercer desplazamiento  
    LSL     TEMP                   ; Cuarto desplazamiento  
    ANDI    TEMP, 0b11110000       ; Limitar los valores a los bits PD4-PD7  
    OUT     PORTD, TEMP            ; Escribir en PORTD para actualizar los LEDs  
    
    RJMP    MAIN_LOOP              ; Repetir el ciclo