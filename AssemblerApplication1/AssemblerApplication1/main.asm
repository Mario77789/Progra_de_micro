/****************************************/  
/* Contador binario de 4 bits utilizando el Timer 0  
 * Incrementa el conteo cada 100 ms sin interrupciones  
 *  
 * Autor: [Tu Nombre]  
 * Fecha: [Fecha Actual]  
 * Microcontrolador: ATmega328P  
 */  
/****************************************/  

.include "m328pdef.inc"  

/****************************************/  
// Definiciones y variables  
.cseg  
.org 0x0000                 ; Dirección de Reset (inicio del programa)  
.def    TEMP    = R16       ; Registro temporal  
.def    COUNTER = R17       ; Contador para incrementar cada 100 ms  
.def    BINARY_COUNT = R18  ; Registro para almacenar el valor del contador binario  

/****************************************/  
// Configuración del Stack  
LDI     TEMP, LOW(RAMEND)   ; Cargar valor bajo de la RAM  
OUT     SPL, TEMP           ; Configurar pila inferior  
LDI     TEMP, HIGH(RAMEND)  ; Cargar valor alto de la RAM  
OUT     SPH, TEMP           ; Configurar pila superior  

/****************************************/  
// Configuración del microcontrolador  
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

    ; Configurar PB0-PB3 como salidas para el contador  
    LDI     TEMP, 0b00001111  
    OUT     DDRB, TEMP             ; Establecer PB0-PB3 como salida  
    OUT     PORTB, BINARY_COUNT    ; Inicializar puerto PORTB en 0  

/****************************************/  
// Loop principal  
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
    OUT     PORTB, BINARY_COUNT    ; Actualizar la salida en PB0-PB3  
    
    RJMP    MAIN_LOOP              ; Repetir el ciclo  

/****************************************/