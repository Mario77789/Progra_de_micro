;***********************************************************  
; Universidad del Valle de Guatemala  
; IE2023: Programación de Microcontroladores  
; ContadorBinario.asm  
;  
; Created: 11/02/25  
; Author : Mario Fernando Cano Itzep  
; Descripción: Contador Binario Dual con anti-rebote y suma de 4 bits  
;***********************************************************  

.INCLUDE "M328PDEF.INC" ; Incluir definiciones específicas del ATmega328P  

.CSEG  
.ORG 0x0000             ; La memoria del programa empieza desde la dirección 0x0000  

; ----------------------------------------------------------  
; Configuración de la pila para subrutinas y manejo correcto  
LDI     R16, LOW(RAMEND) ; Cargar el valor bajo de la dirección final de la RAM  
OUT     SPL, R16         ; Configurar el puntero de pila bajo (SP)  
LDI     R16, HIGH(RAMEND) ; Cargar el valor alto de la dirección final de la RAM  
OUT     SPH, R16         ; Configurar el puntero de pila alto (SP)  

; ----------------------------------------------------------  
; Configuración de los puertos de entrada y salida  
SETUP:  
    ; Configurar PORTD como salida (para LEDs de ambos contadores)  
    LDI     R16, 0xFF         ; Poner todos los bits de DDRD (PD0-PD7) como salidas  
    OUT     DDRD, R16         ; Hacer efectiva la configuración en el registro DDRD  

    ; Configurar PORTB como salida (para LEDs de resultado y overflow)  
    LDI     R16, 0x1F         ; Seleccionar PB0-PB4 como salidas (las demás son entradas)  
    OUT     DDRB, R16         ; Configurar la dirección de datos del PORTB  

    ; Configurar PORTC como entrada con pull-ups activados (para botones)  
    LDI     R16, 0x00         ; Configurar PC0-PC4 como entradas  
    OUT     DDRC, R16         ; Hacer efectiva la configuración en el registro DDRC  
    LDI     R16, 0x1F         ; Activar las resistencias pull-up en PC0-PC4  
    OUT     PORTC, R16        ; Hacer efectiva la configuración en el registro PORTC  

    ; Inicializar registros de los contadores  
    CLR     R17               ; Inicializar Contador 1 en 0  
    CLR     R18               ; Inicializar Contador 2 en 0  

; ----------------------------------------------------------  
; Bucle principal, ejecutado constantemente  
LOOP:  
    ; --- Verificar botón para incrementar Contador 1 (PC0) ---  
    SBIS    PINC, 0           ; Salta si el bit correspondiente de PC0 es alto  
    RCALL   BOTON_INC_C1      ; Llama a la subrutina de incrementar Contador 1  

    ; --- Verificar botón para decrementar Contador 1 (PC1) ---  
    SBIS    PINC, 1           ; Salta si el bit correspondiente de PC1 es alto  
    RCALL   BOTON_DEC_C1      ; Llama a la subrutina de decrementar Contador 1  

    ; --- Verificar botón para incrementar Contador 2 (PC2) ---  
    SBIS    PINC, 2           ; Salta si el bit correspondiente de PC2 es alto  
    RCALL   BOTON_INC_C2      ; Llama a la subrutina de incrementar Contador 2  

    ; --- Verificar botón para decrementar Contador 2 (PC3) ---  
    SBIS    PINC, 3           ; Salta si el bit correspondiente de PC3 es alto  
    RCALL   BOTON_DEC_C2      ; Llama a la subrutina de decrementar Contador 2  

    ; --- Verificar botón para calcular y mostrar suma (PC4) ---  
    SBIS    PINC, 4           ; Salta si el bit correspondiente de PC4 es alto  
    RCALL   MOSTRAR_SUMA      ; Llama a la subrutina para calcular y mostrar la suma  

    ; --- Actualizar LEDs de los contadores en PORTD ---  
    RCALL   ACTUALIZAR_DISPLAY ; Actualizar el estado visual de los LEDs  
    
    ; Regresar al inicio del bucle  
    RJMP    LOOP  

; ----------------------------------------------------------  
; Subrutinas para botones: Implementan anti-rebote y la lógica básica  

BOTON_INC_C1:                 ; Subrutina para incrementar Contador 1  
    RCALL   ANTIRREBOTE       ; Llama al procedimiento anti-rebote  
    SBIS    PINC, 0           ; Verifica si el botón sigue presionado  
    RET                       ; Si no está presionado, regresa  
    RCALL   INCREMENTAR_C1    ; Llama a la subrutina para incrementar Contador 1  
    RET  

BOTON_DEC_C1:                 ; Subrutina para decrementar Contador 1  
    RCALL   ANTIRREBOTE       ; Llama al procedimiento anti-rebote  
    SBIS    PINC, 1           ; Verifica si el botón sigue presionado  
    RET                       ; Si no está presionado, regresa  
    RCALL   DECREMENTAR_C1    ; Llama a la subrutina para decrementar Contador 1  
    RET  

BOTON_INC_C2:                 ; Subrutina para incrementar Contador 2  
    RCALL   ANTIRREBOTE       ; Llama al procedimiento anti-rebote  
    SBIS    PINC, 2           ; Verifica si el botón sigue presionado  
    RET                       ; Si no está presionado, regresa  
    RCALL   INCREMENTAR_C2    ; Llama a la subrutina para incrementar Contador 2  
    RET  

BOTON_DEC_C2:                 ; Subrutina para decrementar Contador 2  
    RCALL   ANTIRREBOTE       ; Llama al procedimiento anti-rebote  
    SBIS    PINC, 3           ; Verifica si el botón sigue presionado  
    RET                       ; Si no está presionado, regresa  
    RCALL   DECREMENTAR_C2    ; Llama a la subrutina para decrementar Contador 2  
    RET  

; ----------------------------------------------------------  
; Subrutinas para incrementar y decrementar contadores  

INCREMENTAR_C1:               ; Incrementa el valor de Contador 1  
    INC     R17               ; Incrementa el registro R17  
    ANDI    R17, 0x0F         ; Limita el valor a 4 bits (máximo 15)  
    RET  

DECREMENTAR_C1:               ; Decrementa el valor de Contador 1  
    CPI     R17, 0x00         ; Compara si el registro es 0  
    BREQ    DEC_C1_OVER       ; Si es 0, salta para reiniciarlo a 15  
    DEC     R17               ; Decrementa normalmente  
    RET  
DEC_C1_OVER:  
    LDI     R17, 0x0F         ; Reinicia Contador 1 a 15  
    RET  

INCREMENTAR_C2:               ; Incrementa el valor de Contador 2  
    INC     R18               ; Incrementa el registro R18  
    ANDI    R18, 0x0F         ; Limita el valor a 4 bits (máximo 15)  
    RET  

DECREMENTAR_C2:               ; Decrementa el valor de Contador 2  
    CPI     R18, 0x00         ; Compara si el registro es 0  
    BREQ    DEC_C2_OVER       ; Si es 0, salta para reiniciarlo a 15  
    DEC     R18               ; Decrementa normalmente  
    RET  
DEC_C2_OVER:  
    LDI     R18, 0x0F         ; Reinicia Contador 2 a 15  
    RET  

; ----------------------------------------------------------  
; Subrutina para actualizar la visualización de los LEDs  
ACTUALIZAR_DISPLAY:  
    MOV     R16, R17          ; Cargar valor de Contador 1  
    SWAP    R18               ; Intercambiar bits de Contador 2  
    OR      R16, R18          ; Combinar ambos valores  
    OUT     PORTD, R16        ; Actualizar LEDs conectados a PORTD  
    SWAP    R18               ; Restaurar Contador 2  
    RET  

; ----------------------------------------------------------  
; Subrutina para calcular y mostrar la suma  
MOSTRAR_SUMA:  
    RCALL   ANTIRREBOTE       ; Anti-rebote para el botón de suma  
    MOV     R19, R17          ; Cargar valor de Contador 1  
    ADD     R19, R18          ; Sumar Contador 2  
    MOV     R16, R19          ; Guardar resultado  
    
    ANDI    R16, 0x1F         ; Limitar la suma a 5 bits para manejar overflow  
    CPI     R19, 0x10         ; Comparar con 16 para verificar overflow  
    BRLO    NO_OVERFLOW  
    ORI     R16, 0x10         ; Activar el bit de overflow si es necesario  
NO_OVERFLOW:  
    OUT     PORTB, R16        ; Mostrar resultado en LEDs conectados a PORTB  
    RET  

; ----------------------------------------------------------  
; Subrutina de anti-rebote (20 ms @ 1 MHz)  
ANTIRREBOTE:  
    LDI     R19, 27           ; Configurar el contador externo (aprox. 20 ms)  
DELAY1:  
    LDI     R20, 250          ; Configurar el segundo contador interno  
DELAY2:  
    DEC     R20               ; Disminuir el contador interno  
    BRNE    DELAY2            ; Repetir hasta que el contador interno llegue a 0  
    DEC     R19               ; Disminuir el contador externo  
    BRNE    DELAY1            ; Repetir hasta que el contador externo llegue a 0  
    RET