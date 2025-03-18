;************************************************************      
; Universidad del Valle de Guatemala      
; IE2023: Programaci�n de Microcontroladores      
;      
; Reloj Digital con 4 displays (horas:minutos)      
; Multiplexaci�n en PC0-PC3 (cambiado de PB0-PB3)      
; Botones en PB0-PB3 (cambiado de PC0-PC2)      
; LEDs indicadores en PB4, PC4, PC5 y PB5 (alarma)      
;************************************************************      
.include "m328Pdef.inc"      ; Incluye definiciones para ATmega328P  
.cseg                        ; Inicia segmento de c�digo  
.org 0x0000                  ; Direcci�n de inicio del programa  
    
JMP START                    ; Vector de reset: Salta a inicializaci�n  
.org OVF0addr                ; Vector de interrupci�n por desbordamiento del Timer0  
    
JMP TMR0_ISR                 ; Salta a la rutina de servicio del Timer0  
.org 0x0006                  ; Vector de interrupci�n PCINT0 (para botones)  
    
JMP ISR_PCINT0               ; Salta a la rutina de servicio de interrupci�n de botones  
        
; Tabla de valores para display de 7 segmentos      
.org 0x0030                  ; Direcci�n segura para el resto del c�digo      
DISPLAY:                     ; Etiqueta para tabla de valores de display  
    
.db 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F  ; C�digos para d�gitos 0-9  

; Definici�n de registros - Asigna nombres a registros para mejor legibilidad    
.def temp = r16              ; Registro temporal para operaciones generales  
.def flags = r23             ; Registro para flags (bit 0: parpadeo, bit 1: alarma activa)      
.def temp2 = r18             ; Registro temporal adicional    
.def modo = r19              ; Registro para modo de operaci�n  
.def config_sel = r17        ; Registro para selecci�n de configuraci�n    
                             ; 0 = minutos/meses, 1 = horas/d�as    
.def resto = r22             ; Registro para almacenar restos en divisiones    
; Modos de operaci�n:  
; 0 = reloj normal     
; 1 = fecha      
; 2 = config hora      
; 3 = config fecha   
; 4 = config alarma   
   
; Variables en .dseg - Reserva espacio en memoria RAM      
.dseg                        ; Inicia segmento de datos  
cont_sec:    .byte 1         ; Contador de segundos      
cont_min_u:  .byte 1         ; Unidades de minutos      
cont_min_d:  .byte 1         ; Decenas de minutos      
cont_hr_u:   .byte 1         ; Unidades de horas      
cont_hr_d:   .byte 1         ; Decenas de horas      
contador:    .byte 1         ; Contador para timer (base de tiempo)    
led_timer:   .byte 1         ; Contador para parpadeo de LED      
dia_u:       .byte 1         ; Unidades de d�a      
dia_d:       .byte 1         ; Decenas de d�a  
mes_u:       .byte 1         ; Unidades de mes    
mes_d:       .byte 1         ; Decenas de mes   
alarm_min_u: .byte 1         ; Unidades de minutos de alarma   
alarm_min_d: .byte 1         ; Decenas de minutos de alarma   
alarm_hr_u:  .byte 1         ; Unidades de horas de alarma   
alarm_hr_d:  .byte 1         ; Decenas de horas de alarma   
alarm_active:.byte 1         ; Flag para indicar si la alarma est� sonando   
alarm_counter:.byte 1        ; Contador para duraci�n de alarma (30 segundos)   
   
.cseg                        ; Vuelve al segmento de c�digo  
    
START:                       ; Punto de entrada principal del programa  
    LDI temp, LOW(RAMEND)    ; Carga el byte bajo de la direcci�n final de RAM     
    OUT SPL, temp            ; Inicializa puntero de pila (byte bajo)  
    LDI temp, HIGH(RAMEND)   ; Carga el byte alto de la direcci�n final de RAM    
    OUT SPH, temp            ; Inicializa puntero de pila (byte alto)  
SETUP:                       ; Configuraci�n inicial del sistema  
    CLI                      ; Deshabilita interrupciones durante configuraci�n  
   
    ; Configuraci�n del prescaler del reloj      
    LDI temp, (1<<CS02)|(1<<CS00) ; Prescaler de 1024 para Timer0    
    OUT TCCR0B, temp         ; Configura el Timer0 con prescaler  
    LDI temp, 0              ; Valor inicial para timer = 0  
    OUT TCNT0, temp          ; Inicializa el contador del Timer0  
   
    ; Habilitar interrupci�n de Timer0  
    LDI temp, (1<<TOIE0)     ; Habilita interrupci�n por desbordamiento de Timer0  
    STS TIMSK0, temp         ; Guarda configuraci�n en registro TIMSK0  
   
    ; Configuraci�n de puertos      
    ; PORTB: PB0-PB3 como entradas (botones), PB4 y PB5 como salidas (LED modo hora y alarma)      
    LDI temp, (1<<PB4)|(1<<PB5) ; PB4 y PB5 como salidas      
    OUT DDRB, temp           ; Configura direcci�n de PORTB  
    LDI temp, (1<<PB0)|(1<<PB1)|(1<<PB2)|(1<<PB3) ; Pull-up en PB0-PB3 (botones)     
    OUT PORTB, temp          ; Activa resistencias pull-up internas  
   
    ; PORTC: PC0-PC3 como salidas (multiplexor), PC4-PC5 como salidas (LEDs)      
    LDI temp, (1<<PC0)|(1<<PC1)|(1<<PC2)|(1<<PC3)|(1<<PC4)|(1<<PC5)      
    OUT DDRC, temp           ; Configura PORTC como salidas  
    LDI temp, 0x00           ; Inicializar en 0 (todos apagados)  
    OUT PORTC, temp          ; Inicializa PORTC  
   
    ; PORTD: Todo como salidas (segmentos)      
    LDI temp, 0xFF           ; Todos los pines como salidas  
    OUT DDRD, temp           ; Configura PORTD para segmentos del display  
     
    ; Configuraci�n de interrupciones pin change para PORTB (botones)      
    LDI temp, (1<<PCIE0)     ; Habilitar grupo PCINT0 (PORTB)  
    STS PCICR, temp          ; Configura interrupci�n de cambio de pin  
    LDI temp, (1<<PCINT0)|(1<<PCINT1)|(1<<PCINT2)|(1<<PCINT3) ; Habilita pines espec�ficos  
    STS PCMSK0, temp         ; Configura m�scara para PCINT0-3 (PB0-PB3)  

    ; Inicializaci�n de variables - Establece valores iniciales     
    LDI temp, 0              ; Valor inicial = 0  
    STS cont_sec, temp       ; Inicializa segundos  
    STS cont_min_u, temp     ; Inicializa unidades de minutos    
    STS cont_min_d, temp     ; Inicializa decenas de minutos     
    STS cont_hr_u, temp      ; Inicializa unidades de horas  
    STS cont_hr_d, temp      ; Inicializa decenas de horas  
    STS contador, temp       ; Inicializa contador de timer  
    STS led_timer, temp      ; Inicializa temporizador de LED  
    STS alarm_active, temp   ; Inicializa estado de alarma (inactiva)  
    STS alarm_counter, temp  ; Inicializa contador de alarma  
   
    ; Inicializar fecha (01/01) - Fecha predeterminada    
    LDI temp, 1              ; Valor = 1  
    STS dia_u, temp          ; Unidades de d�a = 1  
    LDI temp, 0              ; Valor = 0  
    STS dia_d, temp          ; Decenas de d�a = 0 (d�a 01)  
    LDI temp, 1              ; Valor = 1  
    STS mes_u, temp          ; Unidades de mes = 1  
    LDI temp, 0              ; Valor = 0  
    STS mes_d, temp          ; Decenas de mes = 0 (mes 01)  
    
    ; Inicializar alarma (12:12) - Alarma predeterminada  
    LDI temp, 2              ; Valor = 2  
    STS alarm_hr_u, temp     ; Unidades de hora de alarma = 2  
    STS alarm_min_u, temp    ; Unidades de minuto de alarma = 2  
    LDI temp, 1              ; Valor = 1  
    STS alarm_hr_d, temp     ; Decenas de hora de alarma = 1 (hora 12)  
    STS alarm_min_d, temp    ; Decenas de minuto de alarma = 1 (minuto 12)  
     
    CLR flags                ; Limpia registro de flags  
    CLR modo                 ; Inicializa en modo 0 (reloj)  
    
    ; Inicializar config_sel en 1 (por defecto configurando horas/d�as)    
    LDI temp, 1              ; Valor = 1 (configura horas/d�as)  
    MOV config_sel, temp     ; Inicializa selector de configuraci�n  
   
    ; Inicializar LEDs indicadores de modo  
    SBI PORTB, PB4           ; Enciende LED de modo hora (PB4)  
    CBI PORTC, PC4           ; Apaga LED de modo fecha (PC4)  
    CBI PORTC, PC5           ; Apaga LED de modo configuraci�n (PC5)  
    CBI PORTB, PB5           ; Apaga LED de alarma (PB5)  
   
    SEI                      ; Habilita interrupciones globales  
MAIN_LOOP:                   ; Bucle principal del programa  
    CALL MOSTRAR_DISPLAYS    ; Actualiza los displays seg�n el modo actual  
    RJMP MAIN_LOOP           ; Bucle infinito  
   
ACTUALIZAR_LEDS_MODO:        ; Actualiza LEDs seg�n el modo actual  
    PUSH temp                ; Guarda registro temporal en pila  
    PUSH temp2               ; Guarda segundo registro temporal  
    ; Apagar todos los LEDs primero   
    CBI PORTB, PB4           ; Apaga LED en PB4 (modo hora)  
    CBI PORTC, PC4           ; Apaga LED en PC4 (modo fecha)  
    CBI PORTC, PC5           ; Apaga LED en PC5 (configuraci�n)  
   
    CPI modo, 0              ; Compara modo con 0  
    BRNE CHECK_MODO_1        ; Si no es igual, verifica el siguiente modo  
    SBI PORTB, PB4           ; Modo 0: Enciende LED de hora (PB4)  
    RJMP SET_LEDS            ; Salta a fin de la funci�n  
   
CHECK_MODO_1:                ; Verificaci�n para modo 1  
    CPI modo, 1              ; Compara modo con 1  
    BRNE CHECK_MODO_2        ; Si no es igual, verifica el siguiente modo  
    SBI PORTC, PC4           ; Modo 1: Enciende LED de fecha (PC4)  
    RJMP SET_LEDS            ; Salta a fin de la funci�n  
   
CHECK_MODO_2:                ; Verificaci�n para modo 2  
    CPI modo, 2              ; Compara modo con 2  
    BRNE CHECK_MODO_3        ; Si no es igual, verifica el siguiente modo  
    SBI PORTB, PB4           ; Modo 2: Enciende LED hora (parpadea en TMR0_ISR)  
    SBI PORTC, PC5           ; Enciende LED configuraci�n (fijo)  
    RJMP SET_LEDS            ; Salta a fin de la funci�n  
   
CHECK_MODO_3:                ; Verificaci�n para modo 3  
    CPI modo, 3              ; Compara modo con 3  
    BRNE CHECK_MODO_4        ; Si no es igual, verifica el siguiente modo  
    SBI PORTC, PC4           ; Modo 3: Enciende LED fecha (parpadea en TMR0_ISR)  
    SBI PORTC, PC5           ; Enciende LED configuraci�n (fijo)  
    RJMP SET_LEDS            ; Salta a fin de la funci�n  

CHECK_MODO_4:                ; Verificaci�n para modo 4  
    CPI modo, 4              ; Compara modo con 4  
    BRNE SET_LEDS            ; Si no es igual, termina funci�n  
    SBI PORTB, PB4           ; Modo 4: Enciende LED hora (parpadea en TMR0_ISR)  
    ; PC5 se mantiene apagado  
   
SET_LEDS:                    ; Fin de la funci�n  
    POP temp2                ; Recupera registro temp2 de la pila  
    POP temp                 ; Recupera registro temp de la pila  
    RET                      ; Retorno de la funci�n  
   
MOSTRAR_DISPLAYS:            ; Funci�n para mostrar displays seg�n el modo  
    CPI modo, 1              ; Verifica si estamos en modo 1 (fecha)  
    BRNE CHECK_MODO_2_DISPLAY ; Si no, verifica siguiente modo  
    JMP MOSTRAR_FECHA        ; Salta a mostrar fecha (JMP por lejan�a)  
   
CHECK_MODO_2_DISPLAY:        ; Verificaci�n para modo 2  
    CPI modo, 2              ; Verifica si estamos en modo 2 (config hora)  
    BRNE CHECK_MODO_3_DISPLAY ; Si no, verifica siguiente modo  
    JMP MOSTRAR_CONFIG_HORA  ; Salta a mostrar configuraci�n de hora  
   
CHECK_MODO_3_DISPLAY:        ; Verificaci�n para modo 3  
    CPI modo, 3              ; Verifica si estamos en modo 3 (config fecha)  
    BRNE CHECK_MODO_4_DISPLAY ; Si no, verifica siguiente modo  
    JMP MOSTRAR_CONFIG_FECHA ; Salta a mostrar configuraci�n de fecha  

CHECK_MODO_4_DISPLAY:        ; Verificaci�n para modo 4  
    CPI modo, 4              ; Verifica si estamos en modo 4 (config alarma)  
    BRNE MOSTRAR_RELOJ       ; Si no, muestra reloj (modo por defecto)  
    JMP MOSTRAR_CONFIG_ALARMA ; Salta a mostrar configuraci�n de alarma  
   
MOSTRAR_RELOJ:               ; Funci�n para mostrar la hora actual  
    ; Display 4 (PC3) - Decenas de horas     
    CALL APAGAR_DISPLAYS     ; Apaga todos los displays para multiplexaci�n  
   
    LDI ZL, LOW(DISPLAY*2)   ; Carga direcci�n baja de tabla DISPLAY (x2 por flash)  
    LDI ZH, HIGH(DISPLAY*2)  ; Carga direcci�n alta de tabla DISPLAY  
    LDS temp, cont_hr_d      ; Carga valor de decenas de hora  
    ADD ZL, temp             ; Suma offset para acceder al d�gito correcto  
    LPM temp, Z              ; Carga patr�n del d�gito desde memoria de programa  
    OUT PORTD, temp          ; Muestra el patr�n en PORTD (segmentos)  
    SBI PORTC, PC3           ; Activa display 4  
    CALL RETARDO             ; Peque�o retardo para visualizaci�n  
     
    ; Display 3 (PC2) - Unidades de horas     
    CALL APAGAR_DISPLAYS     ; Apaga displays para mostrar siguiente d�gito  
   
    LDI ZL, LOW(DISPLAY*2)   ; Prepara puntero a tabla de display  
    LDI ZH, HIGH(DISPLAY*2)   
    LDS temp, cont_hr_u      ; Carga unidades de hora  
    ADD ZL, temp             ; Calcula direcci�n en tabla  
    LPM temp, Z              ; Carga patr�n del d�gito  
    SBRC flags, 0            ; Si bit 0 de flags est� a 0, salta siguiente instrucci�n  
    ORI temp, 0x80           ; Agrega punto decimal (separador horas:minutos)  
    OUT PORTD, temp          ; Muestra patr�n en segmentos  
    SBI PORTC, PC2           ; Activa display 3  
    CALL RETARDO             ; Retardo para visualizaci�n  
     
    ; Display 2 (PC1) - Decenas de minutos  
    CALL APAGAR_DISPLAYS     ; Apaga displays  
   
    LDI ZL, LOW(DISPLAY*2)   ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, cont_min_d     ; Carga decenas de minutos  
    ADD ZL, temp             ; Calcula direcci�n en tabla  
    LPM temp, Z              ; Carga patr�n del d�gito  
    SBRC flags, 0            ; Si bit 0 de flags est� a 0, salta  
    ORI temp, 0x80           ; Agrega punto decimal (parpadea con segundos)  
    OUT PORTD, temp          ; Muestra patr�n  
    SBI PORTC, PC1           ; Activa display 2  
    CALL RETARDO             ; Retardo  
     
    ; Display 1 (PC0) - Unidades de minutos     
    CALL APAGAR_DISPLAYS     ; Apaga displays  
   
    LDI ZL, LOW(DISPLAY*2)   ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)   
    LDS temp, cont_min_u     ; Carga unidades de minutos  
    ADD ZL, temp             ; Calcula direcci�n  
    LPM temp, Z              ; Carga patr�n  
    OUT PORTD, temp          ; Muestra d�gito  
    SBI PORTC, PC0           ; Activa display 1  
    CALL RETARDO             ; Retardo  
    RET                      ; Retorno de funci�n  

MOSTRAR_FECHA:               ; Funci�n para mostrar la fecha actual  
    ; Display 4 (PC3) - Decenas de d�a     
    CALL APAGAR_DISPLAYS     ; Apaga displays  
   
    LDI ZL, LOW(DISPLAY*2)   ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, dia_d          ; Carga decenas de d�a  
    ADD ZL, temp             ; Calcula direcci�n  
    LPM temp, Z              ; Carga patr�n  
    OUT PORTD, temp          ; Muestra d�gito  
    SBI PORTC, PC3           ; Activa display 4  
    CALL RETARDO             ; Retardo  
     
    ; Display 3 (PC2) - Unidades de d�a     
    CALL APAGAR_DISPLAYS     ; Apaga displays  
     
    LDI ZL, LOW(DISPLAY*2)   ; Prepara puntero  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, dia_u          ; Carga unidades de d�a  
    ADD ZL, temp             ; Calcula direcci�n  
    LPM temp, Z              ; Carga patr�n  
    ORI temp, 0x80           ; Agrega punto decimal (separador d�a/mes)  
    OUT PORTD, temp          ; Muestra d�gito  
    SBI PORTC, PC2           ; Activa display 3  
    CALL RETARDO             ; Retardo  

    ; Display 2 (PC1) - Decenas de mes    
    CALL APAGAR_DISPLAYS     ; Apaga displays  
     
    LDI ZL, LOW(DISPLAY*2)   ; Prepara puntero  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, mes_d          ; Carga decenas de mes  
    ADD ZL, temp             ; Calcula direcci�n  
    LPM temp, Z              ; Carga patr�n  
    OUT PORTD, temp          ; Muestra d�gito  
    SBI PORTC, PC1           ; Activa display 2  
    CALL RETARDO             ; Retardo  
     
    ; Display 1 (PC0) - Unidades de mes   
    CALL APAGAR_DISPLAYS     ; Apaga displays  
     
    LDI ZL, LOW(DISPLAY*2)   ; Prepara puntero  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, mes_u          ; Carga unidades de mes  
    ADD ZL, temp             ; Calcula direcci�n  
    LPM temp, Z              ; Carga patr�n  
    OUT PORTD, temp          ; Muestra d�gito  
    SBI PORTC, PC0           ; Activa display 1  
    CALL RETARDO             ; Retardo  
    RET                      ; Retorno de funci�n  
   
MOSTRAR_CONFIG_HORA:         ; Funci�n para mostrar configuraci�n de hora con parpadeo  
    ; Display 4 (PC3) - Decenas de horas     
    CALL APAGAR_DISPLAYS     ; Apaga displays  
   
    LDI ZL, LOW(DISPLAY*2)   ; Prepara puntero  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, cont_hr_d      ; Carga decenas de hora  
    ADD ZL, temp             ; Calcula direcci�n  
    LPM temp, Z              ; Carga patr�n  
    
    ; Si config_sel = 1 (configurando horas) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 1        ; Compara selector con 1 (configurando horas)  
    BRNE NO_BLINK_HR_D       ; Si no configura horas, no parpadea  
    SBRC flags, 0            ; Si bit de parpadeo est� a 0, salta  
    CLR temp                 ; Apaga segmento para efecto de parpadeo    
NO_BLINK_HR_D:               ; Etiqueta de salto si no parpadea  
    OUT PORTD, temp          ; Muestra patr�n (normal o apagado)  
    SBI PORTC, PC3           ; Activa display 4  
    CALL RETARDO             ; Retardo  
     
    ; Display 3 (PC2) - Unidades de horas   
    CALL APAGAR_DISPLAYS     ; Apaga displays  
     
    LDI ZL, LOW(DISPLAY*2)   ; Prepara puntero  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, cont_hr_u      ; Carga unidades de hora  
    ADD ZL, temp             ; Calcula direcci�n  
    LPM temp, Z              ; Carga patr�n  
     
    ; Si config_sel = 1 (configurando horas) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 1        ; Compara selector  
    BRNE ADD_DOT_HR          ; Si no configura horas, agrega punto sin parpadeo  
    SBRC flags, 0            ; Si bit de parpadeo est� a 0, salta  
    CLR temp                 ; Apaga segmento para parpadeo  
ADD_DOT_HR:                  ; Etiqueta para agregar punto decimal  
     
    ; A�adir punto decimal siempre     
    ORI temp, 0x80           ; Agrega punto (separador horas:minutos)  
    OUT PORTD, temp          ; Muestra patr�n  
    SBI PORTC, PC2           ; Activa display 3  
    CALL RETARDO             ; Retardo       
    ; Display 2 (PC1) - Decenas de minutos     
    CALL APAGAR_DISPLAYS     
     
    LDI ZL, LOW(DISPLAY*2)     
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, cont_min_d     
    ADD ZL, temp     
    LPM temp, Z    
    
    ; Si config_sel = 0 (configurando minutos) y bit de parpadeo activado, apagar segmento  
    CPI config_sel, 0    
    BRNE NO_BLINK_MIN_D    
    SBRC flags, 0    
    CLR temp ; Apagar segmento para efecto de parpadeo    

NO_BLINK_MIN_D:                ; Etiqueta para saltar si no se aplica parpadeo a decenas de minutos  
    OUT PORTD, temp            ; Saca el patr�n del d�gito a los segmentos del display  
    SBI PORTC, PC1             ; Activa el display 2 (PC1)  
    CALL RETARDO               ; Peque�a pausa para visualizaci�n  
     
    ; Display 1 (PC0) - Unidades de minutos     
    CALL APAGAR_DISPLAYS       ; Apaga todos los displays para multiplexaci�n  
     
    LDI ZL, LOW(DISPLAY*2)     ; Carga direcci�n baja de tabla de d�gitos  
    LDI ZH, HIGH(DISPLAY*2)    ; Carga direcci�n alta de tabla  
    LDS temp, cont_min_u       ; Carga valor de unidades de minutos  
    ADD ZL, temp               ; Calcula direcci�n del d�gito en tabla  
    LPM temp, Z                ; Carga patr�n del d�gito de memoria de programa  
    
    ; Si config_sel = 0 (configurando minutos) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 0          ; Compara selector con 0 (configurando minutos)  
    BRNE NO_BLINK_MIN_U        ; Si no estamos configurando minutos, salta  
    SBRC flags, 0              ; Si bit de parpadeo est� a 0, salta  
    CLR temp                   ; Apaga todos los segmentos para efecto de parpadeo  
NO_BLINK_MIN_U:                ; Etiqueta para saltar si no se aplica parpadeo  
    OUT PORTD, temp            ; Muestra el d�gito en los segmentos  
    SBI PORTC, PC0             ; Activa el display 1 (PC0)  
    CALL RETARDO               ; Peque�a pausa para visualizaci�n  
    RET                        ; Retorno de la funci�n  
   
MOSTRAR_CONFIG_FECHA:          ; Funci�n para mostrar y configurar fecha  
    ; Display 4 (PC3) - Decenas de d�a     
    CALL APAGAR_DISPLAYS       ; Apaga todos los displays  
     
    LDI ZL, LOW(DISPLAY*2)     ; Prepara puntero a tabla de d�gitos  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, dia_d            ; Carga decenas de d�a  
    ADD ZL, temp               ; Calcula direcci�n en tabla  
    LPM temp, Z                ; Carga patr�n del d�gito  
    
    ; Si config_sel = 1 (configurando d�as) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 1          ; Compara selector con 1 (configurando d�as)  
    BRNE NO_BLINK_DIA_D        ; Si no estamos configurando d�as, salta  
    SBRC flags, 0              ; Si bit de parpadeo est� a 0, salta  
    CLR temp                   ; Apaga segmentos para efecto de parpadeo  
NO_BLINK_DIA_D:                ; Etiqueta para saltar si no se aplica parpadeo  
    OUT PORTD, temp            ; Muestra el d�gito  
    SBI PORTC, PC3             ; Activa display 4  
    CALL RETARDO               ; Peque�a pausa  
     
    ; Display 3 (PC2) - Unidades de d�a     
    CALL APAGAR_DISPLAYS       ; Apaga todos los displays  
    LDI ZL, LOW(DISPLAY*2)     ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, dia_u            ; Carga unidades de d�a  
    ADD ZL, temp               ; Calcula direcci�n  
    LPM temp, Z                ; Carga patr�n  
    
    ; Si config_sel = 1 (configurando d�as) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 1          ; Compara selector con 1 (configurando d�as)  
    BRNE ADD_DOT_DIA           ; Si no configuramos d�as, salta a a�adir punto  
    SBRC flags, 0              ; Si bit de parpadeo est� a 0, salta  
    LDI temp, 0x80             ; Carga SOLO punto decimal (parpadea d�gito pero no el punto)  
ADD_DOT_DIA:                   ; Etiqueta para a�adir punto decimal  
    
    ; A�adir punto decimal siempre    
    ORI temp, 0x80             ; A�ade punto decimal (separador d�a/mes)  
    OUT PORTD, temp            ; Muestra d�gito con punto  
    SBI PORTC, PC2             ; Activa display 3  
    CALL RETARDO               ; Peque�a pausa  
     
    ; Display 2 (PC1) - Decenas de mes     
    CALL APAGAR_DISPLAYS       ; Apaga todos los displays  
     
    LDI ZL, LOW(DISPLAY*2)     ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, mes_d            ; Carga decenas de mes  
    ADD ZL, temp               ; Calcula direcci�n  
    LPM temp, Z                ; Carga patr�n  
    
    ; Si config_sel = 0 (configurando meses) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 0          ; Compara selector con 0 (configurando meses)  
    BRNE NO_BLINK_MES_D        ; Si no configuramos meses, salta  
    SBRC flags, 0              ; Si bit de parpadeo est� a 0, salta  
    CLR temp                   ; Apaga segmentos para efecto de parpadeo  
NO_BLINK_MES_D:                ; Etiqueta para saltar si no se aplica parpadeo  
    OUT PORTD, temp            ; Muestra d�gito  
    SBI PORTC, PC1             ; Activa display 2  
    CALL RETARDO               ; Peque�a pausa  
     
    ; Display 1 (PC0) - Unidades de mes     
    CALL APAGAR_DISPLAYS       ; Apaga todos los displays  
     
    LDI ZL, LOW(DISPLAY*2)     ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, mes_u            ; Carga unidades de mes  
    ADD ZL, temp               ; Calcula direcci�n  
    LPM temp, Z                ; Carga patr�n  
    
    ; Si config_sel = 0 (configurando meses) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 0          ; Compara selector con 0 (configurando meses)  
    BRNE NO_BLINK_MES_U        ; Si no configuramos meses, salta  
    SBRC flags, 0              ; Si bit de parpadeo est� a 0, salta  
    CLR temp                   ; Apaga segmentos para efecto de parpadeo  
NO_BLINK_MES_U:                ; Etiqueta para saltar si no se aplica parpadeo  
    OUT PORTD, temp            ; Muestra d�gito  
    SBI PORTC, PC0             ; Activa display 1  
    CALL RETARDO               ; Peque�a pausa  
    RET                        ; Retorno de la funci�n  

; Funci�n para mostrar la configuraci�n de alarma  
MOSTRAR_CONFIG_ALARMA:         ; Funci�n para configurar la alarma  
    ; Display 4 (PC3) - Decenas de horas de alarma     
    CALL APAGAR_DISPLAYS       ; Apaga todos los displays  
    LDI ZL, LOW(DISPLAY*2)     ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, alarm_hr_d       ; Carga decenas de horas de alarma  
    ADD ZL, temp               ; Calcula direcci�n  
    LPM temp, Z                ; Carga patr�n  
    
    ; Si config_sel = 1 (configurando horas) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 1          ; Compara selector con 1 (configurando horas)  
    BRNE NO_BLINK_ALARM_HR_D   ; Si no configuramos horas, salta  
    SBRC flags, 0              ; Si bit de parpadeo est� a 0, salta  
    CLR temp                   ; Apaga segmentos para efecto de parpadeo  
NO_BLINK_ALARM_HR_D:           ; Etiqueta para saltar si no se aplica parpadeo  
    OUT PORTD, temp            ; Muestra d�gito  
    SBI PORTC, PC3             ; Activa display 4  
    CALL RETARDO               ; Peque�a pausa  
     
    ; Display 3 (PC2) - Unidades de horas de alarma   
    CALL APAGAR_DISPLAYS       ; Apaga todos los displays  
     
    LDI ZL, LOW(DISPLAY*2)     ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, alarm_hr_u       ; Carga unidades de horas de alarma  
    ADD ZL, temp               ; Calcula direcci�n  
    LPM temp, Z                ; Carga patr�n  
     
    ; Si config_sel = 1 (configurando horas) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 1          ; Compara selector con 1 (configurando horas)  
    BRNE ADD_DOT_ALARM_HR      ; Si no configuramos horas, salta a a�adir punto  
    SBRC flags, 0              ; Si bit de parpadeo est� a 0, salta  
    CLR temp                   ; Apaga segmentos para efecto de parpadeo  
ADD_DOT_ALARM_HR:              ; Etiqueta para a�adir punto decimal  
    
    ; A�adir punto decimal siempre    
    ORI temp, 0x80             ; A�ade punto decimal (separador horas:minutos)  
    OUT PORTD, temp            ; Muestra d�gito con punto  
    SBI PORTC, PC2             ; Activa display 3  
    CALL RETARDO               ; Peque�a pausa  
     
    ; Display 2 (PC1) - Decenas de minutos de alarma     
    CALL APAGAR_DISPLAYS       ; Apaga todos los displays  
     
    LDI ZL, LOW(DISPLAY*2)     ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, alarm_min_d      ; Carga decenas de minutos de alarma  
    ADD ZL, temp               ; Calcula direcci�n  
    LPM temp, Z                ; Carga patr�n  
    
    ; Si config_sel = 0 (configurando minutos) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 0          ; Compara selector con 0 (configurando minutos)  
    BRNE NO_BLINK_ALARM_MIN_D  ; Si no configuramos minutos, salta  
    SBRC flags, 0              ; Si bit de parpadeo est� a 0, salta  
    CLR temp                   ; Apaga segmentos para efecto de parpadeo  
NO_BLINK_ALARM_MIN_D:          ; Etiqueta para saltar si no se aplica parpadeo  
    OUT PORTD, temp            ; Muestra d�gito  
    SBI PORTC, PC1             ; Activa display 2  
    CALL RETARDO               ; Peque�a pausa  
     
    ; Display 1 (PC0) - Unidades de minutos de alarma     
    CALL APAGAR_DISPLAYS       ; Apaga todos los displays  
     
    LDI ZL, LOW(DISPLAY*2)     ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, alarm_min_u      ; Carga unidades de minutos de alarma  
    ADD ZL, temp               ; Calcula direcci�n  
    LPM temp, Z                ; Carga patr�n  
    
    ; Si config_sel = 0 (configurando minutos) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 0          ; Compara selector con 0 (configurando minutos)  
    BRNE NO_BLINK_ALARM_MIN_U  ; Si no configuramos minutos, salta  
    SBRC flags, 0              ; Si bit de parpadeo est� a 0, salta  
    CLR temp                   ; Apaga segmentos para efecto de parpadeo  
NO_BLINK_ALARM_MIN_U:          ; Etiqueta para saltar si no se aplica parpadeo  
    OUT PORTD, temp            ; Muestra d�gito  
    SBI PORTC, PC0             ; Activa display 1  
    CALL RETARDO               ; Peque�a pausa  
    RET                        ; Retorno de la funci�n  
   
APAGAR_DISPLAYS:               ; Funci�n para apagar todos los displays (multiplexaci�n)  
    CBI PORTC, PC0             ; Apaga display 1  
    CBI PORTC, PC1             ; Apaga display 2  
    CBI PORTC, PC2             ; Apaga display 3  
    CBI PORTC, PC3             ; Apaga display 4  
    RET                        ; Retorno de la funci�n  
   
RETARDO:                       ; Funci�n de retardo para multiplexaci�n  
    PUSH r17                   ; Guarda r17 en la pila  
    LDI r17, 10                ; Carga valor inicial para retardo  
LOOP_RETARDO:                  ; Bucle de retardo  
    DEC r17                    ; Decrementa contador  
    BRNE LOOP_RETARDO          ; Si no es cero, contin�a el bucle  
    POP r17                    ; Recupera r17 de la pila  
    RET                        ; Retorno de la funci�n  
   
; Funci�n corregida para incrementar el tiempo correctamente     
INCREMENTAR_TIEMPO:            ; Funci�n para avanzar el tiempo (cada segundo)  
    ; Incrementar segundos (no se muestran)     
    LDS temp, cont_sec         ; Carga contador de segundos  
    INC temp                   ; Incrementa segundos  
    CPI temp, 60               ; Compara si lleg� a 60  
    BRNE GUARDAR_SEC           ; Si no es 60, guarda y termina  
   
    ; Si segundos llega a 60, reiniciar y incrementar minutos     
    LDI temp, 0                ; Reinicia segundos a 0  
    STS cont_sec, temp         ; Guarda valor  
   
    ; Incrementar unidades de minutos     
    LDS temp, cont_min_u       ; Carga unidades de minutos  
    INC temp                   ; Incrementa  
    CPI temp, 10               ; Compara si lleg� a 10  
    BRNE GUARDAR_MIN_U         ; Si no es 10, guarda y termina  
   
    ; Si unidades de minutos llega a 10, reiniciar e incrementar decenas     
    LDI temp, 0                ; Reinicia unidades de minutos a 0  
    STS cont_min_u, temp       ; Guarda valor  
   
    ; Incrementar decenas de minutos   
    LDS temp, cont_min_d       ; Carga decenas de minutos  
    INC temp                   ; Incrementa  
    CPI temp, 6                ; Compara si lleg� a 6 (60 minutos)  
    BRNE GUARDAR_MIN_D         ; Si no es 6, guarda y termina  
    ; Si decenas de minutos llega a 6, reiniciar e incrementar horas     
    LDI temp, 0                ; Reinicia decenas de minutos a 0  
    STS cont_min_d, temp       ; Guarda valor  
   
    ; Incrementar unidades de horas     
    LDS temp, cont_hr_u        ; Carga unidades de horas  
    INC temp                   ; Incrementa  
   
    ; Verificar si estamos en 24 horas (23:59 -> 00:00)    
    LDS temp2, cont_hr_d       ; Carga decenas de horas  
    CPI temp2, 2               ; Compara si decenas es 2  
    BRNE CHECK_HR_U_NORMAL     ; Si no es 2, verificaci�n normal  
    CPI temp, 4                ; Compara si unidades lleg� a 4 (24 horas)  
    BRNE CHECK_HR_U_NORMAL     ; Si no es 4, verificaci�n normal  
   
    ; Si llegamos a 24 horas, reiniciar a 00:00 e incrementar d�a     
    LDI temp, 0                ; Reinicia unidades de horas a 0  
    STS cont_hr_u, temp        ; Guarda valor  
    LDI temp, 0                ; Reinicia decenas de horas a 0  
    STS cont_hr_d, temp        ; Guarda valor  
   
    ; Incrementar d�a - ASEGURARNOS DE QUE ESTO SE EJECUTE     
    PUSH temp                  ; Guarda registros en pila para preservar valores  
    PUSH temp2     
    CALL INCREMENTAR_DIA_AUTOMATICO ; Llama a subrutina para incrementar d�a  
    POP temp2                  ; Recupera registros de pila  
    POP temp     
    RET                        ; Retorno de la funci�n  
   
CHECK_HR_U_NORMAL:             ; Verificaci�n normal de horas  
    ; Verificar si unidades de hora llega a 10     
    CPI temp, 10               ; Compara si unidades de hora lleg� a 10  
    BRNE GUARDAR_HR_U          ; Si no es 10, guarda y termina  
   
    ; Si unidades de hora llega a 10, reiniciar e incrementar decenas     
    LDI temp, 0                ; Reinicia unidades de hora a 0  
    STS cont_hr_u, temp        ; Guarda valor  
   
    ; Incrementar decenas de horas     
    LDS temp, cont_hr_d        ; Carga decenas de horas  
    INC temp                   ; Incrementa  
    STS cont_hr_d, temp        ; Guarda valor  
    RET                        ; Retorno de la funci�n  
   
GUARDAR_HR_U:                  ; Rutina para guardar unidades de hora  
    STS cont_hr_u, temp        ; Guarda valor en memoria  
    RET                        ; Retorno de la funci�n  
   
GUARDAR_MIN_D:                 ; Rutina para guardar decenas de minutos  
    STS cont_min_d, temp       ; Guarda valor en memoria  
    RET                        ; Retorno de la funci�n  
  
GUARDAR_MIN_U:                 ; Rutina para guardar unidades de minutos  
    STS cont_min_u, temp       ; Guarda valor en memoria  
    RET                        ; Retorno de la funci�n  
   
GUARDAR_SEC:                   ; Rutina para guardar segundos  
    STS cont_sec, temp         ; Guarda valor en memoria  
    RET                        ; Retorno de la funci�n  
    
; Funci�n para incrementar horas (para bot�n PB1 en modo incremento)     
INCREMENTAR_HORAS:             ; Funci�n para incrementar horas manualmente  
    ; Incrementar unidades de horas     
    LDS temp, cont_hr_u        ; Carga unidades de horas  
    INC temp                   ; Incrementa  
   
    ; Verificar si estamos en 24 horas (23:59 -> 00:00)     
    LDS temp2, cont_hr_d       ; Carga decenas de horas  
    CPI temp2, 2               ; Compara si decenas es 2  
    BRNE INC_HR_CHECK_U        ; Si no es 2, verificaci�n normal  
    CPI temp, 4                ; Compara si unidades lleg� a 4 (24 horas)  
    BRNE INC_HR_CHECK_U        ; Si no es 4, verificaci�n normal  
   
    ; Si llegamos a 24 horas, reiniciar a 00:00     
    LDI temp, 0                ; Reinicia unidades de horas a 0  
    STS cont_hr_u, temp        ; Guarda valor  
    LDI temp, 0                ; Reinicia decenas de horas a 0  
    STS cont_hr_d, temp        ; Guarda valor  
    RET                        ; Retorno de la funci�n  
   
INC_HR_CHECK_U:                ; Verificaci�n normal de unidades de hora  
    ; Verificar si unidades de hora llega a 10     
    CPI temp, 10               ; Compara si unidades lleg� a 10  
    BRNE INC_HR_SAVE_U         ; Si no es 10, guarda y termina  
   
    ; Si unidades de hora llega a 10, reiniciar e incrementar decenas     
    LDI temp, 0                ; Reinicia unidades a 0  
    STS cont_hr_u, temp        ; Guarda valor  
   
    ; Incrementar decenas de horas     
    LDS temp, cont_hr_d        ; Carga decenas de horas  
    INC temp                   ; Incrementa  
    STS cont_hr_d, temp        ; Guarda valor  
    RET                        ; Retorno de la funci�n  
INC_HR_SAVE_U:                ; Etiqueta para guardar unidades de hora incrementadas  
    STS cont_hr_u, temp       ; Guarda el valor en la variable de unidades de hora  
    RET                       ; Retorno de la funci�n  
    
; FUNCI�N CORREGIDA: Decrementar horas (para bot�n PB2 en modo decremento)    
DECREMENTAR_HORAS:            ; Funci�n para decrementar horas manualmente  
    ; Verificar si estamos en 00:xx    
    LDS temp, cont_hr_d       ; Carga decenas de horas  
    CPI temp, 0               ; Compara si es 0  
    BRNE DEC_HR_NOT_ZERO_D    ; Si no es 0, salta al manejo de decenas no cero  
      
    LDS temp, cont_hr_u       ; Carga unidades de horas  
    CPI temp, 0               ; Compara si es 0  
    BRNE DEC_HR_NOT_ZERO_U    ; Si no es 0, salta al manejo de unidades no cero  
      
    ; Si llegamos a 00 horas, cambiar a 23:00 (underflow)    
    LDI temp, 3               ; Carga 3 para unidades  
    STS cont_hr_u, temp       ; Guarda unidades = 3  
    LDI temp, 2               ; Carga 2 para decenas  
    STS cont_hr_d, temp       ; Guarda decenas = 2 (hora 23)  
    RET                       ; Retorno de la funci�n  
      
DEC_HR_NOT_ZERO_U:            ; Etiqueta para decrementar unidades de hora no cero  
    ; Decrementar unidades de hora    
    DEC temp                  ; Decrementa unidades  
    STS cont_hr_u, temp       ; Guarda el nuevo valor  
    RET                       ; Retorno de la funci�n  

DEC_HR_NOT_ZERO_D:            ; Etiqueta para decrementar con decenas no cero  
    ; Si decenas > 0, verificar si unidades es 0    
    LDS temp, cont_hr_u       ; Carga unidades de horas  
    CPI temp, 0               ; Compara si es 0  
    BRNE DEC_HR_NOT_ZERO_U    ; Si no es 0, decrementa normalmente  
      
    ; Si unidades = 0, poner unidades en 9 y decrementar decenas    
    LDI temp, 9               ; Carga 9 para unidades  
    STS cont_hr_u, temp       ; Guarda unidades = 9  
    LDS temp, cont_hr_d       ; Carga decenas de horas  
    DEC temp                  ; Decrementa decenas  
    STS cont_hr_d, temp       ; Guarda el nuevo valor de decenas  
    RET                       ; Retorno de la funci�n  
    
; Funci�n para incrementar minutos (para bot�n PB1 en modo incremento)     
INCREMENTAR_MINUTOS:          ; Funci�n para incrementar minutos manualmente  
    ; Incrementar unidades de minutos     
    LDS temp, cont_min_u      ; Carga unidades de minutos  
    INC temp                  ; Incrementa unidades  
    CPI temp, 10              ; Compara si lleg� a 10  
    BRNE INC_MIN_SAVE_U       ; Si no es 10, guarda y termina  
    
    ; Si unidades de minutos llega a 10, reiniciar e incrementar decenas     
    LDI temp, 0               ; Reinicia unidades a 0  
    STS cont_min_u, temp      ; Guarda el valor  
   
    ; Incrementar decenas de minutos     
    LDS temp, cont_min_d      ; Carga decenas de minutos  
    INC temp                  ; Incrementa decenas  
    CPI temp, 6               ; Compara si lleg� a 6 (60 minutos)  
    BRNE INC_MIN_SAVE_D       ; Si no es 6, guarda y termina  
   
    ; Si decenas de minutos llega a 6, reiniciar     
    LDI temp, 0               ; Reinicia decenas a 0  

INC_MIN_SAVE_D:               ; Etiqueta para guardar decenas incrementadas  
    STS cont_min_d, temp      ; Guarda el valor en variable de decenas  
    RET                       ; Retorno de la funci�n  
   
INC_MIN_SAVE_U:               ; Etiqueta para guardar unidades incrementadas  
    STS cont_min_u, temp      ; Guarda el valor en variable de unidades  
    RET                       ; Retorno de la funci�n  
    
; FUNCI�N CORREGIDA: Decrementar minutos (para bot�n PB2 en modo decremento)    
DECREMENTAR_MINUTOS:          ; Funci�n para decrementar minutos manualmente  
    ; Verificar si estamos en xx:00    
    LDS temp, cont_min_d      ; Carga decenas de minutos  
    CPI temp, 0               ; Compara si es 0  
    BRNE DEC_MIN_NOT_ZERO_D   ; Si no es 0, salta  
      
    LDS temp, cont_min_u      ; Carga unidades de minutos  
    CPI temp, 0               ; Compara si es 0  
    BRNE DEC_MIN_NOT_ZERO_U   ; Si no es 0, salta  
      
    ; Si llegamos a 00 minutos, cambiar a xx:59 (underflow)    
    LDI temp, 9               ; Carga 9 para unidades  
    STS cont_min_u, temp      ; Guarda unidades = 9  
    LDI temp, 5               ; Carga 5 para decenas  
    STS cont_min_d, temp      ; Guarda decenas = 5 (59 minutos)  
    RET                       ; Retorno de la funci�n  

DEC_MIN_NOT_ZERO_U:           ; Etiqueta para decrementar unidades no cero  
    ; Decrementar unidades de minutos    
    DEC temp                  ; Decrementa unidades  
    STS cont_min_u, temp      ; Guarda el nuevo valor  
    RET                       ; Retorno de la funci�n  
      
DEC_MIN_NOT_ZERO_D:           ; Etiqueta para decrementar con decenas no cero  
    ; Si decenas > 0, verificar si unidades es 0    
    LDS temp, cont_min_u      ; Carga unidades de minutos  
    CPI temp, 0               ; Compara si es 0  
    BRNE DEC_MIN_NOT_ZERO_U   ; Si no es 0, decrementa normalmente  
      
    ; Si unidades = 0, poner unidades en 9 y decrementar decenas    
    LDI temp, 9               ; Carga 9 para unidades  
    STS cont_min_u, temp      ; Guarda unidades = 9  
    LDS temp, cont_min_d      ; Carga decenas de minutos  
    DEC temp                  ; Decrementa decenas  
    STS cont_min_d, temp      ; Guarda el nuevo valor  
    RET                       ; Retorno de la funci�n  
   
; Funci�n para incrementar el d�a autom�ticamente (cuando cambia de 23:59 a 00:00)     
INCREMENTAR_DIA_AUTOMATICO:   ; Funci�n para cambio autom�tico de d�a  
    PUSH r20                  ; Guarda registros en pila  
    PUSH r21     
    PUSH temp  
    PUSH temp2    
     
    ; Obtener d�as m�ximos del mes actual     
    CALL OBTENER_DIAS_MES     ; Obtiene cu�ntos d�as tiene el mes actual  
    MOV r21, temp             ; r21 = d�as m�ximos del mes  
   
    ; Calcular el d�a actual (decenas*10 + unidades)     
    LDS r20, dia_d            ; Carga decenas de d�a  
    LDI temp, 10              ; Base decimal (10)  
   
    ; Multiplicaci�n manual (r20 * 10)     
    CLR temp2                 ; Limpia acumulador  
    MOV resto, r20            ; Contador para multiplicaci�n  
   
MULT_LOOP_DIA_AUTO:           ; Bucle para multiplicar por 10  
    CPI resto, 0              ; Compara si contador lleg� a 0  
    BREQ MULT_DONE_DIA_AUTO   ; Si es 0, termina multiplicaci�n  
    ADD temp2, temp           ; Suma 10 al acumulador  
    DEC resto                 ; Decrementa contador  
    RJMP MULT_LOOP_DIA_AUTO   ; Repite bucle  
   
MULT_DONE_DIA_AUTO:           ; Fin de multiplicaci�n  
    ; A�adir unidades     
    LDS r20, dia_u            ; Carga unidades de d�a  
    ADD temp2, r20            ; temp2 = d�a completo (decenas*10 + unidades)  
    ; Incrementar d�a     
    INC temp2                 ; Incrementa el d�a  
   
    ; Verificar si hemos superado el m�ximo de d�as del mes     
    CP temp2, r21             ; Compara con m�ximo de d�as  
    BRLO NO_CAMBIO_MES        ; Si es menor, no hay cambio de mes  
    BRNE CAMBIO_MES           ; Si es mayor, cambiar mes  
    RJMP NO_CAMBIO_MES        ; Si es igual, tampoco hay cambio de mes  
   
CAMBIO_MES:                   ; Manejo de cambio de mes  
    ; Si hemos superado el m�ximo, reiniciar a d�a 1 e incrementar mes     
    LDI temp, 1               ; Carga 1 para d�a nuevo  
    STS dia_u, temp           ; Guarda unidades = 1  
    LDI temp, 0               ; Carga 0 para decenas  
    STS dia_d, temp           ; Guarda decenas = 0 (d�a 01)  
   
    ; Incrementar mes     
    CALL INCREMENTAR_MES_AUTOMATICO  ; Incrementa el mes  
    POP temp2                 ; Restaura registros  
    POP temp     
    POP r21     
    POP r20     
    RET                       ; Retorno de la funci�n  
   
NO_CAMBIO_MES:                ; Sin cambio de mes, s�lo actualiza d�a  
    ; Si no hemos superado el m�ximo, actualizar d�a normalmente  
    MOV temp, temp2           ; Copia d�a incrementado  
    LDI temp2, 10             ; Base decimal (10)  
    CALL DIV                  ; Divide: temp = decenas, resto = unidades  
    STS dia_d, temp           ; Guarda decenas de d�a  
    MOV temp, resto           ; Copia unidades  
    STS dia_u, temp           ; Guarda unidades de d�a  
    POP temp2                 ; Restaura registros  
    POP temp     
    POP r21    
    POP r20     
    RET                       ; Retorno de la funci�n  
   
; Funci�n para incrementar el mes autom�ticamente     
INCREMENTAR_MES_AUTOMATICO:   ; Funci�n para cambio autom�tico de mes  
    PUSH temp                 ; Guarda registros  
    PUSH r20     
   
    ; Incrementar unidades de mes     
    LDS temp, mes_u           ; Carga unidades de mes  
    INC temp                  ; Incrementa unidades  
   
    ; Verificar si llegamos a mes 13     
    LDS r20, mes_d            ; Carga decenas de mes  
    CPI r20, 1                ; Compara si decenas es 1  
    BRNE CHECK_MES_U_AUTO     ; Si no es 1, verificaci�n normal  
    CPI temp, 3               ; Compara si unidades es 3 (mes 13)  
    BRNE CHECK_MES_U_AUTO     ; Si no es 3, verificaci�n normal  
   
    ; Si llegamos a mes 13, reiniciar a mes 1     
    LDI temp, 1               ; Carga 1 para unidades  
    STS mes_u, temp           ; Guarda unidades = 1  
    LDI temp, 0               ; Carga 0 para decenas  
    STS mes_d, temp           ; Guarda decenas = 0 (mes 01)  
   
    ; Verificar si el d�a actual es v�lido para el nuevo mes     
    CALL VALIDAR_DIA_ACTUAL   ; Valida que el d�a sea v�lido para nuevo mes  
    POP r20                   ; Restaura registros  
    POP temp     
    RET                       ; Retorno de la funci�n  
   
CHECK_MES_U_AUTO:             ; Verificaci�n normal de unidades de mes  
    ; Verificar si unidades de mes llega a 10     
    CPI temp, 10              ; Compara si unidades lleg� a 10  
    BRNE SAVE_MES_U_AUTO      ; Si no es 10, guarda y termina  
   
    ; Si unidades de mes llega a 10, reiniciar e incrementar decenas     
    LDI temp, 0               ; Reinicia unidades a 0  
    STS mes_u, temp           ; Guarda el valor  
   
    ; Incrementar decenas de mes     
    LDS temp, mes_d           ; Carga decenas de mes  
    INC temp                  ; Incrementa decenas  
    STS mes_d, temp           ; Guarda el valor  
  
    ; Verificar si el d�a actual es v�lido para el nuevo mes     
    CALL VALIDAR_DIA_ACTUAL   ; Valida que el d�a sea v�lido  
    POP r20                   ; Restaura registros  
    POP temp     
    RET                       ; Retorno de la funci�n  
   
SAVE_MES_U_AUTO:              ; Guarda unidades de mes incrementadas  
    STS mes_u, temp           ; Guarda unidades de mes  
   
    ; Verificar si el d�a actual es v�lido para el nuevo mes     
    CALL VALIDAR_DIA_ACTUAL   ; Valida que el d�a sea v�lido  
    POP r20                   ; Restaura registros  
    POP temp     
    RET                       ; Retorno de la funci�n  
   
; Funci�n para obtener el n�mero m�ximo de d�as para el mes actual     
OBTENER_DIAS_MES:             ; Funci�n para calcular d�as del mes actual  
    PUSH r20                  ; Guarda registros  
    PUSH r21    
    PUSH temp2     
   
    ; Calcular el mes actual (decenas*10 + unidades)     
    LDS r20, mes_d            ; Carga decenas de mes  
    LDI r21, 10               ; Base decimal (10)  
  
    ; Multiplicaci�n manual (r20 * 10)     
    CLR temp                  ; Limpia acumulador  
    MOV temp2, r20            ; Contador para multiplicaci�n  
   
MULT_LOOP_MES:                ; Bucle para multiplicar por 10  
    CPI temp2, 0              ; Compara si contador lleg� a 0  
    BREQ MULT_DONE_MES        ; Si es 0, termina multiplicaci�n  
    ADD temp, r21             ; Suma 10 al acumulador  
    DEC temp2                 ; Decrementa contador  
    RJMP MULT_LOOP_MES        ; Repite bucle  
   
MULT_DONE_MES:                ; Fin de multiplicaci�n  
    ; A�adir unidades     
    LDS r21, mes_u            ; Carga unidades de mes  
    ADD temp, r21             ; temp = mes completo (decenas*10 + unidades)  
   
    ; Verificar el mes y asignar d�as     
    CPI temp, 2               ; Verifica si es febrero (mes 2)  
    BRNE CHECK_MES_30         ; Si no es febrero, verifica meses de 30 d�as  
    LDI temp, 28              ; Febrero tiene 28 d�as (no considera a�os bisiestos)  
    RJMP FIN_OBTENER_DIAS     ; Salta a fin de funci�n  
   
CHECK_MES_30:                 ; Verificaci�n de meses con 30 d�as  
    CPI temp, 4               ; Verifica si es abril (mes 4)  
    BREQ MES_30               ; Si es abril, tiene 30 d�as  
    CPI temp, 6               ; Verifica si es junio (mes 6)  
    BREQ MES_30               ; Si es junio, tiene 30 d�as  
    CPI temp, 9               ; Verifica si es septiembre (mes 9)  
    BREQ MES_30               ; Si es septiembre, tiene 30 d�as  
    CPI temp, 11              ; Verifica si es noviembre (mes 11)  
    BREQ MES_30               ; Si es noviembre, tiene 30 d�as  
   
    ; Si no es mes de 30 d�as, asumimos 31 d�as     
    LDI temp, 31              ; Meses con 31 d�as (1,3,5,7,8,10,12)  
    RJMP FIN_OBTENER_DIAS     ; Salta a fin de funci�n  
   
MES_30:                       ; Etiqueta para meses con 30 d�as  
    LDI temp, 30              ; Carga 30 d�as  
   
FIN_OBTENER_DIAS:             ; Fin de la funci�n  
    POP temp2                 ; Restaura registros  
    POP r21     
    POP r20     
    RET                       ; Retorno con resultado en temp  
   
; Funci�n para validar que el d�a actual sea v�lido para el mes actual     
VALIDAR_DIA_ACTUAL:           ; Funci�n para verificar validez del d�a actual  
    PUSH r20                  ; Guarda registros  
    PUSH r21     
    PUSH temp     
    PUSH temp2  
    
    ; Obtener d�as m�ximos del mes actual     
    CALL OBTENER_DIAS_MES     ; Obtiene n�mero m�ximo de d�as  
    MOV r21, temp             ; r21 = d�as m�ximos  
   
    ; Calcular el d�a actual (decenas*10 + unidades)    
    LDS r20, dia_d            ; Carga decenas de d�a  
    LDI temp, 10              ; Base decimal (10)  
   
    ; Multiplicaci�n manual (r20 * 10)     
    CLR temp2                 ; Limpia acumulador  
    MOV temp, r20             ; Contador para multiplicaci�n  
   
MULT_LOOP_DIA:                ; Bucle para multiplicar por 10  
    CPI temp, 0               ; Compara si contador lleg� a 0  
    BREQ MULT_DONE_DIA        ; Si es 0, termina multiplicaci�n  
    ADD temp2, temp           ; Suma 10 al acumulador  
    DEC temp                  ; Decrementa contador  
    RJMP MULT_LOOP_DIA        ; Repite bucle  
   
MULT_DONE_DIA:                ; Fin de multiplicaci�n  
    ; A�adir unidades     
    LDS r20, dia_u            ; Carga unidades de d�a  
    ADD temp2, r20            ; temp2 = d�a completo (decenas*10 + unidades)  
   
    ; Si el d�a actual es mayor que el m�ximo, ajustar al m�ximo     
    CP temp2, r21             ; Compara con m�ximo de d�as  
    BRLO DIA_VALIDO           ; Si es menor, el d�a es v�lido  
  
    ; Ajustar al �ltimo d�a del mes     
    MOV temp, r21             ; Copia m�ximo de d�as  
   
    ; Calcular decenas y unidades     
    LDI temp2, 10             ; Base decimal (10)  
    CALL DIV                  ; Divide: temp = decenas, resto = unidades  
    STS dia_d, temp           ; Guarda decenas de d�a  
    MOV temp, resto           ; Copia unidades  
    STS dia_u, temp           ; Guarda unidades de d�a  
   
DIA_VALIDO:                   ; Etiqueta para d�a v�lido  
    POP temp2                 ; Restaura registros  
    POP temp     
    POP r21     
    POP r20     
    RET                       ; Retorno de la funci�n  
   
; Funci�n auxiliar para divisi�n - CORREGIDA     
DIV:                          ; Funci�n para divisi�n temp / temp2  
    ; Divide temp entre temp2, resultado en temp, resto en resto (r22)     
    PUSH r21                  ; Guarda r21 en pila  
    CLR r21                   ; r21 ser� nuestro cociente, inicia en 0  
   
DIV_LOOP:                     ; Bucle de divisi�n  
    CP temp, temp2            ; Compara temp con temp2  
    BRLO DIV_END              ; Si temp < temp2, termina divisi�n  
    SUB temp, temp2           ; temp = temp - temp2 (resta divisor)  
    INC r21                   ; Incrementa cociente  
    RJMP DIV_LOOP             ; Repite bucle  
   
DIV_END:                      ; Fin de divisi�n  
    MOV resto, temp           ; Guarda resto en registro resto (r22)  
    MOV temp, r21             ; Pone cociente en temp  
    POP r21                   ; Restaura r21  
    RET                       ; Retorno con cociente en temp y resto en r22  
   
; FUNCI�N MODIFICADA: Ahora permite incrementar o decrementar horas/d�as    
BOTON_HORAS:                  ; Funci�n para manejar botones de horas/d�as  
    ; Verificar en qu� modo estamos     
    CPI modo, 2               ; Compara si estamos en modo configuraci�n hora  
    BRNE CHECK_MODO_FECHA_DIAS ; Si no es modo 2, verifica si es modo fecha  
    
    ; Modo configuraci�n hora    
    ; Verificar si estamos configurando horas (config_sel = 1)    
    CPI config_sel, 1         ; Compara si selector es 1 (configurando horas)  
    BRNE FIN_BOTON_HORAS      ; Si no configuramos horas, ignora bot�n  
      
    ; Incrementar horas si estamos presionando PB1, decrementar si PB2    
    SBIS PINB, PB1            ; Si PB1 est� presionado (incrementar)  
    CALL INCREMENTAR_HORAS    ; Llama funci�n de incremento  
    SBIS PINB, PB2            ; Si PB2 est� presionado (decrementar)  
    CALL DECREMENTAR_HORAS    ; Llama funci�n de decremento  
      
    RET                       ; Retorno de la funci�n  
      
CHECK_MODO_FECHA_DIAS:        ; Verificaci�n para modo fecha  
    CPI modo, 3               ; Compara si estamos en modo configuraci�n fecha  
    BRNE CHECK_MODO_ALARMA_HORAS ; Si no es modo 3, verifica si es modo alarma  
      
    ; Modo configuraci�n fecha    
    ; Verificar si estamos configurando d�as (config_sel = 1)    
    CPI config_sel, 1         ; Compara si selector es 1 (configurando d�as)  
    BRNE FIN_BOTON_HORAS      ; Si no configuramos d�as, ignora bot�n  
   
    ; Incrementar d�as si estamos presionando PB1, decrementar si PB2    
    SBIS PINB, PB1            ; Si PB1 est� presionado (incrementar)  
    CALL INCREMENTAR_DIAS     ; Llama funci�n de incremento d�as  
      
    SBIS PINB, PB2            ; Si PB2 est� presionado (decrementar)  
    CALL DECREMENTAR_DIAS     ; Llama funci�n de decremento d�as  
  
    RET                       ; Retorno de la funci�n  

CHECK_MODO_ALARMA_HORAS:       ; Verificaci�n para modo alarma (horas)  
    CPI modo, 4                ; Compara si estamos en modo configuraci�n alarma  
    BRNE FIN_BOTON_HORAS       ; Si no es modo 4, termina funci�n  

    ; Modo configuraci�n alarma  
    ; Verificar si estamos configurando horas (config_sel = 1)  
    CPI config_sel, 1          ; Compara si selector es 1 (configurando horas)  
    BRNE FIN_BOTON_HORAS       ; Si no configuramos horas, ignora bot�n  

    ; Incrementar horas si estamos presionando PB1, decrementar si PB2  
    SBIS PINB, PB1             ; Si PB1 est� presionado (incrementar)  
    CALL INCREMENTAR_HORAS_ALARMA ; Llama funci�n de incremento de horas de alarma  

    SBIS PINB, PB2             ; Si PB2 est� presionado (decrementar)  
    CALL DECREMENTAR_HORAS_ALARMA ; Llama funci�n de decremento de horas de alarma  
      
FIN_BOTON_HORAS:               ; Etiqueta de fin de funci�n  
    RET                        ; Retorno de la funci�n  
    
; FUNCI�N MODIFICADA: Ahora permite incrementar o decrementar minutos/meses    
BOTON_MINUTOS:                 ; Funci�n para manejar botones de minutos/meses  
    ; Verificar en qu� modo estamos  
    CPI modo, 2                ; Compara si estamos en modo configuraci�n hora  
    BRNE CHECK_CONFIG_FECHA_MESES ; Si no es modo 2, verifica modo fecha  
      
    ; Modo configuraci�n hora    
    ; Verificar si estamos configurando minutos (config_sel = 0)    
    CPI config_sel, 0          ; Compara si selector es 0 (configurando minutos)  
    BRNE FIN_BOTON_MINUTOS     ; Si no configuramos minutos, ignora bot�n  
      
    ; Incrementar minutos si estamos presionando PB1, decrementar si PB2    
    SBIS PINB, PB1             ; Si PB1 est� presionado (incrementar)  
    CALL INCREMENTAR_MINUTOS   ; Llama funci�n de incremento minutos  
    SBIS PINB, PB2             ; Si PB2 est� presionado (decrementar)  
    CALL DECREMENTAR_MINUTOS   ; Llama funci�n de decremento minutos  
      
    RET                        ; Retorno de la funci�n  
      
CHECK_CONFIG_FECHA_MESES:      ; Verificaci�n para modo fecha (meses)  
    CPI modo, 3                ; Compara si estamos en modo configuraci�n fecha  
    BRNE CHECK_CONFIG_ALARMA_MINUTOS ; Si no es modo 3, verifica modo alarma  
      
    ; Modo configuraci�n fecha    
    ; Verificar si estamos configurando meses (config_sel = 0)    
    CPI config_sel, 0          ; Compara si selector es 0 (configurando meses)  
    BRNE FIN_BOTON_MINUTOS     ; Si no configuramos meses, ignora bot�n  
      
    ; Incrementar meses si estamos presionando PB1, decrementar si PB2  
    SBIS PINB, PB1             ; Si PB1 est� presionado (incrementar)  
    CALL INCREMENTAR_MESES     ; Llama funci�n de incremento meses  
      
    SBIS PINB, PB2             ; Si PB2 est� presionado (decrementar)  
    CALL DECREMENTAR_MESES     ; Llama funci�n de decremento meses  
    RET                        ; Retorno de la funci�n  

CHECK_CONFIG_ALARMA_MINUTOS:   ; Verificaci�n para modo alarma (minutos)  
    CPI modo, 4                ; Compara si estamos en modo configuraci�n alarma  
    BRNE FIN_BOTON_MINUTOS     ; Si no es modo 4, termina funci�n  

    ; Modo configuraci�n alarma  
    ; Verificar si estamos configurando minutos (config_sel = 0)  
    CPI config_sel, 0          ; Compara si selector es 0 (configurando minutos)  
    BRNE FIN_BOTON_MINUTOS     ; Si no configuramos minutos, ignora bot�n  

    ; Incrementar minutos si estamos presionando PB1, decrementar si PB2  
    SBIS PINB, PB1             ; Si PB1 est� presionado (incrementar)  
    CALL INCREMENTAR_MINUTOS_ALARMA ; Llama funci�n de incremento minutos de alarma  

    SBIS PINB, PB2             ; Si PB2 est� presionado (decrementar)  
    CALL DECREMENTAR_MINUTOS_ALARMA ; Llama funci�n de decremento minutos de alarma  
      
FIN_BOTON_MINUTOS:             ; Etiqueta de fin de funci�n  
    RET                        ; Retorno de la funci�n  
    
; FUNCI�N: Cambiar entre configurar horas/minutos o d�as/meses    
CAMBIAR_CONFIG_SEL:            ; Funci�n para alternar config_sel entre 0 y 1  
    ; Alternar entre 0 y 1    
    LDI temp, 1                ; Carga valor 1  
    EOR config_sel, temp       ; Operaci�n XOR para alternar bit 0  
    RET                        ; Retorno de la funci�n  
    
; Funci�n para incrementar d�as    
INCREMENTAR_DIAS:              ; Funci�n para incrementar d�as manualmente  
    PUSH r20                   ; Guarda registros en pila  
    PUSH r21     
    PUSH temp     
    PUSH temp2     
      
    ; Obtener d�as m�ximos del mes actual     
    CALL OBTENER_DIAS_MES      ; Obtiene cu�ntos d�as tiene el mes actual  
    MOV r21, temp              ; r21 = d�as m�ximos del mes  
  
    ; Calcular el d�a actual (decenas*10 + unidades)     
    LDS r20, dia_d             ; Carga decenas de d�a  
    LDI temp, 10               ; Base decimal (10)  
      
    ; Multiplicaci�n manual (r20 * 10)     
    CLR temp2                  ; Limpia acumulador  
    MOV resto, r20             ; Contador para multiplicaci�n  
   
MULT_LOOP_DIA_BOTON_INC:       ; Bucle para multiplicar por 10  
    CPI resto, 0               ; Compara si contador lleg� a 0  
    BREQ MULT_DONE_DIA_BOTON_INC ; Si es 0, termina multiplicaci�n  
    ADD temp2, temp            ; Suma 10 al acumulador  
    DEC resto                  ; Decrementa contador  
    RJMP MULT_LOOP_DIA_BOTON_INC ; Repite bucle  
   
MULT_DONE_DIA_BOTON_INC:       ; Fin de multiplicaci�n  
    ; A�adir unidades     
    LDS r20, dia_u             ; Carga unidades de d�a  
    ADD temp2, r20             ; temp2 = d�a completo (decenas*10 + unidades)  
      
    ; Incrementar d�a     
    INC temp2                  ; Incrementa el d�a  
      
    ; Verificar si hemos superado el m�ximo de d�as del mes     
    CP temp2, r21              ; Compara con m�ximo de d�as  
    BRLO NO_OVERFLOW_DIA_INC   ; Si es menor, no hay overflow  
    BRNE OVERFLOW_DIA_INC      ; Si es mayor, hacer overflow  
    RJMP NO_OVERFLOW_DIA_INC   ; Si es igual, tampoco hay overflow  
      
OVERFLOW_DIA_INC:              ; Manejo de overflow de d�a  
    ; Si hemos superado el m�ximo, reiniciar a d�a 1     
    LDI temp, 1                ; Carga 1 para d�a nuevo  
    STS dia_u, temp            ; Guarda unidades = 1  
    LDI temp, 0                ; Carga 0 para decenas  
    STS dia_d, temp            ; Guarda decenas = 0 (d�a 01)  
      
    POP temp2                  ; Restaura registros  
    POP temp     
    POP r21     
    POP r20     
    RET                        ; Retorno de la funci�n  
      
NO_OVERFLOW_DIA_INC:           ; Sin overflow, actualiza normalmente  
    ; Si no hemos superado el m�ximo, actualizar d�a normalmente     
    MOV temp, temp2            ; Copia d�a incrementado  
    LDI temp2, 10              ; Base decimal (10)  
    CALL DIV                   ; Divide: temp = decenas, resto = unidades  
    STS dia_d, temp            ; Guarda decenas de d�a  
    MOV temp, resto            ; Copia unidades  
    STS dia_u, temp            ; Guarda unidades de d�a  
    POP temp2                  ; Restaura registros  
    POP temp     
    POP r21     
    POP r20     
    RET                        ; Retorno de la funci�n  
    
; FUNCI�N CORREGIDA: Decrementar d�as    
DECREMENTAR_DIAS:              ; Funci�n para decrementar d�as manualmente  
    PUSH r20                   ; Guarda registros en pila  
    PUSH r21    
    PUSH temp    
    PUSH temp2   
    
    ; Calcular el d�a actual (decenas*10 + unidades)    
    LDS r20, dia_d             ; Carga decenas de d�a  
    LDI temp, 10               ; Base decimal (10)  
      
    ; Multiplicaci�n manual (r20 * 10)    
    CLR temp2                  ; Limpia acumulador  
    MOV resto, r20             ; Contador para multiplicaci�n  
   
MULT_LOOP_DIA_BOTON_DEC:       ; Bucle para multiplicar por 10  
    CPI resto, 0               ; Compara si contador lleg� a 0  
    BREQ MULT_DONE_DIA_BOTON_DEC ; Si es 0, termina multiplicaci�n  
    ADD temp2, temp            ; Suma 10 al acumulador  
    DEC resto                  ; Decrementa contador  
    RJMP MULT_LOOP_DIA_BOTON_DEC ; Repite bucle  
  
MULT_DONE_DIA_BOTON_DEC:       ; Fin de multiplicaci�n  
    ; A�adir unidades    
    LDS r20, dia_u             ; Carga unidades de d�a  
    ADD temp2, r20             ; temp2 = d�a completo (decenas*10 + unidades)  
      
    ; Verificar si estamos en d�a 1    
    CPI temp2, 1               ; Compara si es d�a 1  
    BRNE NO_UNDERFLOW_DIA      ; Si no es d�a 1, no hay underflow  
      
    ; Si es d�a 1, cambiar al �ltimo d�a del mes    
    CALL OBTENER_DIAS_MES      ; Obtiene d�as del mes actual  
    MOV temp2, temp            ; temp2 = �ltimo d�a del mes  
    RJMP ACTUALIZAR_DIA_DEC    ; Salta a actualizar d�a  
      
NO_UNDERFLOW_DIA:              ; Sin underflow, decrementa normalmente  
    ; Si no es d�a 1, simplemente decrementar    
    DEC temp2                  ; Decrementa d�a  
      
ACTUALIZAR_DIA_DEC:            ; Actualiza d�a decrementado  
    ; Actualizar d�a    
    MOV temp, temp2            ; Copia d�a decrementado  
    LDI temp2, 10              ; Base decimal (10)  
    CALL DIV                   ; Divide: temp = decenas, resto = unidades  
    STS dia_d, temp            ; Guarda decenas de d�a  
    MOV temp, resto            ; Copia unidades  
    STS dia_u, temp            ; Guarda unidades de d�a  
      
    POP temp2                  ; Restaura registros  
    POP temp    
    POP r21    
    POP r20    
    RET                        ; Retorno de la funci�n  
    
; Funci�n para incrementar meses     
INCREMENTAR_MESES:             ; Funci�n para incrementar meses manualmente  
    PUSH r20                   ; Guarda registros en pila  
    PUSH temp   
    
    ; Incrementar unidades de mes     
    LDS temp, mes_u            ; Carga unidades de mes  
    INC temp                   ; Incrementa unidades  
      
    ; Verificar si llegamos a mes 13     
    LDS r20, mes_d             ; Carga decenas de mes  
    CPI r20, 1                 ; Compara si decenas es 1  
    BRNE CHECK_MES_U           ; Si no es 1, verificaci�n normal  
    CPI temp, 3                ; Compara si unidades es 3 (mes 13)  
    BRNE CHECK_MES_U           ; Si no es 3, verificaci�n normal  
      
    ; Si llegamos a mes 13, reiniciar a mes 1     
    LDI temp, 1                ; Carga 1 para unidades  
    STS mes_u, temp            ; Guarda unidades = 1  
    LDI temp, 0                ; Carga 0 para decenas  
    STS mes_d, temp            ; Guarda decenas = 0 (mes 01)  
      
    ; Verificar si el d�a actual es v�lido para el nuevo mes     
    CALL VALIDAR_DIA_ACTUAL    ; Valida que el d�a sea v�lido para nuevo mes  
      
    POP temp                   ; Restaura registros  
    POP r20     
    RET                        ; Retorno de la funci�n  
      
CHECK_MES_U:                   ; Verificaci�n normal de unidades de mes  
    ; Verificar si unidades de mes llega a 10     
    CPI temp, 10               ; Compara si unidades lleg� a 10  
    BRNE SAVE_MES_U            ; Si no es 10, guarda y termina  
      
    ; Si unidades de mes llega a 10, reiniciar e incrementar decenas     
    LDI temp, 0                ; Reinicia unidades a 0  
    STS mes_u, temp            ; Guarda el valor  
      
    ; Incrementar decenas de mes     
    LDS temp, mes_d            ; Carga decenas de mes  
    INC temp                   ; Incrementa decenas  
    STS mes_d, temp            ; Guarda el valor  
      
    ; Verificar si el d�a actual es v�lido para el nuevo mes     
    CALL VALIDAR_DIA_ACTUAL    ; Valida que el d�a sea v�lido  
    POP temp                   ; Restaura registros  
    POP r20     
    RET                        ; Retorno de la funci�n  
      
SAVE_MES_U:                    ; Guarda unidades de mes incrementadas  
    STS mes_u, temp            ; Guarda unidades de mes  
      
    ; Verificar si el d�a actual es v�lido para el nuevo mes     
    CALL VALIDAR_DIA_ACTUAL    ; Valida que el d�a sea v�lido  
    POP temp                   ; Restaura registros  
    POP r20     
    RET                        ; Retorno de la funci�n  
    
; FUNCI�N CORREGIDA: Decrementar meses (usando registros v�lidos)    
DECREMENTAR_MESES:             ; Funci�n para decrementar meses manualmente  
    PUSH r20                   ; Guarda registros en pila  
    PUSH r21   
    PUSH temp   
    PUSH temp2   
   
    ; Calcular el mes actual (decenas*10 + unidades)   
    LDS r20, mes_d             ; Cargar decenas del mes   
    LDI r21, 10                ; Base decimal   
    CLR temp2                  ; Inicializar acumulador  
    
    ; Multiplicar decenas por 10   
    MOV resto, r20             ; Contador de decenas   
    
MULT_LOOP_MES_DEC:             ; Bucle para multiplicar por 10  
    CPI resto, 0               ; Compara si contador lleg� a 0  
    BREQ MULT_DONE_MES_DEC     ; Si es 0, termina multiplicaci�n  
    ADD temp2, r21             ; temp2 += 10   
    DEC resto                  ; Decrementa contador  
    RJMP MULT_LOOP_MES_DEC     ; Repite bucle  
   
MULT_DONE_MES_DEC:             ; Fin de multiplicaci�n  
    ; Sumar unidades del mes   
    LDS r20, mes_u             ; Carga unidades de mes  
    ADD temp2, r20             ; temp2 = mes completo (1-12)   
   
    ; Verificar si el mes es 1 (underflow a 12)   
    CPI temp2, 1               ; Compara si es mes 1  
    BRNE NO_UNDERFLOW_MES      ; Si no es mes 1, no hay underflow  
   
    ; Cambiar a mes 12 (diciembre)   
    LDI temp, 1                ; mes_d = 1 (decena)   
    STS mes_d, temp            ; Guarda decenas = 1  
    LDI temp, 2                ; mes_u = 2 (unidad)   
    STS mes_u, temp            ; Guarda unidades = 2 (mes 12)  
    RJMP VALIDAR_MES_DEC       ; Salta a validar d�a para nuevo mes  
   
NO_UNDERFLOW_MES:              ; Sin underflow, decrementa normalmente  
    ; Decrementar unidades del mes   
    LDS temp, mes_u            ; Carga unidades de mes  
    CPI temp, 0                ; Compara si unidades es 0  
    BRNE DEC_MES_U             ; Si unidades != 0, decrementar normalmente   
   
    ; Si unidades es 0 (ej: 10 ? 09)   
    LDI temp, 9                ; mes_u = 9   
    STS mes_u, temp            ; Guarda unidades = 9  
    LDS temp, mes_d            ; Carga decenas de mes  
    DEC temp                   ; mes_d -= 1 (ej: 1 ? 0 para 10 ? 09)   
    STS mes_d, temp            ; Guarda decenas decrementadas  
    RJMP VALIDAR_MES_DEC       ; Salta a validar d�a para nuevo mes  
   
DEC_MES_U:                     ; Decrementar unidades normalmente  
    ; Decrementar unidades normalmente   
    DEC temp                   ; Decrementa unidades  
    STS mes_u, temp            ; Guarda el nuevo valor  
   
VALIDAR_MES_DEC:               ; Validaci�n del d�a para el nuevo mes  
    ; Asegurar que el d�a actual sea v�lido para el nuevo mes   
    CALL VALIDAR_DIA_ACTUAL    ; Valida que el d�a sea v�lido  
   
    POP temp2                  ; Restaura registros  
    POP temp   
    POP r21   
    POP r20  
    RET                        ; Retorno de la funci�n  

; Funciones para manejar la alarma  
; Incrementar horas de alarma  
INCREMENTAR_HORAS_ALARMA:      ; Funci�n para incrementar horas de alarma  
    ; Incrementar unidades de horas de alarma  
    LDS temp, alarm_hr_u       ; Carga unidades de horas de alarma  
    INC temp                   ; Incrementa unidades  
   
    ; Verificar si llegamos a 24 horas  
    LDS temp2, alarm_hr_d      ; Carga decenas de horas de alarma  
    CPI temp2, 2               ; Compara si decenas es 2  
    BRNE INC_ALARM_HR_CHECK_U  ; Si no es 2, verificaci�n normal  
    CPI temp, 4                ; Compara si unidades lleg� a 4 (24 horas)  
    BRNE INC_ALARM_HR_CHECK_U  ; Si no es 4, verificaci�n normal  
   
    ; Si llegamos a 24 horas, reiniciar a 00:00  
    LDI temp, 0                ; Reinicia unidades a 0  
    STS alarm_hr_u, temp       ; Guarda unidades = 0  
    LDI temp, 0                ; Reinicia decenas a 0  
    STS alarm_hr_d, temp       ; Guarda decenas = 0 (hora 00)  
    RET                        ; Retorno de la funci�n  
   
INC_ALARM_HR_CHECK_U:          ; Verificaci�n normal de unidades de hora  
    ; Verificar si unidades de hora llega a 10  
    CPI temp, 10               ; Compara si unidades lleg� a 10  
    BRNE INC_ALARM_HR_SAVE_U   ; Si no es 10, guarda y termina  
   
    ; Si unidades llega a 10, reiniciar e incrementar decenas  
    LDI temp, 0                ; Reinicia unidades a 0  
    STS alarm_hr_u, temp       ; Guarda el valor  
   
    ; Incrementar decenas de horas  
    LDS temp, alarm_hr_d       ; Carga decenas de horas  
    INC temp                   ; Incrementa decenas  
    STS alarm_hr_d, temp       ; Guarda el valor  
    RET                        ; Retorno de la funci�n  
   
INC_ALARM_HR_SAVE_U:           ; Guarda unidades incrementadas  
    STS alarm_hr_u, temp       ; Guarda unidades de hora  
    RET                        ; Retorno de la funci�n  

; Decrementar horas de alarma  
DECREMENTAR_HORAS_ALARMA:      ; Funci�n para decrementar horas de alarma  
    ; Verificar si estamos en 00:xx  
    LDS temp, alarm_hr_d       ; Carga decenas de horas  
    CPI temp, 0                ; Compara si es 0  
    BRNE DEC_ALARM_HR_NOT_ZERO_D ; Si no es 0, salta  
      
    LDS temp, alarm_hr_u       ; Carga unidades de horas  
    CPI temp, 0                ; Compara si es 0  
    BRNE DEC_ALARM_HR_NOT_ZERO_U ; Si no es 0, salta  
      
    ; Si llegamos a 00 horas, cambiar a 23:xx (underflow)  
    LDI temp, 3                ; Carga 3 para unidades  
    STS alarm_hr_u, temp       ; Guarda unidades = 3  
    LDI temp, 2                ; Carga 2 para decenas  
    STS alarm_hr_d, temp       ; Guarda decenas = 2 (hora 23)  
    RET                        ; Retorno de la funci�n  
      
DEC_ALARM_HR_NOT_ZERO_U:       ; Decrementa unidades no cero  
    ; Decrementar unidades de hora  
    DEC temp                   ; Decrementa unidades  
    STS alarm_hr_u, temp       ; Guarda el nuevo valor  
    RET                        ; Retorno de la funci�n  

DEC_ALARM_HR_NOT_ZERO_D:       ; Decrementa con decenas no cero  
    ; Si decenas > 0, verificar si unidades es 0  
    LDS temp, alarm_hr_u       ; Carga unidades de horas  
    CPI temp, 0                ; Compara si es 0  
    BRNE DEC_ALARM_HR_NOT_ZERO_U ; Si no es 0, decrementa normalmente  
      
    ; Si unidades = 0, poner unidades en 9 y decrementar decenas  
    LDI temp, 9                ; Carga 9 para unidades  
    STS alarm_hr_u, temp       ; Guarda unidades = 9  
    LDS temp, alarm_hr_d       ; Carga decenas de horas  
    DEC temp                   ; Decrementa decenas  
    STS alarm_hr_d, temp       ; Guarda el nuevo valor  
    RET                        ; Retorno de la funci�n  

; Incrementar minutos de alarma  
INCREMENTAR_MINUTOS_ALARMA:    ; Funci�n para incrementar minutos de alarma  
    ; Incrementar unidades de minutos  
    LDS temp, alarm_min_u      ; Carga unidades de minutos  
    INC temp                   ; Incrementa unidades  
    CPI temp, 10               ; Compara si lleg� a 10  
    BRNE INC_ALARM_MIN_SAVE_U  ; Si no es 10, guarda y termina  
   
    ; Si unidades llega a 10, reiniciar e incrementar decenas  
    LDI temp, 0                ; Reinicia unidades a 0  
    STS alarm_min_u, temp      ; Guarda el valor  
   
    ; Incrementar decenas de minutos  
    LDS temp, alarm_min_d      ; Carga decenas de minutos  
    INC temp                   ; Incrementa decenas  
    CPI temp, 6                ; Compara si lleg� a 6 (60 minutos)  
    BRNE INC_ALARM_MIN_SAVE_D  ; Si no es 6, guarda y termina  
   
    ; Si decenas llega a 6, reiniciar  
    LDI temp, 0                ; Reinicia decenas a 0  

INC_ALARM_MIN_SAVE_D:          ; Guarda decenas incrementadas  
    STS alarm_min_d, temp      ; Guarda el valor  
    RET                        ; Retorno de la funci�n  
   
INC_ALARM_MIN_SAVE_U:          ; Guarda unidades incrementadas  
    STS alarm_min_u, temp      ; Guarda el valor  
    RET                        ; Retorno de la funci�n  

; Decrementar minutos de alarma  
DECREMENTAR_MINUTOS_ALARMA:    ; Funci�n para decrementar minutos de alarma  
    ; Verificar si estamos en xx:00  
    LDS temp, alarm_min_d      ; Carga decenas de minutos  
    CPI temp, 0                ; Compara si es 0  
    BRNE DEC_ALARM_MIN_NOT_ZERO_D ; Si no es 0, salta  
      
    LDS temp, alarm_min_u      ; Carga unidades de minutos  
    CPI temp, 0                ; Compara si es 0  
    BRNE DEC_ALARM_MIN_NOT_ZERO_U ; Si no es 0, salta  
      
    ; Si llegamos a 00 minutos, cambiar a xx:59 (underflow)  
    LDI temp, 9                ; Carga 9 para unidades  
    STS alarm_min_u, temp      ; Guarda unidades = 9  
    LDI temp, 5                ; Carga 5 para decenas  
    STS alarm_min_d, temp      ; Guarda decenas = 5 (59 minutos)  
    RET                        ; Retorno de la funci�n  

DEC_ALARM_MIN_NOT_ZERO_U:      ; Decrementa unidades no cero  
    ; Decrementar unidades de minutos  
    DEC temp                   ; Decrementa unidades  
    STS alarm_min_u, temp      ; Guarda el nuevo valor  
    RET                        ; Retorno de la funci�n  
      
DEC_ALARM_MIN_NOT_ZERO_D:      ; Decrementa con decenas no cero  
    ; Si decenas > 0, verificar si unidades es 0  
    LDS temp, alarm_min_u      ; Carga unidades de minutos  
    CPI temp, 0                ; Compara si es 0  
    BRNE DEC_ALARM_MIN_NOT_ZERO_U ; Si no es 0, decrementa normalmente  
      
    ; Si unidades = 0, poner unidades en 9 y decrementar decenas  
    LDI temp, 9                ; Carga 9 para unidades  
    STS alarm_min_u, temp      ; Guarda unidades = 9  
    LDS temp, alarm_min_d      ; Carga decenas de minutos  
    DEC temp                   ; Decrementa decenas  
    STS alarm_min_d, temp      ; Guarda el nuevo valor  
    RET                        ; Retorno de la funci�n  

; Verificar si la hora actual coincide con la hora de la alarma  
VERIFICAR_ALARMA:              ; Funci�n para comprobar coincidencia con alarma  
    PUSH temp                  ; Guarda registros en pila  
    PUSH temp2   
   
    ; Verificar si la alarma ya est� activa   
    LDS temp, alarm_active     ; Carga estado de alarma  
    CPI temp, 1                ; Compara si est� activa (1)  
    BREQ FIN_VERIFICAR_ALARMA  ; Si ya est� activa, no hacer nada m�s  
    
    ; NUEVO: Verificar bit de alarma apagada manualmente  
    SBRC flags, 1              ; Saltar siguiente instrucci�n si bit 1 est� borrado  
    RJMP COMPROBAR_CAMBIO_HORA ; Si alarma fue apagada, verificar si cambi� la hora  
   
CONTINUAR_VERIFICACION:        ; Contin�a verificaci�n normal  
    ; Comparar horas   
    LDS temp, cont_hr_d        ; Carga decenas de hora actual  
    LDS temp2, alarm_hr_d      ; Carga decenas de hora de alarma  
    CP temp, temp2             ; Compara ambos valores  
    BRNE FIN_VERIFICAR_ALARMA  ; Si decenas de hora no coinciden, salir   
   
    LDS temp, cont_hr_u        ; Carga unidades de hora actual  
    LDS temp2, alarm_hr_u      ; Carga unidades de hora de alarma  
    CP temp, temp2             ; Compara ambos valores  
    BRNE FIN_VERIFICAR_ALARMA  ; Si unidades de hora no coinciden, salir   
   
    ; Comparar minutos   
    LDS temp, cont_min_d       ; Carga decenas de minutos actuales  
    LDS temp2, alarm_min_d     ; Carga decenas de minutos de alarma  
    CP temp, temp2             ; Compara ambos valores  
    BRNE FIN_VERIFICAR_ALARMA  ; Si decenas de minutos no coinciden, salir  
    
    LDS temp, cont_min_u       ; Carga unidades de minutos actuales  
    LDS temp2, alarm_min_u     ; Carga unidades de minutos de alarma  
    CP temp, temp2             ; Compara ambos valores  
    BRNE FIN_VERIFICAR_ALARMA  ; Si unidades de minutos no coinciden, salir   
   
    ; Si todo coincide, activar la alarma   
    LDI temp, 1                ; Valor = 1 (alarma activa)  
    STS alarm_active, temp     ; Activa la alarma  
    LDI temp, 0                ; Valor = 0  
    STS alarm_counter, temp    ; Reinicia contador de duraci�n  
    SBI PORTB, PB5             ; Encender LED de alarma (PB5)   
    RJMP FIN_VERIFICAR_ALARMA  ; Salta a fin de funci�n  
    
COMPROBAR_CAMBIO_HORA:         ; Verificaci�n para reset de bit de alarma  
    ; Verificar si la hora actual ya no coincide con la hora de alarma  
    ; para limpiar el bit de alarma apagada manualmente  
    
    ; Comparar horas  
    LDS temp, cont_hr_d        ; Carga decenas de hora actual  
    LDS temp2, alarm_hr_d      ; Carga decenas de hora de alarma  
    CP temp, temp2             ; Compara ambos valores  
    BRNE RESET_ALARM_FLAG      ; Si no coinciden, resetear flag  
    
    LDS temp, cont_hr_u        ; Carga unidades de hora actual  
    LDS temp2, alarm_hr_u      ; Carga unidades de hora de alarma  
    CP temp, temp2             ; Compara ambos valores  
    BRNE RESET_ALARM_FLAG      ; Si no coinciden, resetear flag  
    
    ; Comparar minutos  
    LDS temp, cont_min_d       ; Carga decenas de minutos actuales  
    LDS temp2, alarm_min_d     ; Carga decenas de minutos de alarma  
    CP temp, temp2             ; Compara ambos valores  
    BRNE RESET_ALARM_FLAG      ; Si no coinciden, resetear flag  
    
    LDS temp, cont_min_u       ; Carga unidades de minutos actuales  
    LDS temp2, alarm_min_u     ; Carga unidades de minutos de alarma  
    CP temp, temp2             ; Compara ambos valores  
    BRNE RESET_ALARM_FLAG      ; Si no coinciden, resetear flag  
    
    ; Si todav�a coincide la hora, mantener bit y salir  
    RJMP FIN_VERIFICAR_ALARMA  ; Salta a fin de funci�n  
    
RESET_ALARM_FLAG:              ; Resetea flag de alarma apagada  
    ; La hora ya no coincide, resetear bit de alarma apagada  
    ANDI flags, ~(1<<1)        ; Limpiar bit 1 (flag de alarma apagada)  
    RJMP CONTINUAR_VERIFICACION ; Ahora s� verificar la alarma  
   
FIN_VERIFICAR_ALARMA:          ; Fin de la funci�n  
    POP temp2                  ; Restaura registros  
    POP temp   
    RET                        ; Retorno de la funci�n  
    
; FUNCI�N CORREGIDA: Manejo del temporizador con incrementos no deseados corregidos    
TMR0_ISR:                      ; Rutina de interrupci�n de Timer0  
    PUSH temp                  ; Guarda registros en pila  
    IN temp, SREG              ; Guarda registro de estado  
    PUSH temp   
    PUSH temp2   
   
    LDI temp, 0                ; Valor = 0  
    OUT TCNT0, temp            ; Reinicia contador de Timer0  
   
    ; Incrementar contador LED (para parpadeo)  
    LDS temp, led_timer        ; Carga contador de LED  
    INC temp                   ; Incrementa contador  
    STS led_timer, temp        ; Guarda nuevo valor  
   
    CPI temp, 30               ; Compara si lleg� a 30  
    BRNE SKIP_LED              ; Si no es 30, salta  
    LDI temp, 0                ; Reinicia contador  
    STS led_timer, temp        ; Guarda nuevo valor  
   
    ; Toggle flag de parpadeo   
    LDI temp, 0x01             ; Bit 0 (flag de parpadeo)  
    EOR flags, temp            ; Alterna el bit  

    CPI modo, 2                ; Compara con modo 2 (config hora)  
    BRNE CHECK_LED_MODO_3      ; Si no es modo 2, verifica modo 3  
    ; Parpadear PB4 (LED hora)  
    IN temp, PORTB             ; Lee estado actual de PORTB  
    LDI temp2, (1<<PB4)        ; M�scara para PB4  
    EOR temp, temp2            ; Invierte estado de PB4  
    OUT PORTB, temp            ; Actualiza PORTB  
    RJMP SKIP_LED              ; Salta a siguiente secci�n  
   
CHECK_LED_MODO_3:              ; Verificaci�n para modo 3  
    CPI modo, 3                ; Compara con modo 3 (config fecha)  
    BRNE CHECK_LED_MODO_4      ; Si no es modo 3, verifica modo 4  
    ; Parpadear PC4 (LED fecha)  
    IN temp, PORTC             ; Lee estado actual de PORTC  
    LDI temp2, (1<<PC4)        ; M�scara para PC4  
    EOR temp, temp2            ; Invierte estado de PC4  
    OUT PORTC, temp            ; Actualiza PORTC  
    RJMP SKIP_LED              ; Salta a siguiente secci�n  

CHECK_LED_MODO_4:              ; Verificaci�n para modo 4  
    CPI modo, 4                ; Compara con modo 4 (config alarma)  
    BRNE SKIP_LED              ; Si no es modo 4, salta  
    ; Parpadear PB4 (LED hora)  
    IN temp, PORTB             ; Lee estado actual de PORTB  
    LDI temp2, (1<<PB4)        ; M�scara para PB4  
    EOR temp, temp2            ; Invierte estado de PB4  
    OUT PORTB, temp            ; Actualiza PORTB  
   
SKIP_LED:                      ; Contin�a rutina de timer  
    ; Incrementar contador principal     
    LDS temp, contador         ; Carga contador principal  
    INC temp                   ; Incrementa contador  
    STS contador, temp         ; Guarda nuevo valor  
    CPI temp, 61               ; Compara si lleg� a 61 (aprox. 1 segundo)  
    BRNE CHECK_ALARMA_ACTIVA   ; Si no es 61, verifica alarma  
      
    LDI temp, 0                ; Reinicia contador  
    STS contador, temp         ; Guarda nuevo valor  
      
    ; Solo incrementar tiempo si NO estamos en modo configuraci�n    
    ; PUNTO CR�TICO: Verificar expl�citamente los modos   
    CPI modo, 0                ; Compara con modo 0 (reloj)  
    BRNE CHECK_MODO_FECHA_AUTO ; Si no es modo 0, verifica modo 1  
    ; Si modo = 0 (reloj), incrementar tiempo    
    CALL INCREMENTAR_TIEMPO    ; Llama funci�n de incremento de tiempo  
    CALL VERIFICAR_ALARMA      ; Verifica si hay que activar la alarma  
    RJMP CHECK_ALARMA_ACTIVA   ; Salta a verificar alarma activa  
      
CHECK_MODO_FECHA_AUTO:         ; Verificaci�n para modo fecha  
    CPI modo, 1                ; Compara con modo 1 (fecha)  
    BRNE CHECK_ALARMA_ACTIVA   ; Si no es modo 0 ni 1, no incrementar  

CHECK_ALARMA_ACTIVA:           ; Verifica si la alarma est� activa  
    ; Verificar si la alarma est� activa  
    LDS temp, alarm_active     ; Carga estado de alarma  
    CPI temp, 1                ; Compara si est� activa (1)  
    BRNE FIN_ISR               ; Si no est� activa, termina  

    ; Incrementar contador de alarma  
    LDS temp, alarm_counter    ; Carga contador de alarma  
    INC temp                   ; Incrementa contador  
    STS alarm_counter, temp    ; Guarda nuevo valor  
    CPI temp, 30               ; Compara si lleg� a 30 segundos  
    BRLO FIN_ISR               ; Si es menor, termina  

    ; Si ha pasado 30 segundos, desactivar alarma  
    LDI temp, 0                ; Valor = 0 (alarma inactiva)  
    STS alarm_active, temp     ; Desactiva alarma  
    STS alarm_counter, temp    ; Reinicia contador  
    CBI PORTB, PB5             ; Apagar LED de alarma  
      
FIN_ISR:                       ; Fin de rutina de interrupci�n  
    POP temp2                  ; Restaura registros  
    POP temp     
    OUT SREG, temp             ; Restaura registro de estado  
    POP temp     
    RETI                       ; Retorno de interrupci�n  
    
; VERSI�N CORREGIDA: Rutina ISR_PCINT0 para incluir PB3    
ISR_PCINT0:                    ; Rutina de interrupci�n para botones  
    PUSH temp                  ; Guarda registros en pila  
    IN temp, SREG              ; Guarda registro de estado  
    PUSH temp     
    PUSH temp2   
    
    ; Verificar bot�n PB0 (modo)     
    SBIC PINB, PB0             ; Verifica si PB0 est� presionado  
    RJMP CHECK_PB1_PRESS       ; Si no est� presionado, verifica PB1  
      
    ; Cambiar modo    
    CALL CAMBIAR_MODO          ; Llama funci�n para cambiar modo  
    RJMP FIN_PCINT0            ; Salta a fin de rutina  
      
CHECK_PB1_PRESS:               ; Verificaci�n para PB1 (incrementar)  
    ; Verificar bot�n PB1 (incrementar)     
    SBIC PINB, PB1             ; Verifica si PB1 est� presionado  
    RJMP CHECK_PB2_PRESS       ; Si no est� presionado, verifica PB2  
      
    ; Acci�n seg�n modo (incrementar)    
    CPI modo, 2                ; Compara si modo >= 2 (configuraci�n)  
    BRLO FIN_PCINT0            ; Si modo < 2, ignorar  
      
    ; En modo configuraci�n, manejar botones a trav�s de las funciones espec�ficas    
    CALL BOTON_HORAS           ; Llama funci�n para bot�n horas  
    CALL BOTON_MINUTOS         ; Llama funci�n para bot�n minutos  
    RJMP FIN_PCINT0            ; Salta a fin de rutina  
      
CHECK_PB2_PRESS:               ; Verificaci�n para PB2 (decrementar)  
    ; Verificar bot�n PB2 (decrementar)      
    SBIC PINB, PB2             ; Verifica si PB2 est� presionado  
    RJMP CHECK_PB3_PRESS       ; Si no est� presionado, verifica PB3  

    ; NUEVA FUNCIONALIDAD: Verificar si estamos en modo hora (MODO=0) y la alarma est� activa  
    CPI modo, 0                ; Compara con modo 0 (reloj)  
    BRNE CHECK_MODO_CONFIG     ; Si no estamos en modo hora, verificar config  
    
    ; Estamos en modo hora, verificar si la alarma est� activa  
    LDS temp, alarm_active     ; Carga estado de alarma  
    CPI temp, 1                ; Compara si est� activa (1)  
    BRNE CHECK_MODO_CONFIG     ; Si la alarma no est� activa, verifica config  
    
    ; La alarma est� activa y estamos en modo hora, apagar la alarma  
    LDI temp, 0                ; Valor = 0 (alarma inactiva)  
    STS alarm_active, temp     ; Desactiva alarma  
    STS alarm_counter, temp    ; Reinicia contador  
    CBI PORTB, PB5             ; Apagar LED de alarma  
    
    ; Establecer bit 1 de flags para indicar alarma apagada manualmente  
    ORI flags, (1<<1)          ; Establece bit 1 (flag de alarma apagada)  
    
    RJMP FIN_PCINT0            ; Salta a fin de rutina  
      
CHECK_MODO_CONFIG:             ; Verificaci�n para modos de configuraci�n  
    ; Acci�n seg�n modo (decrementar)     
    CPI modo, 2                ; Compara si modo >= 2 (configuraci�n)  
    BRLO FIN_PCINT0            ; Si modo < 2, ignorar  
       
    ; En modo configuraci�n, manejar botones a trav�s de las funciones espec�ficas     
    CALL BOTON_HORAS           ; Llama funci�n para bot�n horas  
    CALL BOTON_MINUTOS         ; Llama funci�n para bot�n minutos  
    RJMP FIN_PCINT0            ; Salta a fin de rutina  

CHECK_PB3_PRESS:               ; Verificaci�n para PB3 (cambiar selecci�n)  
    ; Verificar bot�n PB3 (cambiar selecci�n)    
    SBIC PINB, PB3             ; Verifica si PB3 est� presionado  
    RJMP FIN_PCINT0            ; Si no est� presionado, termina  
      
    ; Solo cambiar selecci�n si estamos en modo configuraci�n    
    CPI modo, 2                ; Compara si modo >= 2 (configuraci�n)  
    BRLO FIN_PCINT0            ; Si modo < 2, ignorar  
  
    ; Cambiar entre hora/minutos o d�a/mes    
    CALL CAMBIAR_CONFIG_SEL    ; Alterna entre configurar hora/d�a (1) o minutos/mes (0)  
      
FIN_PCINT0:                    ; Fin de rutina de interrupci�n  
    POP temp2                  ; Restaura registros  
    POP temp   
    OUT SREG, temp             ; Restaura registro de estado  
    POP temp     
    RETI                       ; Retorno de interrupci�n  
   
; Funci�n para cambiar el modo (separada para mejor organizaci�n)     
CAMBIAR_MODO:                  ; Funci�n para cambiar el modo del reloj  
    ; Cambiar modo     
    INC modo                   ; Incrementa modo  
    CPI modo, 5                ; Compara si lleg� a 5  
    BRNE ACTUALIZAR_MODO_CAMBIO ; Si no es 5, actualiza LEDs  
    CLR modo                   ; Si es 5, reinicia a modo 0  
      
ACTUALIZAR_MODO_CAMBIO:        ; Actualiza LEDs seg�n nuevo modo  
    ; Resetear selecci�n a 1 (horas o d�as) cuando cambia el modo    
    LDI temp, 1                ; Valor = 1 (configura horas/d�as)  
    MOV config_sel, temp       ; Actualiza selector  
      
    CALL ACTUALIZAR_LEDS_MODO  ; Actualiza LEDs indicadores  
    RET                        ; Retorno de la funci�n  