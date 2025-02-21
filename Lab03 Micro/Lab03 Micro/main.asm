;************************************************************  
; Universidad del Valle de Guatemala  
; IE2023: Programación de Microcontroladores  
;  
; Author  : Mario Fernando Cano Itzep  
; Proyecto: Laboratorio 3 - Post Lab    
;************************************************************  

// Incluir la definición del microcontrolador ATmega328P  
.include "m328Pdef.inc"  

// Configuración de la sección de código  
.cseg  
.org 0x0000  
    JMP     START  ; Salta a la etiqueta START al inicio del programa  

; Definición de direcciones de interrupción  
.org PCI1addr		  
	JMP		PCINT_ISR  ; Interrupción para cambios en las entradas del puerto C  

.org OVF0addr  
    JMP     TMR0_ISR  ; Interrupción por desbordamiento del Timer 0  

DISPLAY:   
    .DB 0x3F,0x06,0x5B,0x4F,0x66,0x6D,0x7D,0x07,0x7F,0x6F ; Codificación del display de 7 segmentos para mostrar números del 0 al 9  

; Definición de registros  
.def    cont_z = r17  ; Registro para contador de unidades  
.def    cont_2 = r21   ; Registro para contador de decenas  

START:  
; Configuración de pila  
    LDI     R16, LOW(RAMEND)    ; Cargar el valor más bajo de RAM a R16  
    OUT     SPL, R16            ; Establecer SPL  
    LDI     R16, HIGH(RAMEND)   ; Cargar el valor más alto de RAM a R16  
    OUT     SPH, R16            ; Establecer SPH  

SETUP:  
    CLI             ; Deshabilitar interrupciones para evitar problemas  

    ; Configuración del prescaler del reloj  
    LDI     R16, (1 << CLKPCE)  ; Habilita cambio de configuración de prescaler  
    STS     CLKPR, R16           ; Cambia el registro CLKPR  
    LDI     R16, 0b00000100     ; Prescaler de 8  
    STS     CLKPR, R16           ; Configura el prescaler  

    ; Configuración del Timer 0  
    LDI     R16, (1<<CS01) | (1<<CS00)  ; Configura el Timer 0 con prescaler de 64  
    OUT     TCCR0B, R16          ; Aplicar configuración al Timer 0  
    LDI     R16, 100              ; Inicializar el Timer en 100  
    OUT     TCNT0, R16            ; Cargar valor inicial al contador  

    ; Habilitar interrupción de desbordamiento del Timer 0  
    LDI     R16, (1<<TOIE0)  
    STS     TIMSK0, R16  

	; Habilitar interrupciones de cambio de estado en el puerto C  
	LDI		R16, (1 << PCIE1)	; Habilita interrupciones para PCINT[14:8]  
	STS		PCICR, R16  

	; Configuración de interrupciones para PC0 y PC1  
	LDI		R16, (1 << PCINT8) | (1 << PCINT9)  
	STS		PCMSK1, R16  

    ; Configuración de los pines del puerto C  
    CBI     DDRC, PC0        ; Configurar PC0 como entrada  
    CBI     DDRC, PC1        ; Configurar PC1 como entrada  
    SBI     DDRC, PC2        ; Configurar PC2 como salida  
    SBI     DDRC, PC3        ; Configurar PC3 como salida  
       
    ; Inicialización de los pines  
    SBI     PORTC, PC0        ; Activar resistencia pull-up en PC0  
    SBI     PORTC, PC1        ; Activar resistencia pull-up en PC1  
    CBI     PORTC, PC2        ; Salida en cero para PC2  
    CBI     PORTC, PC3        ; Salida en cero para PC3  

    ; Configuración de puertos B y D  
    LDI     R16, 0xFF  
    OUT     DDRB, R16        ; Configurar todos los pines del puerto B como salida  
    LDI     R16, 0x00  
    OUT     PORTB, R16       ; Inicializar el puerto B en cero  

    LDI     R16, 0xFF  
    OUT     DDRD, R16        ; Configurar todos los pines del puerto D como salida  
    LDI     R16, 0x00  
    OUT     PORTD, R16       ; Inicializar el puerto D en cero  

    ; Cargar el primer valor del DISPLAY en el display  
    LDI     ZL, LOW(DISPLAY*2) ; Cargar la dirección de DISPLAY  
    LDI     ZH, HIGH(DISPLAY*2)  
    LDI     XL, LOW(DISPLAY*2)  
    LDI     XH, HIGH(DISPLAY*2)  
    LPM     R16, Z           ; Leer el valor del DISPLAY en R16  
    OUT     PORTD, R16       ; Mostrar el valor en el display  

    LDI     R20, 0            ; Inicializar contador para ciclo  
	LDI		R18, 1             ; Inicializar valor de R18  
    LDI     cont_z, 0         ; Inicializar contador de unidades  
    LDI     cont_2, 0         ; Inicializar contador de decenas  

    SEI                 ; HABILITAR INTERRUPCIONES  

MAIN_LOOP:  
	CPI		R18, 0x11          ; Comparar con 17 (0x11)  
	BREQ	REINICIO1          ; Reinicia si es igual a 17  
	CPI		R18, 0x00          ; Comparar con 0  
	BREQ	REINICIO2          ; Reinicia si es igual a 0  
	DEC		R18                ; Decrementa R18  
	OUT		PORTB, R18         ; Muestra el valor en el puerto B  
	INC		R18                ; Incrementa R18  

	CALL	CARGAR_VALOR_U2    ; Llama función para cargar el valor de unidades  
	CALL	CARGAR_VALOR_D2     ; Llama función para cargar el valor de decenas  
    CPI     R20, 100          ; Comparar contador R20 con 100  
    BRNE    MAIN_LOOP         ; Repite el bucle si no es igual a 100  
    RJMP    UNIDADES          ; De saltar a la sección de unidades  

REINICIO1:  
	LDI     R18, 0x01         ; Reiniciar R18 a 1  
	RJMP	MAIN_LOOP          ; Regresar al bucle principal  

REINICIO2:  
	LDI     R18, 0x10         ; Reiniciar R18 a 16  
	RJMP	MAIN_LOOP          ; Regresar al bucle principal  


UNIDADES:  
    CLR     R20              ; Reiniciar contador en R20  
    CPI     cont_z, 9        ; Comparar cont_z con 9  
    BRNE    CONTINUAR_SUMAR  ; Si no es igual, continuar sumando  
    LDI     ZL, LOW(DISPLAY*2); Reiniciar la dirección de DISPLAY  
    LDI     ZH, HIGH(DISPLAY*2)  
    CLR     cont_z           ; Reiniciar cont_z  
    RJMP    DECENAS          ; Saltar a decenas  

CONTINUAR_SUMAR:  
    ADIW    Z, 1              ; Incrementar Z para la dirección  
    INC     cont_z            ; Incrementar el contador de unidades  

; Cargar el valor de las unidades en el display  
CARGAR_VALOR_U1:  
    CBI		PORTC, PC3        ; Apagar display de decenas  
    CBI		PORTC, PC2        ; Apagar display de unidades  
    CALL	RETARDO            ; Llamar función de retardo  
    SBI		PORTC, PC2        ; Encender display de unidades  
    LPM		R16, Z            ; Leer valor del display  
    OUT		PORTD, R16        ; Mostrar en el display de unidades  
    CALL	RETARDO            ; Mantener encendido un momento  
    RJMP    MAIN_LOOP         ; Regresar al bucle principal  

CARGAR_VALOR_U2:  
    CBI		PORTC, PC3        ; Apagar display de decenas  
    CBI		PORTC, PC2        ; Apagar display de unidades  
    CALL	RETARDO            ; Llamar función de retardo  
    SBI		PORTC, PC2        ; Encender display de unidades  
    LPM		R16, Z            ; Leer valor del display  
    OUT		PORTD, R16        ; Mostrar en el display de unidades  
    CALL	RETARDO            ; Mantener encendido un momento  
    RET                     ; Regresar de la función  

DECENAS:  
    INC     cont_2           ; Incrementar el contador de decenas  
    CPI     cont_2, 6       ; Comparar cont_2 con 6  
    BRNE    SUMA_D           ; Si no es igual, continuar sumando  
    LDI     XL, LOW(DISPLAY*2); Reiniciar la dirección de DISPLAY  
    LDI     XH, HIGH(DISPLAY*2)  
    CLR     cont_2           ; Reiniciar cont_2  
    RJMP    CARGAR_VALOR_D1  ; Llama función para cargar valor de decenas  

SUMA_D:  
    ADIW    X, 1              ; Incrementar dirección de X (decenas)  

; Cargar el valor de las decenas en el display  
CARGAR_VALOR_D1:  
    MOVW    Y, Z             ; Mover Z a Y  
    MOVW    Z, X             ; Mover X a Z  
    CBI		PORTC, PC3        ; Apagar display de decenas  
    CBI		PORTC, PC2        ; Apagar display de unidades  
    CALL	RETARDO            ; Llamar función de retardo  
    SBI		PORTC, PC3        ; Encender display de decenas  
    LPM		R16, Z            ; Leer valor del display  
    OUT		PORTD, R16        ; Mostrar en el display de decenas  
    CALL	RETARDO            ; Mantener encendido un momento  
    MOVW    Z, Y             ; Regresar Z original  
    RJMP    MAIN_LOOP         ; Regresar al bucle principal  

CARGAR_VALOR_D2:  
    MOVW    Y, Z             ; Mover Z a Y  
    MOVW    Z, X             ; Mover X a Z  
    CBI		PORTC, PC3        ; Apagar display de decenas  
    CBI		PORTC, PC2        ; Apagar display de unidades  
    CALL	RETARDO            ; Llamar función de retardo  
    SBI		PORTC, PC3        ; Encender display de decenas  
    LPM		R16, Z            ; Leer valor del display  
    OUT		PORTD, R16        ; Mostrar en el display de decenas  
    CALL	RETARDO            ; Mantener encendido un momento  
    MOVW    Z, Y             ; Regresar Z original  
    RET                     ; Regresar de la función  

RETARDO:  
    LDI     R16, 0xFF        ; Cargar 255 para el retardo  
RETARDO_LOOP:  
    DEC     R16              ; Decrementar el valor  
    BRNE    RETARDO_LOOP     ; Repetir hasta que sea cero  
    RET                     ; Regresar de la función  

; Interrupción por desbordamiento del Timer 0  
TMR0_ISR:  
    LDI     R22, 100         ; Reiniciar el contador del Timer 0  
    OUT     TCNT0, R22       ; Cargar el valor de reinicio  
    INC     R20              ; Incrementar el contador en R20  
    RETI                     ; Regreso de la interrupción  

; Interrupción por ingreso en los botones  
PCINT_ISR:  
    SBIS    PINC, PC0        ; Comprobar si el botón en PC0 está presionado  
    RJMP    BOTON1           ; Saltar a la acción del botón 1  

    SBIS    PINC, PC1        ; Comprobar si el botón en PC1 está presionado   
    RJMP    BOTON2           ; Saltar a la acción del botón 2  

    RETI                     ; Regreso de la interrupción  

BOTON1:  
	INC		R18              ; Incrementa el valor de R18 por la acción del botón 1  
	RETI                    ; Regreso de la interrupción  

BOTON2:  
	DEC		R18              ; Decrementa el valor de R18 por la acción del botón 2  
	RETI                    ; Regreso de la interrupción