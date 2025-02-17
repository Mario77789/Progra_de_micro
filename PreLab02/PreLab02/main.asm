.include "m328pdef.inc"  

// Definiciones y variables  
.cseg  
.org 0x0000
.def    TEMP    = R16
.def    COUNTER = R17        ; Contador para 100ms
.def    SECOND_COUNTER = R18 ; Contador para segundos
.def    HEX_COUNT = R19      ; Contador hexadecimal con botones
.def    BUTTON_STATE = R20   ; Estado de botones
.def    LED_STATE = R21      ; Estado del LED indicador
.def    DECISECONDS = R22    ; Contador de décimas de segundo (para 1s)

// Tabla de conversión para display de 7 segmentos (cátodo común)
SEGMENT_TABLE:
    .db 0b00111111, 0b00000110, 0b01011011, 0b01001111  ; 0-3
    .db 0b01100110, 0b01101101, 0b01111101, 0b00000111  ; 4-7
    .db 0b01111111, 0b01101111, 0b01110111, 0b01111100  ; 8-B
    .db 0b00111001, 0b01011110, 0b01111001, 0b01110001  ; C-F

// Configuración del Stack  
LDI     TEMP, LOW(RAMEND)   
OUT     SPL, TEMP           
LDI     TEMP, HIGH(RAMEND)  
OUT     SPH, TEMP           

SETUP:  
    ; Configurar el reloj -> Prescaler a 16 (1 MHz)  
    LDI     TEMP, (1 << CLKPCE)    
    STS     CLKPR, TEMP  
    LDI     TEMP, 0b00000100       
    STS     CLKPR, TEMP  

    ; Configurar Timer 0 -> Prescaler a 64  
    LDI     TEMP, (1 << CS01) | (1 << CS00)  
    OUT     TCCR0B, TEMP           
    
    ; Inicializar registros  
    LDI     TEMP, 100              
    OUT     TCNT0, TEMP  
    CLR     COUNTER
    CLR     SECOND_COUNTER
    CLR     HEX_COUNT
    CLR     BUTTON_STATE
    CLR     LED_STATE
    CLR     DECISECONDS

    ; Configurar PB0-PB3 como salidas para el contador binario
    ; y PB4 para el LED indicador
    LDI     TEMP, 0b00011111  
    OUT     DDRB, TEMP
    OUT     PORTB, SECOND_COUNTER    

    ; Configurar PC0 y PC1 como entradas para los botones con pull-up
    CBI     DDRC, PC0
    CBI     DDRC, PC1
    SBI     PORTC, PC0
    SBI     PORTC, PC1

    ; Configurar PD0-PD7 como salidas para el display
    LDI     TEMP, 0b11111111  
    OUT     DDRD, TEMP

    RCALL   UPDATE_DISPLAY

MAIN_LOOP:  
    RCALL   CHECK_TIMER
    RCALL   CHECK_BUTTONS
    RJMP    MAIN_LOOP

CHECK_TIMER:
    IN      TEMP, TIFR0
    SBRS    TEMP, TOV0
    RET

    ; Limpiar bandera y recargar Timer 0
    SBI     TIFR0, TOV0
    LDI     TEMP, 100
    OUT     TCNT0, TEMP  

    ; Incrementar contador cada 100ms
    INC     COUNTER
    CPI     COUNTER, 10
    BRNE    TIMER_END

    ; Han pasado 100ms * 10 = 1 segundo
    CLR     COUNTER
    
    ; Incrementar contador de segundos y mantenerlo en 4 bits
    INC     SECOND_COUNTER
    ANDI    SECOND_COUNTER, 0x0F
    
    ; Mostrar valor actual en PORTB (excluyendo PB4)
    IN      TEMP, PORTB        ; Leer estado actual de PORTB
    ANDI    TEMP, 0b00010000  ; Mantener solo el bit del LED (PB4)
    MOV     LED_STATE, TEMP    ; Guardar estado del LED
    MOV     TEMP, SECOND_COUNTER
    ANDI    TEMP, 0x0F        ; Asegurar solo 4 bits
    OR      TEMP, LED_STATE    ; Combinar con estado del LED
    OUT     PORTB, TEMP       ; Actualizar PORTB

    ; Comparar contador de segundos con contador hexadecimal
    MOV     TEMP, SECOND_COUNTER
    CP      TEMP, HEX_COUNT
    BRNE    TIMER_END

    ; Si son iguales, reiniciar contador de segundos
    CLR     SECOND_COUNTER
    
    ; Toggle LED en PB4
    IN      TEMP, PORTB       ; Leer estado actual
    LDI     LED_STATE, (1 << PB4)
    EOR     TEMP, LED_STATE   ; Toggle solo PB4
    OUT     PORTB, TEMP       ; Actualizar salida

TIMER_END:
    RET

CHECK_BUTTONS:
    ; Verificar botón de incremento (PC0)
    SBIC    PINC, PC0
    RJMP    CHECK_DEC
    
    RCALL   DEBOUNCE
    SBIC    PINC, PC0
    RJMP    CHECK_DEC
    
    INC     HEX_COUNT
    ANDI    HEX_COUNT, 0x0F
    RCALL   UPDATE_DISPLAY
    
WAIT_INC:
    RCALL   CHECK_TIMER
    SBIS    PINC, PC0
    RJMP    WAIT_INC

CHECK_DEC:
    SBIC    PINC, PC1
    RET
    
    RCALL   DEBOUNCE
    SBIC    PINC, PC1
    RET
    
    DEC     HEX_COUNT
    ANDI    HEX_COUNT, 0x0F
    RCALL   UPDATE_DISPLAY
    
WAIT_DEC:
    RCALL   CHECK_TIMER
    SBIS    PINC, PC1
    RJMP    WAIT_DEC
    
    RET

UPDATE_DISPLAY:
    MOV     ZL, HEX_COUNT
    LDI     ZH, HIGH(SEGMENT_TABLE << 1)
    LDI     ZL, LOW(SEGMENT_TABLE << 1)
    ADD     ZL, HEX_COUNT
    LPM     TEMP, Z
    OUT     PORTD, TEMP
    RET

DEBOUNCE:
    LDI     TEMP, 100
DEBOUNCE_LOOP:
    DEC     TEMP
    BRNE    DEBOUNCE_LOOP
    RET