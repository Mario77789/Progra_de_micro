;***********************************************************  
; Universidad del Valle de Guatemala  
; IE2023: Programación de Microcontroladores  
; Lab 4: Contador hexadecimal en display de 7 segmentos  
; Modificación: Integración de contador automático y manual  
;***********************************************************  

.include "m328pdef.inc"  ; Incluir la definición del microcontrolador ATmega328P  

// Definiciones y variables  
.cseg  ; Comienza la sección de código  
.org 0x0000  ; Establece la dirección de inicio del programa en 0x0000  
.def    TEMP    = R16  ; Define TEMP como el registro R16 para uso temporal  
.def    COUNTER = R17  ; Contador para intervalos de 10 ms  
.def    SECOND_COUNTER = R18 ; Contador para segundos  
.def    HEX_COUNT = R19  ; Contador hexadecimal que se incrementa con botones  
.def    BUTTON_STATE = R20   ; Estado de los botones  
.def    LED_STATE = R21      ; Estado del LED indicador  
.def    DECISECONDS = R22    ; Contador de décimos de segundo (no utilizado)  

// Tabla de conversión para display de 7 segmentos (cátodo común)  
SEGMENT_TABLE:  
    .db   0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07  ; Representaciones de 0-7 en el display  
    .db   0x7F, 0x6F, 0x77, 0x7C, 0x39, 0x5E, 0x79, 0x71  ; Representaciones de 8-F en el display  

// Configuración del Stack  
LDI     TEMP, LOW(RAMEND)   ; Cargar el valor bajo de RAMEND en TEMP  
OUT     SPL, TEMP           ; Establecer el puntero de pila bajo  
LDI     TEMP, HIGH(RAMEND)  ; Cargar el valor alto de RAMEND en TEMP  
OUT     SPH, TEMP           ; Establecer el puntero de pila alto  

SETUP:  
    ; Configurar el reloj -> Prescaler a 16 (1 MHz)  
    LDI     TEMP, (1 << CLKPCE)    ; Habilitar cambio de prescaler  
    STS     CLKPR, TEMP             ; Guardar en el registro de control de reloj  
    LDI     TEMP, 0b00000100        ; Establecer el prescaler a 16  
    STS     CLKPR, TEMP             ; Aplicar el prescaler  

    ; Configurar Timer 0 -> Prescaler a 64  
    LDI     TEMP, (1 << CS01) | (1 << CS00)  ; Configurar prescaler a 64  
    OUT     TCCR0B, TEMP            ; Aplicar configuración al Timer 0  
    
    ; Inicializar registros  
    LDI     TEMP, 100               ; Inicializar el contador de Timer 0 a 100  
    OUT     TCNT0, TEMP             ; Cargar el valor en el registro de conteo  
    CLR     COUNTER                 ; Limpiar el contador de 10 ms  
    CLR     SECOND_COUNTER          ; Limpiar el contador de segundos  
    CLR     HEX_COUNT               ; Limpiar el contador hexadecimal  
    CLR     BUTTON_STATE            ; Limpiar el estado de los botones  
    CLR     LED_STATE               ; Limpiar el estado del LED  
    CLR     DECISECONDS             ; Limpiar el contador de décimos de segundo (no utilizado)  

    ; Configurar PB0-PB3 como salidas para el contador binario  
    ; y PB4 para el LED indicador  
    LDI     TEMP, 0b00011111  ; Configurar PB0-PB3 y PB4 como salidas  
    OUT     DDRB, TEMP        ; Aplicar configuración de dirección a PORTB  
    OUT     PORTB, SECOND_COUNTER    ; Inicializar PORTB con el contador de segundos    

    ; Configurar PC0 y PC1 como entradas para los botones con pull-up  
    CBI     DDRC, PC0         ; Configurar PC0 como entrada  
    CBI     DDRC, PC1         ; Configurar PC1 como entrada  
    SBI     PORTC, PC0        ; Activar resistencia pull-up en PC0  
    SBI     PORTC, PC1        ; Activar resistencia pull-up en PC1  

    ; Configurar PD0-PD7 como salidas para el display  
    LDI     TEMP, 0b11111111  ; Configurar PD0-PD7 como salidas  
    OUT     DDRD, TEMP        ; Aplicar configuración de dirección a PORTD  

    RCALL   UPDATE_DISPLAY     ; Llamar a la rutina para actualizar el display  

MAIN_LOOP:  
    RCALL   CHECK_TIMER        ; Verificar el temporizador  
    RCALL   CHECK_BUTTONS      ; Verificar el estado de los botones  
    RJMP    MAIN_LOOP          ; Repetir el ciclo principal  

CHECK_TIMER:  
    IN      TEMP, TIFR0       ; Leer la bandera de interrupción del Timer 0  
    SBRS    TEMP, TOV0        ; Si no hay desbordamiento, regresar  
    RET  

    ; Limpiar bandera y recargar Timer 0  
    SBI     TIFR0, TOV0       ; Limpiar la bandera de desbordamiento  
    LDI     TEMP, 100         ; Preparar el contador para 10 ms  
    OUT     TCNT0, TEMP       ; Cargar el valor en el registro de conteo  

    ; Incrementar contador cada 10ms  
    INC     COUNTER           ; Incrementar el contador de 10 ms  
    CPI     COUNTER, 100      ; Comparar el contador con 100 (1 segundo)  
    BRNE    TIMER_END         ; Si no es igual, regresar  

    ; Han pasado 10ms * 100 = 1 segundo  
    CLR     COUNTER           ; Reiniciar el contador de 10 ms  
    
    ; Incrementar contador de segundos y mantenerlo en 4 bits  
    INC     SECOND_COUNTER    ; Incrementar el contador de segundos  
    ANDI    SECOND_COUNTER, 0x0F  ; Asegurarse de que solo queden 4 bits  
    
    ; Mostrar valor actual en PORTB (excluyendo PB4)  
    IN      TEMP, PORTB       ; Leer estado actual de PORTB  
    ANDI    TEMP, 0b00010000  ; Mantener solo el bit del LED (PB4)  
    MOV     LED_STATE, TEMP    ; Guardar estado del LED  
    MOV     TEMP, SECOND_COUNTER  
    ANDI    TEMP, 0x0F        ; Asegurar solo 4 bits  
    OR      TEMP, LED_STATE    ; Combinar con estado del LED  
    OUT     PORTB, TEMP       ; Actualizar PORTB  

    ; Comparar contador de segundos con contador hexadecimal  
    MOV     TEMP, SECOND_COUNTER  
    CP      TEMP, HEX_COUNT   ; Comparar los contadores  
    BRNE    TIMER_END         ; Si no son iguales, regresar  

    ; Si son iguales, reiniciar contador de segundos  
    CLR     SECOND_COUNTER     ; Reiniciar el contador de segundos  
    
    ; Toggle LED en PB4  
    IN      TEMP, PORTB       ; Leer estado actual  
    LDI     LED_STATE, (1 << PB4)  ; Preparar el bit a togglear  
    EOR     TEMP, LED_STATE   ; Cambiar el estado del LED  
    OUT     PORTB, TEMP       ; Actualizar salida  

TIMER_END:  
    RET  

CHECK_BUTTONS:  
    ; Verificar botón de incremento (PC0)  
    SBIC    PINC, PC0         ; Si PC0 está en bajo (botón presionado), continuar  
    RJMP    CHECK_DEC          ; Si no, verificar decremento  
    
    RCALL   DEBOUNCE           ; Llamar a la rutina de debounce  
    SBIC    PINC, PC0         ; Si sigue bajo, continuar  
    RJMP    CHECK_DEC          ; Si no, verificar decremento  
    
    INC     HEX_COUNT         ; Incrementar el contador hexadecimal  
    ANDI    HEX_COUNT, 0x0F   ; Asegurarse de que se mantenga en 4 bits  
    RCALL   UPDATE_DISPLAY     ; Actualizar el display  
    
WAIT_INC:  
    RCALL   CHECK_TIMER        ; Verificar el temporizador  
    SBIS    PINC, PC0         ; Esperar hasta que PC0 se suelte  
    RJMP    WAIT_INC           ; Repetir hasta que se suelte  

CHECK_DEC:  
    SBIC    PINC, PC1         ; Si PC1 está en bajo (botón presionado), continuar  
    RET                        ; Si no, regresar  
    
    RCALL   DEBOUNCE           ; Llamar a la rutina de debounce  
    SBIC    PINC, PC1         ; Si sigue bajo, continuar  
    RET                        ; Si no, regresar  
    
    DEC     HEX_COUNT         ; Decrementar el contador hexadecimal  
    ANDI    HEX_COUNT, 0x0F   ; Asegurarse de que se mantenga en 4 bits  
    RCALL   UPDATE_DISPLAY     ; Actualizar el display  
    
WAIT_DEC:  
    RCALL   CHECK_TIMER        ; Verificar el temporizador  
    SBIS    PINC, PC1         ; Esperar hasta que PC1 se suelte  
    RJMP    WAIT_DEC           ; Repetir hasta que se suelte  

    RET  

UPDATE_DISPLAY:  
    MOV     ZL, HEX_COUNT     ; Mover el valor del contador hexadecimal a ZL  
    LDI     ZH, HIGH(SEGMENT_TABLE << 1)  ; Cargar la parte alta de la tabla de segmentos  
    LDI     ZL, LOW(SEGMENT_TABLE << 1)   ; Cargar la parte baja de la tabla de segmentos  
    ADD     ZL, HEX_COUNT     ; Sumar el valor del contador para obtener la dirección  
    LPM     TEMP, Z           ; Cargar el valor del segmento correspondiente  
    OUT     PORTD, TEMP       ; Enviar el valor al display  
    RET  

DEBOUNCE:  
    LDI     TEMP, 100         ; Inicializar un contador para el debounce  
DEBOUNCE_LOOP:  
    DEC     TEMP              ; Decrementar el contador  
    BRNE    DEBOUNCE_LOOP     ; Repetir hasta que el contador llegue a cero  
    RET                       ; Regresar de la rutina de debounce