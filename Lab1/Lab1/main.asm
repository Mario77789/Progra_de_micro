;***********************************************************  
; Universidad del Valle de Guatemala  
; IE2023: Programación de Microcontroladores  
; ContadorBinario.asm  
;  
; Created: 11/02/25
; Author : Mario Fernando Cano Itzep
; Descripción: Contador Binario Dual con anti-rebote y suma de 4 bits
;***********************************************************  

.INCLUDE "M328PDEF.INC"

.CSEG
.ORG 0x0000

; Configuración de la pila
    LDI     R16, LOW(RAMEND)
    OUT     SPL, R16
    LDI     R16, HIGH(RAMEND)
    OUT     SPH, R16

; Configuración de puertos
SETUP:
    ; Puerto D como salida (LEDs C1 y C2)
    LDI     R16, 0xFF
    OUT     DDRD, R16

    ; Puerto B como salida (Resultado + Overflow)
    LDI     R16, 0x1F        ; PB0-PB4 como salidas
    OUT     DDRB, R16

    ; Puerto C como entrada con pull-ups (Botones)
    LDI     R16, 0x00
    OUT     DDRC, R16
    LDI     R16, 0x1F        ; Pull-ups en PC0-PC4
    OUT     PORTC, R16

    ; Inicializar contadores
    CLR     R17               ; Contador 1
    CLR     R18               ; Contador 2

; Bucle principal
LOOP:
    ; Leer botones Contador 1
    SBIS    PINC, 0           ; Incrementar C1
    RCALL   BOTON_INC_C1
    SBIS    PINC, 1           ; Decrementar C1
    RCALL   BOTON_DEC_C1

    ; Leer botones Contador 2
    SBIS    PINC, 2           ; Incrementar C2
    RCALL   BOTON_INC_C2
    SBIS    PINC, 3           ; Decrementar C2
    RCALL   BOTON_DEC_C2

    ; Leer botón de suma
    SBIS    PINC, 4
    RCALL   MOSTRAR_SUMA

    ; Actualizar LEDs
    RCALL   ACTUALIZAR_DISPLAY
    RJMP    LOOP

; Subrutinas de manejo de botones
BOTON_INC_C1:
    RCALL   ANTIRREBOTE
    SBIS    PINC, 0
    RET
    RCALL   INCREMENTAR_C1
    RET

BOTON_DEC_C1:
    RCALL   ANTIRREBOTE
    SBIS    PINC, 1
    RET
    RCALL   DECREMENTAR_C1
    RET

BOTON_INC_C2:
    RCALL   ANTIRREBOTE
    SBIS    PINC, 2
    RET
    RCALL   INCREMENTAR_C2
    RET

BOTON_DEC_C2:
    RCALL   ANTIRREBOTE
    SBIS    PINC, 3
    RET
    RCALL   DECREMENTAR_C2
    RET

; Subrutinas de contadores
INCREMENTAR_C1:
    INC     R17
    ANDI    R17, 0x0F         ; Limitar a 4 bits
    RET

DECREMENTAR_C1:
    CPI     R17, 0x00
    BREQ    DEC_C1_OVER
    DEC     R17
    RET
DEC_C1_OVER:
    LDI     R17, 0x0F
    RET

INCREMENTAR_C2:
    INC     R18
    ANDI    R18, 0x0F         ; Limitar a 4 bits
    RET

DECREMENTAR_C2:
    CPI     R18, 0x00
    BREQ    DEC_C2_OVER
    DEC     R18
    RET
DEC_C2_OVER:
    LDI     R18, 0x0F
    RET

; Subrutina de visualización
ACTUALIZAR_DISPLAY:
    MOV     R16, R17          ; Cargar C1
    SWAP    R18               ; Preparar C2
    OR      R16, R18          ; Combinar ambos contadores
    OUT     PORTD, R16        ; Actualizar LEDs
    SWAP    R18               ; Restaurar C2
    RET

; Subrutina de suma
MOSTRAR_SUMA:
    RCALL   ANTIRREBOTE
    SBIS    PINC, 4
    RET
    
    MOV     R19, R17          ; Cargar C1
    ADD     R19, R18          ; Sumar C2
    MOV     R16, R19
    
    ; Manejar overflow
    ANDI    R16, 0x1F         ; Máscara para 5 bits
    CPI     R19, 0x10
    BRLO    NO_OVERFLOW
    ORI     R16, 0x10         ; Activar bit de overflow
NO_OVERFLOW:
    OUT     PORTB, R16        ; Mostrar resultado
    RET

; Subrutina anti-rebote (20ms @ 1MHz)
ANTIRREBOTE:
    LDI     R19, 27
DELAY1:
    LDI     R20, 250
DELAY2:
    DEC     R20
    BRNE    DELAY2
    DEC     R19
    BRNE    DELAY1
    RET