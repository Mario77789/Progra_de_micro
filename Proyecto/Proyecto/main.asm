;************************************************************      
; Universidad del Valle de Guatemala      
; IE2023: Programación de Microcontroladores      
;      
; Reloj Digital con 4 displays (horas:minutos)      
; Multiplexación en PC0-PC3 (cambiado de PB0-PB3)      
; Botones en PB0-PB3 (cambiado de PC0-PC2)      
; LEDs indicadores en PB4, PC4, PC5 y PB5 (alarma)      
;************************************************************      
.include "m328Pdef.inc"      ; Incluye definiciones para ATmega328P  
.cseg                        ; Inicia segmento de código  
.org 0x0000                  ; Dirección de inicio del programa  
    
JMP START                    ; Vector de reset: Salta a inicialización  
.org OVF0addr                ; Vector de interrupción por desbordamiento del Timer0  
    
JMP TMR0_ISR                 ; Salta a la rutina de servicio del Timer0  
.org 0x0006                  ; Vector de interrupción PCINT0 (para botones)  
    
JMP ISR_PCINT0               ; Salta a la rutina de servicio de interrupción de botones  
        
; Tabla de valores para display de 7 segmentos      
.org 0x0030                  ; Dirección segura para el resto del código      
DISPLAY:                     ; Etiqueta para tabla de valores de display  
    
.db 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F  ; Códigos para dígitos 0-9  

; Definición de registros - Asigna nombres a registros para mejor legibilidad    
.def temp = r16              ; Registro temporal para operaciones generales  
.def flags = r23             ; Registro para flags (bit 0: parpadeo, bit 1: alarma activa)      
.def temp2 = r18             ; Registro temporal adicional    
.def modo = r19              ; Registro para modo de operación  
.def config_sel = r17        ; Registro para selección de configuración    
                             ; 0 = minutos/meses, 1 = horas/días    
.def resto = r22             ; Registro para almacenar restos en divisiones    
; Modos de operación:  
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
dia_u:       .byte 1         ; Unidades de día      
dia_d:       .byte 1         ; Decenas de día  
mes_u:       .byte 1         ; Unidades de mes    
mes_d:       .byte 1         ; Decenas de mes   
alarm_min_u: .byte 1         ; Unidades de minutos de alarma   
alarm_min_d: .byte 1         ; Decenas de minutos de alarma   
alarm_hr_u:  .byte 1         ; Unidades de horas de alarma   
alarm_hr_d:  .byte 1         ; Decenas de horas de alarma   
alarm_active:.byte 1         ; Flag para indicar si la alarma está sonando   
alarm_counter:.byte 1        ; Contador para duración de alarma (30 segundos)   
   
.cseg                        ; Vuelve al segmento de código  
    
START:                       ; Punto de entrada principal del programa  
    LDI temp, LOW(RAMEND)    ; Carga el byte bajo de la dirección final de RAM     
    OUT SPL, temp            ; Inicializa puntero de pila (byte bajo)  
    LDI temp, HIGH(RAMEND)   ; Carga el byte alto de la dirección final de RAM    
    OUT SPH, temp            ; Inicializa puntero de pila (byte alto)  
SETUP:                       ; Configuración inicial del sistema  
    CLI                      ; Deshabilita interrupciones durante configuración  
   
    ; Configuración del prescaler del reloj      
    LDI temp, (1<<CS02)|(1<<CS00) ; Prescaler de 1024 para Timer0    
    OUT TCCR0B, temp         ; Configura el Timer0 con prescaler  
    LDI temp, 0              ; Valor inicial para timer = 0  
    OUT TCNT0, temp          ; Inicializa el contador del Timer0  
   
    ; Habilitar interrupción de Timer0  
    LDI temp, (1<<TOIE0)     ; Habilita interrupción por desbordamiento de Timer0  
    STS TIMSK0, temp         ; Guarda configuración en registro TIMSK0  
   
    ; Configuración de puertos      
    ; PORTB: PB0-PB3 como entradas (botones), PB4 y PB5 como salidas (LED modo hora y alarma)      
    LDI temp, (1<<PB4)|(1<<PB5) ; PB4 y PB5 como salidas      
    OUT DDRB, temp           ; Configura dirección de PORTB  
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
     
    ; Configuración de interrupciones pin change para PORTB (botones)      
    LDI temp, (1<<PCIE0)     ; Habilitar grupo PCINT0 (PORTB)  
    STS PCICR, temp          ; Configura interrupción de cambio de pin  
    LDI temp, (1<<PCINT0)|(1<<PCINT1)|(1<<PCINT2)|(1<<PCINT3) ; Habilita pines específicos  
    STS PCMSK0, temp         ; Configura máscara para PCINT0-3 (PB0-PB3)  

    ; Inicialización de variables - Establece valores iniciales     
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
    STS dia_u, temp          ; Unidades de día = 1  
    LDI temp, 0              ; Valor = 0  
    STS dia_d, temp          ; Decenas de día = 0 (día 01)  
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
    
    ; Inicializar config_sel en 1 (por defecto configurando horas/días)    
    LDI temp, 1              ; Valor = 1 (configura horas/días)  
    MOV config_sel, temp     ; Inicializa selector de configuración  
   
    ; Inicializar LEDs indicadores de modo  
    SBI PORTB, PB4           ; Enciende LED de modo hora (PB4)  
    CBI PORTC, PC4           ; Apaga LED de modo fecha (PC4)  
    CBI PORTC, PC5           ; Apaga LED de modo configuración (PC5)  
    CBI PORTB, PB5           ; Apaga LED de alarma (PB5)  
   
    SEI                      ; Habilita interrupciones globales  
MAIN_LOOP:                   ; Bucle principal del programa  
    CALL MOSTRAR_DISPLAYS    ; Actualiza los displays según el modo actual  
    RJMP MAIN_LOOP           ; Bucle infinito  
   
ACTUALIZAR_LEDS_MODO:        ; Actualiza LEDs según el modo actual  
    PUSH temp                ; Guarda registro temporal en pila  
    PUSH temp2               ; Guarda segundo registro temporal  
    ; Apagar todos los LEDs primero   
    CBI PORTB, PB4           ; Apaga LED en PB4 (modo hora)  
    CBI PORTC, PC4           ; Apaga LED en PC4 (modo fecha)  
    CBI PORTC, PC5           ; Apaga LED en PC5 (configuración)  
   
    CPI modo, 0              ; Compara modo con 0  
    BRNE CHECK_MODO_1        ; Si no es igual, verifica el siguiente modo  
    SBI PORTB, PB4           ; Modo 0: Enciende LED de hora (PB4)  
    RJMP SET_LEDS            ; Salta a fin de la función  
   
CHECK_MODO_1:                ; Verificación para modo 1  
    CPI modo, 1              ; Compara modo con 1  
    BRNE CHECK_MODO_2        ; Si no es igual, verifica el siguiente modo  
    SBI PORTC, PC4           ; Modo 1: Enciende LED de fecha (PC4)  
    RJMP SET_LEDS            ; Salta a fin de la función  
   
CHECK_MODO_2:                ; Verificación para modo 2  
    CPI modo, 2              ; Compara modo con 2  
    BRNE CHECK_MODO_3        ; Si no es igual, verifica el siguiente modo  
    SBI PORTB, PB4           ; Modo 2: Enciende LED hora (parpadea en TMR0_ISR)  
    SBI PORTC, PC5           ; Enciende LED configuración (fijo)  
    RJMP SET_LEDS            ; Salta a fin de la función  
   
CHECK_MODO_3:                ; Verificación para modo 3  
    CPI modo, 3              ; Compara modo con 3  
    BRNE CHECK_MODO_4        ; Si no es igual, verifica el siguiente modo  
    SBI PORTC, PC4           ; Modo 3: Enciende LED fecha (parpadea en TMR0_ISR)  
    SBI PORTC, PC5           ; Enciende LED configuración (fijo)  
    RJMP SET_LEDS            ; Salta a fin de la función  

CHECK_MODO_4:                ; Verificación para modo 4  
    CPI modo, 4              ; Compara modo con 4  
    BRNE SET_LEDS            ; Si no es igual, termina función  
    SBI PORTB, PB4           ; Modo 4: Enciende LED hora (parpadea en TMR0_ISR)  
    ; PC5 se mantiene apagado  
   
SET_LEDS:                    ; Fin de la función  
    POP temp2                ; Recupera registro temp2 de la pila  
    POP temp                 ; Recupera registro temp de la pila  
    RET                      ; Retorno de la función  
   
MOSTRAR_DISPLAYS:            ; Función para mostrar displays según el modo  
    CPI modo, 1              ; Verifica si estamos en modo 1 (fecha)  
    BRNE CHECK_MODO_2_DISPLAY ; Si no, verifica siguiente modo  
    JMP MOSTRAR_FECHA        ; Salta a mostrar fecha (JMP por lejanía)  
   
CHECK_MODO_2_DISPLAY:        ; Verificación para modo 2  
    CPI modo, 2              ; Verifica si estamos en modo 2 (config hora)  
    BRNE CHECK_MODO_3_DISPLAY ; Si no, verifica siguiente modo  
    JMP MOSTRAR_CONFIG_HORA  ; Salta a mostrar configuración de hora  
   
CHECK_MODO_3_DISPLAY:        ; Verificación para modo 3  
    CPI modo, 3              ; Verifica si estamos en modo 3 (config fecha)  
    BRNE CHECK_MODO_4_DISPLAY ; Si no, verifica siguiente modo  
    JMP MOSTRAR_CONFIG_FECHA ; Salta a mostrar configuración de fecha  

CHECK_MODO_4_DISPLAY:        ; Verificación para modo 4  
    CPI modo, 4              ; Verifica si estamos en modo 4 (config alarma)  
    BRNE MOSTRAR_RELOJ       ; Si no, muestra reloj (modo por defecto)  
    JMP MOSTRAR_CONFIG_ALARMA ; Salta a mostrar configuración de alarma  
   
MOSTRAR_RELOJ:               ; Función para mostrar la hora actual  
    ; Display 4 (PC3) - Decenas de horas     
    CALL APAGAR_DISPLAYS     ; Apaga todos los displays para multiplexación  
   
    LDI ZL, LOW(DISPLAY*2)   ; Carga dirección baja de tabla DISPLAY (x2 por flash)  
    LDI ZH, HIGH(DISPLAY*2)  ; Carga dirección alta de tabla DISPLAY  
    LDS temp, cont_hr_d      ; Carga valor de decenas de hora  
    ADD ZL, temp             ; Suma offset para acceder al dígito correcto  
    LPM temp, Z              ; Carga patrón del dígito desde memoria de programa  
    OUT PORTD, temp          ; Muestra el patrón en PORTD (segmentos)  
    SBI PORTC, PC3           ; Activa display 4  
    CALL RETARDO             ; Pequeño retardo para visualización  
     
    ; Display 3 (PC2) - Unidades de horas     
    CALL APAGAR_DISPLAYS     ; Apaga displays para mostrar siguiente dígito  
   
    LDI ZL, LOW(DISPLAY*2)   ; Prepara puntero a tabla de display  
    LDI ZH, HIGH(DISPLAY*2)   
    LDS temp, cont_hr_u      ; Carga unidades de hora  
    ADD ZL, temp             ; Calcula dirección en tabla  
    LPM temp, Z              ; Carga patrón del dígito  
    SBRC flags, 0            ; Si bit 0 de flags está a 0, salta siguiente instrucción  
    ORI temp, 0x80           ; Agrega punto decimal (separador horas:minutos)  
    OUT PORTD, temp          ; Muestra patrón en segmentos  
    SBI PORTC, PC2           ; Activa display 3  
    CALL RETARDO             ; Retardo para visualización  
     
    ; Display 2 (PC1) - Decenas de minutos  
    CALL APAGAR_DISPLAYS     ; Apaga displays  
   
    LDI ZL, LOW(DISPLAY*2)   ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, cont_min_d     ; Carga decenas de minutos  
    ADD ZL, temp             ; Calcula dirección en tabla  
    LPM temp, Z              ; Carga patrón del dígito  
    SBRC flags, 0            ; Si bit 0 de flags está a 0, salta  
    ORI temp, 0x80           ; Agrega punto decimal (parpadea con segundos)  
    OUT PORTD, temp          ; Muestra patrón  
    SBI PORTC, PC1           ; Activa display 2  
    CALL RETARDO             ; Retardo  
     
    ; Display 1 (PC0) - Unidades de minutos     
    CALL APAGAR_DISPLAYS     ; Apaga displays  
   
    LDI ZL, LOW(DISPLAY*2)   ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)   
    LDS temp, cont_min_u     ; Carga unidades de minutos  
    ADD ZL, temp             ; Calcula dirección  
    LPM temp, Z              ; Carga patrón  
    OUT PORTD, temp          ; Muestra dígito  
    SBI PORTC, PC0           ; Activa display 1  
    CALL RETARDO             ; Retardo  
    RET                      ; Retorno de función  

MOSTRAR_FECHA:               ; Función para mostrar la fecha actual  
    ; Display 4 (PC3) - Decenas de día     
    CALL APAGAR_DISPLAYS     ; Apaga displays  
   
    LDI ZL, LOW(DISPLAY*2)   ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, dia_d          ; Carga decenas de día  
    ADD ZL, temp             ; Calcula dirección  
    LPM temp, Z              ; Carga patrón  
    OUT PORTD, temp          ; Muestra dígito  
    SBI PORTC, PC3           ; Activa display 4  
    CALL RETARDO             ; Retardo  
     
    ; Display 3 (PC2) - Unidades de día     
    CALL APAGAR_DISPLAYS     ; Apaga displays  
     
    LDI ZL, LOW(DISPLAY*2)   ; Prepara puntero  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, dia_u          ; Carga unidades de día  
    ADD ZL, temp             ; Calcula dirección  
    LPM temp, Z              ; Carga patrón  
    ORI temp, 0x80           ; Agrega punto decimal (separador día/mes)  
    OUT PORTD, temp          ; Muestra dígito  
    SBI PORTC, PC2           ; Activa display 3  
    CALL RETARDO             ; Retardo  

    ; Display 2 (PC1) - Decenas de mes    
    CALL APAGAR_DISPLAYS     ; Apaga displays  
     
    LDI ZL, LOW(DISPLAY*2)   ; Prepara puntero  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, mes_d          ; Carga decenas de mes  
    ADD ZL, temp             ; Calcula dirección  
    LPM temp, Z              ; Carga patrón  
    OUT PORTD, temp          ; Muestra dígito  
    SBI PORTC, PC1           ; Activa display 2  
    CALL RETARDO             ; Retardo  
     
    ; Display 1 (PC0) - Unidades de mes   
    CALL APAGAR_DISPLAYS     ; Apaga displays  
     
    LDI ZL, LOW(DISPLAY*2)   ; Prepara puntero  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, mes_u          ; Carga unidades de mes  
    ADD ZL, temp             ; Calcula dirección  
    LPM temp, Z              ; Carga patrón  
    OUT PORTD, temp          ; Muestra dígito  
    SBI PORTC, PC0           ; Activa display 1  
    CALL RETARDO             ; Retardo  
    RET                      ; Retorno de función  
   
MOSTRAR_CONFIG_HORA:         ; Función para mostrar configuración de hora con parpadeo  
    ; Display 4 (PC3) - Decenas de horas     
    CALL APAGAR_DISPLAYS     ; Apaga displays  
   
    LDI ZL, LOW(DISPLAY*2)   ; Prepara puntero  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, cont_hr_d      ; Carga decenas de hora  
    ADD ZL, temp             ; Calcula dirección  
    LPM temp, Z              ; Carga patrón  
    
    ; Si config_sel = 1 (configurando horas) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 1        ; Compara selector con 1 (configurando horas)  
    BRNE NO_BLINK_HR_D       ; Si no configura horas, no parpadea  
    SBRC flags, 0            ; Si bit de parpadeo está a 0, salta  
    CLR temp                 ; Apaga segmento para efecto de parpadeo    
NO_BLINK_HR_D:               ; Etiqueta de salto si no parpadea  
    OUT PORTD, temp          ; Muestra patrón (normal o apagado)  
    SBI PORTC, PC3           ; Activa display 4  
    CALL RETARDO             ; Retardo  
     
    ; Display 3 (PC2) - Unidades de horas   
    CALL APAGAR_DISPLAYS     ; Apaga displays  
     
    LDI ZL, LOW(DISPLAY*2)   ; Prepara puntero  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, cont_hr_u      ; Carga unidades de hora  
    ADD ZL, temp             ; Calcula dirección  
    LPM temp, Z              ; Carga patrón  
     
    ; Si config_sel = 1 (configurando horas) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 1        ; Compara selector  
    BRNE ADD_DOT_HR          ; Si no configura horas, agrega punto sin parpadeo  
    SBRC flags, 0            ; Si bit de parpadeo está a 0, salta  
    CLR temp                 ; Apaga segmento para parpadeo  
ADD_DOT_HR:                  ; Etiqueta para agregar punto decimal  
     
    ; Añadir punto decimal siempre     
    ORI temp, 0x80           ; Agrega punto (separador horas:minutos)  
    OUT PORTD, temp          ; Muestra patrón  
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
    OUT PORTD, temp            ; Saca el patrón del dígito a los segmentos del display  
    SBI PORTC, PC1             ; Activa el display 2 (PC1)  
    CALL RETARDO               ; Pequeña pausa para visualización  
     
    ; Display 1 (PC0) - Unidades de minutos     
    CALL APAGAR_DISPLAYS       ; Apaga todos los displays para multiplexación  
     
    LDI ZL, LOW(DISPLAY*2)     ; Carga dirección baja de tabla de dígitos  
    LDI ZH, HIGH(DISPLAY*2)    ; Carga dirección alta de tabla  
    LDS temp, cont_min_u       ; Carga valor de unidades de minutos  
    ADD ZL, temp               ; Calcula dirección del dígito en tabla  
    LPM temp, Z                ; Carga patrón del dígito de memoria de programa  
    
    ; Si config_sel = 0 (configurando minutos) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 0          ; Compara selector con 0 (configurando minutos)  
    BRNE NO_BLINK_MIN_U        ; Si no estamos configurando minutos, salta  
    SBRC flags, 0              ; Si bit de parpadeo está a 0, salta  
    CLR temp                   ; Apaga todos los segmentos para efecto de parpadeo  
NO_BLINK_MIN_U:                ; Etiqueta para saltar si no se aplica parpadeo  
    OUT PORTD, temp            ; Muestra el dígito en los segmentos  
    SBI PORTC, PC0             ; Activa el display 1 (PC0)  
    CALL RETARDO               ; Pequeña pausa para visualización  
    RET                        ; Retorno de la función  
   
MOSTRAR_CONFIG_FECHA:          ; Función para mostrar y configurar fecha  
    ; Display 4 (PC3) - Decenas de día     
    CALL APAGAR_DISPLAYS       ; Apaga todos los displays  
     
    LDI ZL, LOW(DISPLAY*2)     ; Prepara puntero a tabla de dígitos  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, dia_d            ; Carga decenas de día  
    ADD ZL, temp               ; Calcula dirección en tabla  
    LPM temp, Z                ; Carga patrón del dígito  
    
    ; Si config_sel = 1 (configurando días) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 1          ; Compara selector con 1 (configurando días)  
    BRNE NO_BLINK_DIA_D        ; Si no estamos configurando días, salta  
    SBRC flags, 0              ; Si bit de parpadeo está a 0, salta  
    CLR temp                   ; Apaga segmentos para efecto de parpadeo  
NO_BLINK_DIA_D:                ; Etiqueta para saltar si no se aplica parpadeo  
    OUT PORTD, temp            ; Muestra el dígito  
    SBI PORTC, PC3             ; Activa display 4  
    CALL RETARDO               ; Pequeña pausa  
     
    ; Display 3 (PC2) - Unidades de día     
    CALL APAGAR_DISPLAYS       ; Apaga todos los displays  
    LDI ZL, LOW(DISPLAY*2)     ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, dia_u            ; Carga unidades de día  
    ADD ZL, temp               ; Calcula dirección  
    LPM temp, Z                ; Carga patrón  
    
    ; Si config_sel = 1 (configurando días) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 1          ; Compara selector con 1 (configurando días)  
    BRNE ADD_DOT_DIA           ; Si no configuramos días, salta a añadir punto  
    SBRC flags, 0              ; Si bit de parpadeo está a 0, salta  
    LDI temp, 0x80             ; Carga SOLO punto decimal (parpadea dígito pero no el punto)  
ADD_DOT_DIA:                   ; Etiqueta para añadir punto decimal  
    
    ; Añadir punto decimal siempre    
    ORI temp, 0x80             ; Añade punto decimal (separador día/mes)  
    OUT PORTD, temp            ; Muestra dígito con punto  
    SBI PORTC, PC2             ; Activa display 3  
    CALL RETARDO               ; Pequeña pausa  
     
    ; Display 2 (PC1) - Decenas de mes     
    CALL APAGAR_DISPLAYS       ; Apaga todos los displays  
     
    LDI ZL, LOW(DISPLAY*2)     ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, mes_d            ; Carga decenas de mes  
    ADD ZL, temp               ; Calcula dirección  
    LPM temp, Z                ; Carga patrón  
    
    ; Si config_sel = 0 (configurando meses) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 0          ; Compara selector con 0 (configurando meses)  
    BRNE NO_BLINK_MES_D        ; Si no configuramos meses, salta  
    SBRC flags, 0              ; Si bit de parpadeo está a 0, salta  
    CLR temp                   ; Apaga segmentos para efecto de parpadeo  
NO_BLINK_MES_D:                ; Etiqueta para saltar si no se aplica parpadeo  
    OUT PORTD, temp            ; Muestra dígito  
    SBI PORTC, PC1             ; Activa display 2  
    CALL RETARDO               ; Pequeña pausa  
     
    ; Display 1 (PC0) - Unidades de mes     
    CALL APAGAR_DISPLAYS       ; Apaga todos los displays  
     
    LDI ZL, LOW(DISPLAY*2)     ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, mes_u            ; Carga unidades de mes  
    ADD ZL, temp               ; Calcula dirección  
    LPM temp, Z                ; Carga patrón  
    
    ; Si config_sel = 0 (configurando meses) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 0          ; Compara selector con 0 (configurando meses)  
    BRNE NO_BLINK_MES_U        ; Si no configuramos meses, salta  
    SBRC flags, 0              ; Si bit de parpadeo está a 0, salta  
    CLR temp                   ; Apaga segmentos para efecto de parpadeo  
NO_BLINK_MES_U:                ; Etiqueta para saltar si no se aplica parpadeo  
    OUT PORTD, temp            ; Muestra dígito  
    SBI PORTC, PC0             ; Activa display 1  
    CALL RETARDO               ; Pequeña pausa  
    RET                        ; Retorno de la función  

; Función para mostrar la configuración de alarma  
MOSTRAR_CONFIG_ALARMA:         ; Función para configurar la alarma  
    ; Display 4 (PC3) - Decenas de horas de alarma     
    CALL APAGAR_DISPLAYS       ; Apaga todos los displays  
    LDI ZL, LOW(DISPLAY*2)     ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, alarm_hr_d       ; Carga decenas de horas de alarma  
    ADD ZL, temp               ; Calcula dirección  
    LPM temp, Z                ; Carga patrón  
    
    ; Si config_sel = 1 (configurando horas) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 1          ; Compara selector con 1 (configurando horas)  
    BRNE NO_BLINK_ALARM_HR_D   ; Si no configuramos horas, salta  
    SBRC flags, 0              ; Si bit de parpadeo está a 0, salta  
    CLR temp                   ; Apaga segmentos para efecto de parpadeo  
NO_BLINK_ALARM_HR_D:           ; Etiqueta para saltar si no se aplica parpadeo  
    OUT PORTD, temp            ; Muestra dígito  
    SBI PORTC, PC3             ; Activa display 4  
    CALL RETARDO               ; Pequeña pausa  
     
    ; Display 3 (PC2) - Unidades de horas de alarma   
    CALL APAGAR_DISPLAYS       ; Apaga todos los displays  
     
    LDI ZL, LOW(DISPLAY*2)     ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, alarm_hr_u       ; Carga unidades de horas de alarma  
    ADD ZL, temp               ; Calcula dirección  
    LPM temp, Z                ; Carga patrón  
     
    ; Si config_sel = 1 (configurando horas) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 1          ; Compara selector con 1 (configurando horas)  
    BRNE ADD_DOT_ALARM_HR      ; Si no configuramos horas, salta a añadir punto  
    SBRC flags, 0              ; Si bit de parpadeo está a 0, salta  
    CLR temp                   ; Apaga segmentos para efecto de parpadeo  
ADD_DOT_ALARM_HR:              ; Etiqueta para añadir punto decimal  
    
    ; Añadir punto decimal siempre    
    ORI temp, 0x80             ; Añade punto decimal (separador horas:minutos)  
    OUT PORTD, temp            ; Muestra dígito con punto  
    SBI PORTC, PC2             ; Activa display 3  
    CALL RETARDO               ; Pequeña pausa  
     
    ; Display 2 (PC1) - Decenas de minutos de alarma     
    CALL APAGAR_DISPLAYS       ; Apaga todos los displays  
     
    LDI ZL, LOW(DISPLAY*2)     ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, alarm_min_d      ; Carga decenas de minutos de alarma  
    ADD ZL, temp               ; Calcula dirección  
    LPM temp, Z                ; Carga patrón  
    
    ; Si config_sel = 0 (configurando minutos) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 0          ; Compara selector con 0 (configurando minutos)  
    BRNE NO_BLINK_ALARM_MIN_D  ; Si no configuramos minutos, salta  
    SBRC flags, 0              ; Si bit de parpadeo está a 0, salta  
    CLR temp                   ; Apaga segmentos para efecto de parpadeo  
NO_BLINK_ALARM_MIN_D:          ; Etiqueta para saltar si no se aplica parpadeo  
    OUT PORTD, temp            ; Muestra dígito  
    SBI PORTC, PC1             ; Activa display 2  
    CALL RETARDO               ; Pequeña pausa  
     
    ; Display 1 (PC0) - Unidades de minutos de alarma     
    CALL APAGAR_DISPLAYS       ; Apaga todos los displays  
     
    LDI ZL, LOW(DISPLAY*2)     ; Prepara puntero a tabla  
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, alarm_min_u      ; Carga unidades de minutos de alarma  
    ADD ZL, temp               ; Calcula dirección  
    LPM temp, Z                ; Carga patrón  
    
    ; Si config_sel = 0 (configurando minutos) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 0          ; Compara selector con 0 (configurando minutos)  
    BRNE NO_BLINK_ALARM_MIN_U  ; Si no configuramos minutos, salta  
    SBRC flags, 0              ; Si bit de parpadeo está a 0, salta  
    CLR temp                   ; Apaga segmentos para efecto de parpadeo  
NO_BLINK_ALARM_MIN_U:          ; Etiqueta para saltar si no se aplica parpadeo  
    OUT PORTD, temp            ; Muestra dígito  
    SBI PORTC, PC0             ; Activa display 1  
    CALL RETARDO               ; Pequeña pausa  
    RET                        ; Retorno de la función  
   
APAGAR_DISPLAYS:               ; Función para apagar todos los displays (multiplexación)  
    CBI PORTC, PC0             ; Apaga display 1  
    CBI PORTC, PC1             ; Apaga display 2  
    CBI PORTC, PC2             ; Apaga display 3  
    CBI PORTC, PC3             ; Apaga display 4  
    RET                        ; Retorno de la función  
   
RETARDO:                       ; Función de retardo para multiplexación  
    PUSH r17                   ; Guarda r17 en la pila  
    LDI r17, 10                ; Carga valor inicial para retardo  
LOOP_RETARDO:                  ; Bucle de retardo  
    DEC r17                    ; Decrementa contador  
    BRNE LOOP_RETARDO          ; Si no es cero, continúa el bucle  
    POP r17                    ; Recupera r17 de la pila  
    RET                        ; Retorno de la función  
   
; Función corregida para incrementar el tiempo correctamente     
INCREMENTAR_TIEMPO:            ; Función para avanzar el tiempo (cada segundo)  
    ; Incrementar segundos (no se muestran)     
    LDS temp, cont_sec         ; Carga contador de segundos  
    INC temp                   ; Incrementa segundos  
    CPI temp, 60               ; Compara si llegó a 60  
    BRNE GUARDAR_SEC           ; Si no es 60, guarda y termina  
   
    ; Si segundos llega a 60, reiniciar y incrementar minutos     
    LDI temp, 0                ; Reinicia segundos a 0  
    STS cont_sec, temp         ; Guarda valor  
   
    ; Incrementar unidades de minutos     
    LDS temp, cont_min_u       ; Carga unidades de minutos  
    INC temp                   ; Incrementa  
    CPI temp, 10               ; Compara si llegó a 10  
    BRNE GUARDAR_MIN_U         ; Si no es 10, guarda y termina  
   
    ; Si unidades de minutos llega a 10, reiniciar e incrementar decenas     
    LDI temp, 0                ; Reinicia unidades de minutos a 0  
    STS cont_min_u, temp       ; Guarda valor  
   
    ; Incrementar decenas de minutos   
    LDS temp, cont_min_d       ; Carga decenas de minutos  
    INC temp                   ; Incrementa  
    CPI temp, 6                ; Compara si llegó a 6 (60 minutos)  
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
    BRNE CHECK_HR_U_NORMAL     ; Si no es 2, verificación normal  
    CPI temp, 4                ; Compara si unidades llegó a 4 (24 horas)  
    BRNE CHECK_HR_U_NORMAL     ; Si no es 4, verificación normal  
   
    ; Si llegamos a 24 horas, reiniciar a 00:00 e incrementar día     
    LDI temp, 0                ; Reinicia unidades de horas a 0  
    STS cont_hr_u, temp        ; Guarda valor  
    LDI temp, 0                ; Reinicia decenas de horas a 0  
    STS cont_hr_d, temp        ; Guarda valor  
   
    ; Incrementar día - ASEGURARNOS DE QUE ESTO SE EJECUTE     
    PUSH temp                  ; Guarda registros en pila para preservar valores  
    PUSH temp2     
    CALL INCREMENTAR_DIA_AUTOMATICO ; Llama a subrutina para incrementar día  
    POP temp2                  ; Recupera registros de pila  
    POP temp     
    RET                        ; Retorno de la función  
   
CHECK_HR_U_NORMAL:             ; Verificación normal de horas  
    ; Verificar si unidades de hora llega a 10     
    CPI temp, 10               ; Compara si unidades de hora llegó a 10  
    BRNE GUARDAR_HR_U          ; Si no es 10, guarda y termina  
   
    ; Si unidades de hora llega a 10, reiniciar e incrementar decenas     
    LDI temp, 0                ; Reinicia unidades de hora a 0  
    STS cont_hr_u, temp        ; Guarda valor  
   
    ; Incrementar decenas de horas     
    LDS temp, cont_hr_d        ; Carga decenas de horas  
    INC temp                   ; Incrementa  
    STS cont_hr_d, temp        ; Guarda valor  
    RET                        ; Retorno de la función  
   
GUARDAR_HR_U:                  ; Rutina para guardar unidades de hora  
    STS cont_hr_u, temp        ; Guarda valor en memoria  
    RET                        ; Retorno de la función  
   
GUARDAR_MIN_D:                 ; Rutina para guardar decenas de minutos  
    STS cont_min_d, temp       ; Guarda valor en memoria  
    RET                        ; Retorno de la función  
  
GUARDAR_MIN_U:                 ; Rutina para guardar unidades de minutos  
    STS cont_min_u, temp       ; Guarda valor en memoria  
    RET                        ; Retorno de la función  
   
GUARDAR_SEC:                   ; Rutina para guardar segundos  
    STS cont_sec, temp         ; Guarda valor en memoria  
    RET                        ; Retorno de la función  
    
; Función para incrementar horas (para botón PB1 en modo incremento)     
INCREMENTAR_HORAS:             ; Función para incrementar horas manualmente  
    ; Incrementar unidades de horas     
    LDS temp, cont_hr_u        ; Carga unidades de horas  
    INC temp                   ; Incrementa  
   
    ; Verificar si estamos en 24 horas (23:59 -> 00:00)     
    LDS temp2, cont_hr_d       ; Carga decenas de horas  
    CPI temp2, 2               ; Compara si decenas es 2  
    BRNE INC_HR_CHECK_U        ; Si no es 2, verificación normal  
    CPI temp, 4                ; Compara si unidades llegó a 4 (24 horas)  
    BRNE INC_HR_CHECK_U        ; Si no es 4, verificación normal  
   
    ; Si llegamos a 24 horas, reiniciar a 00:00     
    LDI temp, 0                ; Reinicia unidades de horas a 0  
    STS cont_hr_u, temp        ; Guarda valor  
    LDI temp, 0                ; Reinicia decenas de horas a 0  
    STS cont_hr_d, temp        ; Guarda valor  
    RET                        ; Retorno de la función  
   
INC_HR_CHECK_U:                ; Verificación normal de unidades de hora  
    ; Verificar si unidades de hora llega a 10     
    CPI temp, 10               ; Compara si unidades llegó a 10  
    BRNE INC_HR_SAVE_U         ; Si no es 10, guarda y termina  
   
    ; Si unidades de hora llega a 10, reiniciar e incrementar decenas     
    LDI temp, 0                ; Reinicia unidades a 0  
    STS cont_hr_u, temp        ; Guarda valor  
   
    ; Incrementar decenas de horas     
    LDS temp, cont_hr_d        ; Carga decenas de horas  
    INC temp                   ; Incrementa  
    STS cont_hr_d, temp        ; Guarda valor  
    RET                        ; Retorno de la función  
INC_HR_SAVE_U:                ; Etiqueta para guardar unidades de hora incrementadas  
    STS cont_hr_u, temp       ; Guarda el valor en la variable de unidades de hora  
    RET                       ; Retorno de la función  
    
; FUNCIÓN CORREGIDA: Decrementar horas (para botón PB2 en modo decremento)    
DECREMENTAR_HORAS:            ; Función para decrementar horas manualmente  
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
    RET                       ; Retorno de la función  
      
DEC_HR_NOT_ZERO_U:            ; Etiqueta para decrementar unidades de hora no cero  
    ; Decrementar unidades de hora    
    DEC temp                  ; Decrementa unidades  
    STS cont_hr_u, temp       ; Guarda el nuevo valor  
    RET                       ; Retorno de la función  

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
    RET                       ; Retorno de la función  
    
; Función para incrementar minutos (para botón PB1 en modo incremento)     
INCREMENTAR_MINUTOS:          ; Función para incrementar minutos manualmente  
    ; Incrementar unidades de minutos     
    LDS temp, cont_min_u      ; Carga unidades de minutos  
    INC temp                  ; Incrementa unidades  
    CPI temp, 10              ; Compara si llegó a 10  
    BRNE INC_MIN_SAVE_U       ; Si no es 10, guarda y termina  
    
    ; Si unidades de minutos llega a 10, reiniciar e incrementar decenas     
    LDI temp, 0               ; Reinicia unidades a 0  
    STS cont_min_u, temp      ; Guarda el valor  
   
    ; Incrementar decenas de minutos     
    LDS temp, cont_min_d      ; Carga decenas de minutos  
    INC temp                  ; Incrementa decenas  
    CPI temp, 6               ; Compara si llegó a 6 (60 minutos)  
    BRNE INC_MIN_SAVE_D       ; Si no es 6, guarda y termina  
   
    ; Si decenas de minutos llega a 6, reiniciar     
    LDI temp, 0               ; Reinicia decenas a 0  

INC_MIN_SAVE_D:               ; Etiqueta para guardar decenas incrementadas  
    STS cont_min_d, temp      ; Guarda el valor en variable de decenas  
    RET                       ; Retorno de la función  
   
INC_MIN_SAVE_U:               ; Etiqueta para guardar unidades incrementadas  
    STS cont_min_u, temp      ; Guarda el valor en variable de unidades  
    RET                       ; Retorno de la función  
    
; FUNCIÓN CORREGIDA: Decrementar minutos (para botón PB2 en modo decremento)    
DECREMENTAR_MINUTOS:          ; Función para decrementar minutos manualmente  
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
    RET                       ; Retorno de la función  

DEC_MIN_NOT_ZERO_U:           ; Etiqueta para decrementar unidades no cero  
    ; Decrementar unidades de minutos    
    DEC temp                  ; Decrementa unidades  
    STS cont_min_u, temp      ; Guarda el nuevo valor  
    RET                       ; Retorno de la función  
      
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
    RET                       ; Retorno de la función  
   
; Función para incrementar el día automáticamente (cuando cambia de 23:59 a 00:00)     
INCREMENTAR_DIA_AUTOMATICO:   ; Función para cambio automático de día  
    PUSH r20                  ; Guarda registros en pila  
    PUSH r21     
    PUSH temp  
    PUSH temp2    
     
    ; Obtener días máximos del mes actual     
    CALL OBTENER_DIAS_MES     ; Obtiene cuántos días tiene el mes actual  
    MOV r21, temp             ; r21 = días máximos del mes  
   
    ; Calcular el día actual (decenas*10 + unidades)     
    LDS r20, dia_d            ; Carga decenas de día  
    LDI temp, 10              ; Base decimal (10)  
   
    ; Multiplicación manual (r20 * 10)     
    CLR temp2                 ; Limpia acumulador  
    MOV resto, r20            ; Contador para multiplicación  
   
MULT_LOOP_DIA_AUTO:           ; Bucle para multiplicar por 10  
    CPI resto, 0              ; Compara si contador llegó a 0  
    BREQ MULT_DONE_DIA_AUTO   ; Si es 0, termina multiplicación  
    ADD temp2, temp           ; Suma 10 al acumulador  
    DEC resto                 ; Decrementa contador  
    RJMP MULT_LOOP_DIA_AUTO   ; Repite bucle  
   
MULT_DONE_DIA_AUTO:           ; Fin de multiplicación  
    ; Añadir unidades     
    LDS r20, dia_u            ; Carga unidades de día  
    ADD temp2, r20            ; temp2 = día completo (decenas*10 + unidades)  
    ; Incrementar día     
    INC temp2                 ; Incrementa el día  
   
    ; Verificar si hemos superado el máximo de días del mes     
    CP temp2, r21             ; Compara con máximo de días  
    BRLO NO_CAMBIO_MES        ; Si es menor, no hay cambio de mes  
    BRNE CAMBIO_MES           ; Si es mayor, cambiar mes  
    RJMP NO_CAMBIO_MES        ; Si es igual, tampoco hay cambio de mes  
   
CAMBIO_MES:                   ; Manejo de cambio de mes  
    ; Si hemos superado el máximo, reiniciar a día 1 e incrementar mes     
    LDI temp, 1               ; Carga 1 para día nuevo  
    STS dia_u, temp           ; Guarda unidades = 1  
    LDI temp, 0               ; Carga 0 para decenas  
    STS dia_d, temp           ; Guarda decenas = 0 (día 01)  
   
    ; Incrementar mes     
    CALL INCREMENTAR_MES_AUTOMATICO  ; Incrementa el mes  
    POP temp2                 ; Restaura registros  
    POP temp     
    POP r21     
    POP r20     
    RET                       ; Retorno de la función  
   
NO_CAMBIO_MES:                ; Sin cambio de mes, sólo actualiza día  
    ; Si no hemos superado el máximo, actualizar día normalmente  
    MOV temp, temp2           ; Copia día incrementado  
    LDI temp2, 10             ; Base decimal (10)  
    CALL DIV                  ; Divide: temp = decenas, resto = unidades  
    STS dia_d, temp           ; Guarda decenas de día  
    MOV temp, resto           ; Copia unidades  
    STS dia_u, temp           ; Guarda unidades de día  
    POP temp2                 ; Restaura registros  
    POP temp     
    POP r21    
    POP r20     
    RET                       ; Retorno de la función  
   
; Función para incrementar el mes automáticamente     
INCREMENTAR_MES_AUTOMATICO:   ; Función para cambio automático de mes  
    PUSH temp                 ; Guarda registros  
    PUSH r20     
   
    ; Incrementar unidades de mes     
    LDS temp, mes_u           ; Carga unidades de mes  
    INC temp                  ; Incrementa unidades  
   
    ; Verificar si llegamos a mes 13     
    LDS r20, mes_d            ; Carga decenas de mes  
    CPI r20, 1                ; Compara si decenas es 1  
    BRNE CHECK_MES_U_AUTO     ; Si no es 1, verificación normal  
    CPI temp, 3               ; Compara si unidades es 3 (mes 13)  
    BRNE CHECK_MES_U_AUTO     ; Si no es 3, verificación normal  
   
    ; Si llegamos a mes 13, reiniciar a mes 1     
    LDI temp, 1               ; Carga 1 para unidades  
    STS mes_u, temp           ; Guarda unidades = 1  
    LDI temp, 0               ; Carga 0 para decenas  
    STS mes_d, temp           ; Guarda decenas = 0 (mes 01)  
   
    ; Verificar si el día actual es válido para el nuevo mes     
    CALL VALIDAR_DIA_ACTUAL   ; Valida que el día sea válido para nuevo mes  
    POP r20                   ; Restaura registros  
    POP temp     
    RET                       ; Retorno de la función  
   
CHECK_MES_U_AUTO:             ; Verificación normal de unidades de mes  
    ; Verificar si unidades de mes llega a 10     
    CPI temp, 10              ; Compara si unidades llegó a 10  
    BRNE SAVE_MES_U_AUTO      ; Si no es 10, guarda y termina  
   
    ; Si unidades de mes llega a 10, reiniciar e incrementar decenas     
    LDI temp, 0               ; Reinicia unidades a 0  
    STS mes_u, temp           ; Guarda el valor  
   
    ; Incrementar decenas de mes     
    LDS temp, mes_d           ; Carga decenas de mes  
    INC temp                  ; Incrementa decenas  
    STS mes_d, temp           ; Guarda el valor  
  
    ; Verificar si el día actual es válido para el nuevo mes     
    CALL VALIDAR_DIA_ACTUAL   ; Valida que el día sea válido  
    POP r20                   ; Restaura registros  
    POP temp     
    RET                       ; Retorno de la función  
   
SAVE_MES_U_AUTO:              ; Guarda unidades de mes incrementadas  
    STS mes_u, temp           ; Guarda unidades de mes  
   
    ; Verificar si el día actual es válido para el nuevo mes     
    CALL VALIDAR_DIA_ACTUAL   ; Valida que el día sea válido  
    POP r20                   ; Restaura registros  
    POP temp     
    RET                       ; Retorno de la función  
   
; Función para obtener el número máximo de días para el mes actual     
OBTENER_DIAS_MES:             ; Función para calcular días del mes actual  
    PUSH r20                  ; Guarda registros  
    PUSH r21    
    PUSH temp2     
   
    ; Calcular el mes actual (decenas*10 + unidades)     
    LDS r20, mes_d            ; Carga decenas de mes  
    LDI r21, 10               ; Base decimal (10)  
  
    ; Multiplicación manual (r20 * 10)     
    CLR temp                  ; Limpia acumulador  
    MOV temp2, r20            ; Contador para multiplicación  
   
MULT_LOOP_MES:                ; Bucle para multiplicar por 10  
    CPI temp2, 0              ; Compara si contador llegó a 0  
    BREQ MULT_DONE_MES        ; Si es 0, termina multiplicación  
    ADD temp, r21             ; Suma 10 al acumulador  
    DEC temp2                 ; Decrementa contador  
    RJMP MULT_LOOP_MES        ; Repite bucle  
   
MULT_DONE_MES:                ; Fin de multiplicación  
    ; Añadir unidades     
    LDS r21, mes_u            ; Carga unidades de mes  
    ADD temp, r21             ; temp = mes completo (decenas*10 + unidades)  
   
    ; Verificar el mes y asignar días     
    CPI temp, 2               ; Verifica si es febrero (mes 2)  
    BRNE CHECK_MES_30         ; Si no es febrero, verifica meses de 30 días  
    LDI temp, 28              ; Febrero tiene 28 días (no considera años bisiestos)  
    RJMP FIN_OBTENER_DIAS     ; Salta a fin de función  
   
CHECK_MES_30:                 ; Verificación de meses con 30 días  
    CPI temp, 4               ; Verifica si es abril (mes 4)  
    BREQ MES_30               ; Si es abril, tiene 30 días  
    CPI temp, 6               ; Verifica si es junio (mes 6)  
    BREQ MES_30               ; Si es junio, tiene 30 días  
    CPI temp, 9               ; Verifica si es septiembre (mes 9)  
    BREQ MES_30               ; Si es septiembre, tiene 30 días  
    CPI temp, 11              ; Verifica si es noviembre (mes 11)  
    BREQ MES_30               ; Si es noviembre, tiene 30 días  
   
    ; Si no es mes de 30 días, asumimos 31 días     
    LDI temp, 31              ; Meses con 31 días (1,3,5,7,8,10,12)  
    RJMP FIN_OBTENER_DIAS     ; Salta a fin de función  
   
MES_30:                       ; Etiqueta para meses con 30 días  
    LDI temp, 30              ; Carga 30 días  
   
FIN_OBTENER_DIAS:             ; Fin de la función  
    POP temp2                 ; Restaura registros  
    POP r21     
    POP r20     
    RET                       ; Retorno con resultado en temp  
   
; Función para validar que el día actual sea válido para el mes actual     
VALIDAR_DIA_ACTUAL:           ; Función para verificar validez del día actual  
    PUSH r20                  ; Guarda registros  
    PUSH r21     
    PUSH temp     
    PUSH temp2  
    
    ; Obtener días máximos del mes actual     
    CALL OBTENER_DIAS_MES     ; Obtiene número máximo de días  
    MOV r21, temp             ; r21 = días máximos  
   
    ; Calcular el día actual (decenas*10 + unidades)    
    LDS r20, dia_d            ; Carga decenas de día  
    LDI temp, 10              ; Base decimal (10)  
   
    ; Multiplicación manual (r20 * 10)     
    CLR temp2                 ; Limpia acumulador  
    MOV temp, r20             ; Contador para multiplicación  
   
MULT_LOOP_DIA:                ; Bucle para multiplicar por 10  
    CPI temp, 0               ; Compara si contador llegó a 0  
    BREQ MULT_DONE_DIA        ; Si es 0, termina multiplicación  
    ADD temp2, temp           ; Suma 10 al acumulador  
    DEC temp                  ; Decrementa contador  
    RJMP MULT_LOOP_DIA        ; Repite bucle  
   
MULT_DONE_DIA:                ; Fin de multiplicación  
    ; Añadir unidades     
    LDS r20, dia_u            ; Carga unidades de día  
    ADD temp2, r20            ; temp2 = día completo (decenas*10 + unidades)  
   
    ; Si el día actual es mayor que el máximo, ajustar al máximo     
    CP temp2, r21             ; Compara con máximo de días  
    BRLO DIA_VALIDO           ; Si es menor, el día es válido  
  
    ; Ajustar al último día del mes     
    MOV temp, r21             ; Copia máximo de días  
   
    ; Calcular decenas y unidades     
    LDI temp2, 10             ; Base decimal (10)  
    CALL DIV                  ; Divide: temp = decenas, resto = unidades  
    STS dia_d, temp           ; Guarda decenas de día  
    MOV temp, resto           ; Copia unidades  
    STS dia_u, temp           ; Guarda unidades de día  
   
DIA_VALIDO:                   ; Etiqueta para día válido  
    POP temp2                 ; Restaura registros  
    POP temp     
    POP r21     
    POP r20     
    RET                       ; Retorno de la función  
   
; Función auxiliar para división - CORREGIDA     
DIV:                          ; Función para división temp / temp2  
    ; Divide temp entre temp2, resultado en temp, resto en resto (r22)     
    PUSH r21                  ; Guarda r21 en pila  
    CLR r21                   ; r21 será nuestro cociente, inicia en 0  
   
DIV_LOOP:                     ; Bucle de división  
    CP temp, temp2            ; Compara temp con temp2  
    BRLO DIV_END              ; Si temp < temp2, termina división  
    SUB temp, temp2           ; temp = temp - temp2 (resta divisor)  
    INC r21                   ; Incrementa cociente  
    RJMP DIV_LOOP             ; Repite bucle  
   
DIV_END:                      ; Fin de división  
    MOV resto, temp           ; Guarda resto en registro resto (r22)  
    MOV temp, r21             ; Pone cociente en temp  
    POP r21                   ; Restaura r21  
    RET                       ; Retorno con cociente en temp y resto en r22  
   
; FUNCIÓN MODIFICADA: Ahora permite incrementar o decrementar horas/días    
BOTON_HORAS:                  ; Función para manejar botones de horas/días  
    ; Verificar en qué modo estamos     
    CPI modo, 2               ; Compara si estamos en modo configuración hora  
    BRNE CHECK_MODO_FECHA_DIAS ; Si no es modo 2, verifica si es modo fecha  
    
    ; Modo configuración hora    
    ; Verificar si estamos configurando horas (config_sel = 1)    
    CPI config_sel, 1         ; Compara si selector es 1 (configurando horas)  
    BRNE FIN_BOTON_HORAS      ; Si no configuramos horas, ignora botón  
      
    ; Incrementar horas si estamos presionando PB1, decrementar si PB2    
    SBIS PINB, PB1            ; Si PB1 está presionado (incrementar)  
    CALL INCREMENTAR_HORAS    ; Llama función de incremento  
    SBIS PINB, PB2            ; Si PB2 está presionado (decrementar)  
    CALL DECREMENTAR_HORAS    ; Llama función de decremento  
      
    RET                       ; Retorno de la función  
      
CHECK_MODO_FECHA_DIAS:        ; Verificación para modo fecha  
    CPI modo, 3               ; Compara si estamos en modo configuración fecha  
    BRNE CHECK_MODO_ALARMA_HORAS ; Si no es modo 3, verifica si es modo alarma  
      
    ; Modo configuración fecha    
    ; Verificar si estamos configurando días (config_sel = 1)    
    CPI config_sel, 1         ; Compara si selector es 1 (configurando días)  
    BRNE FIN_BOTON_HORAS      ; Si no configuramos días, ignora botón  
   
    ; Incrementar días si estamos presionando PB1, decrementar si PB2    
    SBIS PINB, PB1            ; Si PB1 está presionado (incrementar)  
    CALL INCREMENTAR_DIAS     ; Llama función de incremento días  
      
    SBIS PINB, PB2            ; Si PB2 está presionado (decrementar)  
    CALL DECREMENTAR_DIAS     ; Llama función de decremento días  
  
    RET                       ; Retorno de la función  

CHECK_MODO_ALARMA_HORAS:       ; Verificación para modo alarma (horas)  
    CPI modo, 4                ; Compara si estamos en modo configuración alarma  
    BRNE FIN_BOTON_HORAS       ; Si no es modo 4, termina función  

    ; Modo configuración alarma  
    ; Verificar si estamos configurando horas (config_sel = 1)  
    CPI config_sel, 1          ; Compara si selector es 1 (configurando horas)  
    BRNE FIN_BOTON_HORAS       ; Si no configuramos horas, ignora botón  

    ; Incrementar horas si estamos presionando PB1, decrementar si PB2  
    SBIS PINB, PB1             ; Si PB1 está presionado (incrementar)  
    CALL INCREMENTAR_HORAS_ALARMA ; Llama función de incremento de horas de alarma  

    SBIS PINB, PB2             ; Si PB2 está presionado (decrementar)  
    CALL DECREMENTAR_HORAS_ALARMA ; Llama función de decremento de horas de alarma  
      
FIN_BOTON_HORAS:               ; Etiqueta de fin de función  
    RET                        ; Retorno de la función  
    
; FUNCIÓN MODIFICADA: Ahora permite incrementar o decrementar minutos/meses    
BOTON_MINUTOS:                 ; Función para manejar botones de minutos/meses  
    ; Verificar en qué modo estamos  
    CPI modo, 2                ; Compara si estamos en modo configuración hora  
    BRNE CHECK_CONFIG_FECHA_MESES ; Si no es modo 2, verifica modo fecha  
      
    ; Modo configuración hora    
    ; Verificar si estamos configurando minutos (config_sel = 0)    
    CPI config_sel, 0          ; Compara si selector es 0 (configurando minutos)  
    BRNE FIN_BOTON_MINUTOS     ; Si no configuramos minutos, ignora botón  
      
    ; Incrementar minutos si estamos presionando PB1, decrementar si PB2    
    SBIS PINB, PB1             ; Si PB1 está presionado (incrementar)  
    CALL INCREMENTAR_MINUTOS   ; Llama función de incremento minutos  
    SBIS PINB, PB2             ; Si PB2 está presionado (decrementar)  
    CALL DECREMENTAR_MINUTOS   ; Llama función de decremento minutos  
      
    RET                        ; Retorno de la función  
      
CHECK_CONFIG_FECHA_MESES:      ; Verificación para modo fecha (meses)  
    CPI modo, 3                ; Compara si estamos en modo configuración fecha  
    BRNE CHECK_CONFIG_ALARMA_MINUTOS ; Si no es modo 3, verifica modo alarma  
      
    ; Modo configuración fecha    
    ; Verificar si estamos configurando meses (config_sel = 0)    
    CPI config_sel, 0          ; Compara si selector es 0 (configurando meses)  
    BRNE FIN_BOTON_MINUTOS     ; Si no configuramos meses, ignora botón  
      
    ; Incrementar meses si estamos presionando PB1, decrementar si PB2  
    SBIS PINB, PB1             ; Si PB1 está presionado (incrementar)  
    CALL INCREMENTAR_MESES     ; Llama función de incremento meses  
      
    SBIS PINB, PB2             ; Si PB2 está presionado (decrementar)  
    CALL DECREMENTAR_MESES     ; Llama función de decremento meses  
    RET                        ; Retorno de la función  

CHECK_CONFIG_ALARMA_MINUTOS:   ; Verificación para modo alarma (minutos)  
    CPI modo, 4                ; Compara si estamos en modo configuración alarma  
    BRNE FIN_BOTON_MINUTOS     ; Si no es modo 4, termina función  

    ; Modo configuración alarma  
    ; Verificar si estamos configurando minutos (config_sel = 0)  
    CPI config_sel, 0          ; Compara si selector es 0 (configurando minutos)  
    BRNE FIN_BOTON_MINUTOS     ; Si no configuramos minutos, ignora botón  

    ; Incrementar minutos si estamos presionando PB1, decrementar si PB2  
    SBIS PINB, PB1             ; Si PB1 está presionado (incrementar)  
    CALL INCREMENTAR_MINUTOS_ALARMA ; Llama función de incremento minutos de alarma  

    SBIS PINB, PB2             ; Si PB2 está presionado (decrementar)  
    CALL DECREMENTAR_MINUTOS_ALARMA ; Llama función de decremento minutos de alarma  
      
FIN_BOTON_MINUTOS:             ; Etiqueta de fin de función  
    RET                        ; Retorno de la función  
    
; FUNCIÓN: Cambiar entre configurar horas/minutos o días/meses    
CAMBIAR_CONFIG_SEL:            ; Función para alternar config_sel entre 0 y 1  
    ; Alternar entre 0 y 1    
    LDI temp, 1                ; Carga valor 1  
    EOR config_sel, temp       ; Operación XOR para alternar bit 0  
    RET                        ; Retorno de la función  
    
; Función para incrementar días    
INCREMENTAR_DIAS:              ; Función para incrementar días manualmente  
    PUSH r20                   ; Guarda registros en pila  
    PUSH r21     
    PUSH temp     
    PUSH temp2     
      
    ; Obtener días máximos del mes actual     
    CALL OBTENER_DIAS_MES      ; Obtiene cuántos días tiene el mes actual  
    MOV r21, temp              ; r21 = días máximos del mes  
  
    ; Calcular el día actual (decenas*10 + unidades)     
    LDS r20, dia_d             ; Carga decenas de día  
    LDI temp, 10               ; Base decimal (10)  
      
    ; Multiplicación manual (r20 * 10)     
    CLR temp2                  ; Limpia acumulador  
    MOV resto, r20             ; Contador para multiplicación  
   
MULT_LOOP_DIA_BOTON_INC:       ; Bucle para multiplicar por 10  
    CPI resto, 0               ; Compara si contador llegó a 0  
    BREQ MULT_DONE_DIA_BOTON_INC ; Si es 0, termina multiplicación  
    ADD temp2, temp            ; Suma 10 al acumulador  
    DEC resto                  ; Decrementa contador  
    RJMP MULT_LOOP_DIA_BOTON_INC ; Repite bucle  
   
MULT_DONE_DIA_BOTON_INC:       ; Fin de multiplicación  
    ; Añadir unidades     
    LDS r20, dia_u             ; Carga unidades de día  
    ADD temp2, r20             ; temp2 = día completo (decenas*10 + unidades)  
      
    ; Incrementar día     
    INC temp2                  ; Incrementa el día  
      
    ; Verificar si hemos superado el máximo de días del mes     
    CP temp2, r21              ; Compara con máximo de días  
    BRLO NO_OVERFLOW_DIA_INC   ; Si es menor, no hay overflow  
    BRNE OVERFLOW_DIA_INC      ; Si es mayor, hacer overflow  
    RJMP NO_OVERFLOW_DIA_INC   ; Si es igual, tampoco hay overflow  
      
OVERFLOW_DIA_INC:              ; Manejo de overflow de día  
    ; Si hemos superado el máximo, reiniciar a día 1     
    LDI temp, 1                ; Carga 1 para día nuevo  
    STS dia_u, temp            ; Guarda unidades = 1  
    LDI temp, 0                ; Carga 0 para decenas  
    STS dia_d, temp            ; Guarda decenas = 0 (día 01)  
      
    POP temp2                  ; Restaura registros  
    POP temp     
    POP r21     
    POP r20     
    RET                        ; Retorno de la función  
      
NO_OVERFLOW_DIA_INC:           ; Sin overflow, actualiza normalmente  
    ; Si no hemos superado el máximo, actualizar día normalmente     
    MOV temp, temp2            ; Copia día incrementado  
    LDI temp2, 10              ; Base decimal (10)  
    CALL DIV                   ; Divide: temp = decenas, resto = unidades  
    STS dia_d, temp            ; Guarda decenas de día  
    MOV temp, resto            ; Copia unidades  
    STS dia_u, temp            ; Guarda unidades de día  
    POP temp2                  ; Restaura registros  
    POP temp     
    POP r21     
    POP r20     
    RET                        ; Retorno de la función  
    
; FUNCIÓN CORREGIDA: Decrementar días    
DECREMENTAR_DIAS:              ; Función para decrementar días manualmente  
    PUSH r20                   ; Guarda registros en pila  
    PUSH r21    
    PUSH temp    
    PUSH temp2   
    
    ; Calcular el día actual (decenas*10 + unidades)    
    LDS r20, dia_d             ; Carga decenas de día  
    LDI temp, 10               ; Base decimal (10)  
      
    ; Multiplicación manual (r20 * 10)    
    CLR temp2                  ; Limpia acumulador  
    MOV resto, r20             ; Contador para multiplicación  
   
MULT_LOOP_DIA_BOTON_DEC:       ; Bucle para multiplicar por 10  
    CPI resto, 0               ; Compara si contador llegó a 0  
    BREQ MULT_DONE_DIA_BOTON_DEC ; Si es 0, termina multiplicación  
    ADD temp2, temp            ; Suma 10 al acumulador  
    DEC resto                  ; Decrementa contador  
    RJMP MULT_LOOP_DIA_BOTON_DEC ; Repite bucle  
  
MULT_DONE_DIA_BOTON_DEC:       ; Fin de multiplicación  
    ; Añadir unidades    
    LDS r20, dia_u             ; Carga unidades de día  
    ADD temp2, r20             ; temp2 = día completo (decenas*10 + unidades)  
      
    ; Verificar si estamos en día 1    
    CPI temp2, 1               ; Compara si es día 1  
    BRNE NO_UNDERFLOW_DIA      ; Si no es día 1, no hay underflow  
      
    ; Si es día 1, cambiar al último día del mes    
    CALL OBTENER_DIAS_MES      ; Obtiene días del mes actual  
    MOV temp2, temp            ; temp2 = último día del mes  
    RJMP ACTUALIZAR_DIA_DEC    ; Salta a actualizar día  
      
NO_UNDERFLOW_DIA:              ; Sin underflow, decrementa normalmente  
    ; Si no es día 1, simplemente decrementar    
    DEC temp2                  ; Decrementa día  
      
ACTUALIZAR_DIA_DEC:            ; Actualiza día decrementado  
    ; Actualizar día    
    MOV temp, temp2            ; Copia día decrementado  
    LDI temp2, 10              ; Base decimal (10)  
    CALL DIV                   ; Divide: temp = decenas, resto = unidades  
    STS dia_d, temp            ; Guarda decenas de día  
    MOV temp, resto            ; Copia unidades  
    STS dia_u, temp            ; Guarda unidades de día  
      
    POP temp2                  ; Restaura registros  
    POP temp    
    POP r21    
    POP r20    
    RET                        ; Retorno de la función  
    
; Función para incrementar meses     
INCREMENTAR_MESES:             ; Función para incrementar meses manualmente  
    PUSH r20                   ; Guarda registros en pila  
    PUSH temp   
    
    ; Incrementar unidades de mes     
    LDS temp, mes_u            ; Carga unidades de mes  
    INC temp                   ; Incrementa unidades  
      
    ; Verificar si llegamos a mes 13     
    LDS r20, mes_d             ; Carga decenas de mes  
    CPI r20, 1                 ; Compara si decenas es 1  
    BRNE CHECK_MES_U           ; Si no es 1, verificación normal  
    CPI temp, 3                ; Compara si unidades es 3 (mes 13)  
    BRNE CHECK_MES_U           ; Si no es 3, verificación normal  
      
    ; Si llegamos a mes 13, reiniciar a mes 1     
    LDI temp, 1                ; Carga 1 para unidades  
    STS mes_u, temp            ; Guarda unidades = 1  
    LDI temp, 0                ; Carga 0 para decenas  
    STS mes_d, temp            ; Guarda decenas = 0 (mes 01)  
      
    ; Verificar si el día actual es válido para el nuevo mes     
    CALL VALIDAR_DIA_ACTUAL    ; Valida que el día sea válido para nuevo mes  
      
    POP temp                   ; Restaura registros  
    POP r20     
    RET                        ; Retorno de la función  
      
CHECK_MES_U:                   ; Verificación normal de unidades de mes  
    ; Verificar si unidades de mes llega a 10     
    CPI temp, 10               ; Compara si unidades llegó a 10  
    BRNE SAVE_MES_U            ; Si no es 10, guarda y termina  
      
    ; Si unidades de mes llega a 10, reiniciar e incrementar decenas     
    LDI temp, 0                ; Reinicia unidades a 0  
    STS mes_u, temp            ; Guarda el valor  
      
    ; Incrementar decenas de mes     
    LDS temp, mes_d            ; Carga decenas de mes  
    INC temp                   ; Incrementa decenas  
    STS mes_d, temp            ; Guarda el valor  
      
    ; Verificar si el día actual es válido para el nuevo mes     
    CALL VALIDAR_DIA_ACTUAL    ; Valida que el día sea válido  
    POP temp                   ; Restaura registros  
    POP r20     
    RET                        ; Retorno de la función  
      
SAVE_MES_U:                    ; Guarda unidades de mes incrementadas  
    STS mes_u, temp            ; Guarda unidades de mes  
      
    ; Verificar si el día actual es válido para el nuevo mes     
    CALL VALIDAR_DIA_ACTUAL    ; Valida que el día sea válido  
    POP temp                   ; Restaura registros  
    POP r20     
    RET                        ; Retorno de la función  
    
; FUNCIÓN CORREGIDA: Decrementar meses (usando registros válidos)    
DECREMENTAR_MESES:             ; Función para decrementar meses manualmente  
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
    CPI resto, 0               ; Compara si contador llegó a 0  
    BREQ MULT_DONE_MES_DEC     ; Si es 0, termina multiplicación  
    ADD temp2, r21             ; temp2 += 10   
    DEC resto                  ; Decrementa contador  
    RJMP MULT_LOOP_MES_DEC     ; Repite bucle  
   
MULT_DONE_MES_DEC:             ; Fin de multiplicación  
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
    RJMP VALIDAR_MES_DEC       ; Salta a validar día para nuevo mes  
   
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
    RJMP VALIDAR_MES_DEC       ; Salta a validar día para nuevo mes  
   
DEC_MES_U:                     ; Decrementar unidades normalmente  
    ; Decrementar unidades normalmente   
    DEC temp                   ; Decrementa unidades  
    STS mes_u, temp            ; Guarda el nuevo valor  
   
VALIDAR_MES_DEC:               ; Validación del día para el nuevo mes  
    ; Asegurar que el día actual sea válido para el nuevo mes   
    CALL VALIDAR_DIA_ACTUAL    ; Valida que el día sea válido  
   
    POP temp2                  ; Restaura registros  
    POP temp   
    POP r21   
    POP r20  
    RET                        ; Retorno de la función  

; Funciones para manejar la alarma  
; Incrementar horas de alarma  
INCREMENTAR_HORAS_ALARMA:      ; Función para incrementar horas de alarma  
    ; Incrementar unidades de horas de alarma  
    LDS temp, alarm_hr_u       ; Carga unidades de horas de alarma  
    INC temp                   ; Incrementa unidades  
   
    ; Verificar si llegamos a 24 horas  
    LDS temp2, alarm_hr_d      ; Carga decenas de horas de alarma  
    CPI temp2, 2               ; Compara si decenas es 2  
    BRNE INC_ALARM_HR_CHECK_U  ; Si no es 2, verificación normal  
    CPI temp, 4                ; Compara si unidades llegó a 4 (24 horas)  
    BRNE INC_ALARM_HR_CHECK_U  ; Si no es 4, verificación normal  
   
    ; Si llegamos a 24 horas, reiniciar a 00:00  
    LDI temp, 0                ; Reinicia unidades a 0  
    STS alarm_hr_u, temp       ; Guarda unidades = 0  
    LDI temp, 0                ; Reinicia decenas a 0  
    STS alarm_hr_d, temp       ; Guarda decenas = 0 (hora 00)  
    RET                        ; Retorno de la función  
   
INC_ALARM_HR_CHECK_U:          ; Verificación normal de unidades de hora  
    ; Verificar si unidades de hora llega a 10  
    CPI temp, 10               ; Compara si unidades llegó a 10  
    BRNE INC_ALARM_HR_SAVE_U   ; Si no es 10, guarda y termina  
   
    ; Si unidades llega a 10, reiniciar e incrementar decenas  
    LDI temp, 0                ; Reinicia unidades a 0  
    STS alarm_hr_u, temp       ; Guarda el valor  
   
    ; Incrementar decenas de horas  
    LDS temp, alarm_hr_d       ; Carga decenas de horas  
    INC temp                   ; Incrementa decenas  
    STS alarm_hr_d, temp       ; Guarda el valor  
    RET                        ; Retorno de la función  
   
INC_ALARM_HR_SAVE_U:           ; Guarda unidades incrementadas  
    STS alarm_hr_u, temp       ; Guarda unidades de hora  
    RET                        ; Retorno de la función  

; Decrementar horas de alarma  
DECREMENTAR_HORAS_ALARMA:      ; Función para decrementar horas de alarma  
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
    RET                        ; Retorno de la función  
      
DEC_ALARM_HR_NOT_ZERO_U:       ; Decrementa unidades no cero  
    ; Decrementar unidades de hora  
    DEC temp                   ; Decrementa unidades  
    STS alarm_hr_u, temp       ; Guarda el nuevo valor  
    RET                        ; Retorno de la función  

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
    RET                        ; Retorno de la función  

; Incrementar minutos de alarma  
INCREMENTAR_MINUTOS_ALARMA:    ; Función para incrementar minutos de alarma  
    ; Incrementar unidades de minutos  
    LDS temp, alarm_min_u      ; Carga unidades de minutos  
    INC temp                   ; Incrementa unidades  
    CPI temp, 10               ; Compara si llegó a 10  
    BRNE INC_ALARM_MIN_SAVE_U  ; Si no es 10, guarda y termina  
   
    ; Si unidades llega a 10, reiniciar e incrementar decenas  
    LDI temp, 0                ; Reinicia unidades a 0  
    STS alarm_min_u, temp      ; Guarda el valor  
   
    ; Incrementar decenas de minutos  
    LDS temp, alarm_min_d      ; Carga decenas de minutos  
    INC temp                   ; Incrementa decenas  
    CPI temp, 6                ; Compara si llegó a 6 (60 minutos)  
    BRNE INC_ALARM_MIN_SAVE_D  ; Si no es 6, guarda y termina  
   
    ; Si decenas llega a 6, reiniciar  
    LDI temp, 0                ; Reinicia decenas a 0  

INC_ALARM_MIN_SAVE_D:          ; Guarda decenas incrementadas  
    STS alarm_min_d, temp      ; Guarda el valor  
    RET                        ; Retorno de la función  
   
INC_ALARM_MIN_SAVE_U:          ; Guarda unidades incrementadas  
    STS alarm_min_u, temp      ; Guarda el valor  
    RET                        ; Retorno de la función  

; Decrementar minutos de alarma  
DECREMENTAR_MINUTOS_ALARMA:    ; Función para decrementar minutos de alarma  
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
    RET                        ; Retorno de la función  

DEC_ALARM_MIN_NOT_ZERO_U:      ; Decrementa unidades no cero  
    ; Decrementar unidades de minutos  
    DEC temp                   ; Decrementa unidades  
    STS alarm_min_u, temp      ; Guarda el nuevo valor  
    RET                        ; Retorno de la función  
      
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
    RET                        ; Retorno de la función  

; Verificar si la hora actual coincide con la hora de la alarma  
VERIFICAR_ALARMA:              ; Función para comprobar coincidencia con alarma  
    PUSH temp                  ; Guarda registros en pila  
    PUSH temp2   
   
    ; Verificar si la alarma ya está activa   
    LDS temp, alarm_active     ; Carga estado de alarma  
    CPI temp, 1                ; Compara si está activa (1)  
    BREQ FIN_VERIFICAR_ALARMA  ; Si ya está activa, no hacer nada más  
    
    ; NUEVO: Verificar bit de alarma apagada manualmente  
    SBRC flags, 1              ; Saltar siguiente instrucción si bit 1 está borrado  
    RJMP COMPROBAR_CAMBIO_HORA ; Si alarma fue apagada, verificar si cambió la hora  
   
CONTINUAR_VERIFICACION:        ; Continúa verificación normal  
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
    STS alarm_counter, temp    ; Reinicia contador de duración  
    SBI PORTB, PB5             ; Encender LED de alarma (PB5)   
    RJMP FIN_VERIFICAR_ALARMA  ; Salta a fin de función  
    
COMPROBAR_CAMBIO_HORA:         ; Verificación para reset de bit de alarma  
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
    
    ; Si todavía coincide la hora, mantener bit y salir  
    RJMP FIN_VERIFICAR_ALARMA  ; Salta a fin de función  
    
RESET_ALARM_FLAG:              ; Resetea flag de alarma apagada  
    ; La hora ya no coincide, resetear bit de alarma apagada  
    ANDI flags, ~(1<<1)        ; Limpiar bit 1 (flag de alarma apagada)  
    RJMP CONTINUAR_VERIFICACION ; Ahora sí verificar la alarma  
   
FIN_VERIFICAR_ALARMA:          ; Fin de la función  
    POP temp2                  ; Restaura registros  
    POP temp   
    RET                        ; Retorno de la función  
    
; FUNCIÓN CORREGIDA: Manejo del temporizador con incrementos no deseados corregidos    
TMR0_ISR:                      ; Rutina de interrupción de Timer0  
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
   
    CPI temp, 30               ; Compara si llegó a 30  
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
    LDI temp2, (1<<PB4)        ; Máscara para PB4  
    EOR temp, temp2            ; Invierte estado de PB4  
    OUT PORTB, temp            ; Actualiza PORTB  
    RJMP SKIP_LED              ; Salta a siguiente sección  
   
CHECK_LED_MODO_3:              ; Verificación para modo 3  
    CPI modo, 3                ; Compara con modo 3 (config fecha)  
    BRNE CHECK_LED_MODO_4      ; Si no es modo 3, verifica modo 4  
    ; Parpadear PC4 (LED fecha)  
    IN temp, PORTC             ; Lee estado actual de PORTC  
    LDI temp2, (1<<PC4)        ; Máscara para PC4  
    EOR temp, temp2            ; Invierte estado de PC4  
    OUT PORTC, temp            ; Actualiza PORTC  
    RJMP SKIP_LED              ; Salta a siguiente sección  

CHECK_LED_MODO_4:              ; Verificación para modo 4  
    CPI modo, 4                ; Compara con modo 4 (config alarma)  
    BRNE SKIP_LED              ; Si no es modo 4, salta  
    ; Parpadear PB4 (LED hora)  
    IN temp, PORTB             ; Lee estado actual de PORTB  
    LDI temp2, (1<<PB4)        ; Máscara para PB4  
    EOR temp, temp2            ; Invierte estado de PB4  
    OUT PORTB, temp            ; Actualiza PORTB  
   
SKIP_LED:                      ; Continúa rutina de timer  
    ; Incrementar contador principal     
    LDS temp, contador         ; Carga contador principal  
    INC temp                   ; Incrementa contador  
    STS contador, temp         ; Guarda nuevo valor  
    CPI temp, 61               ; Compara si llegó a 61 (aprox. 1 segundo)  
    BRNE CHECK_ALARMA_ACTIVA   ; Si no es 61, verifica alarma  
      
    LDI temp, 0                ; Reinicia contador  
    STS contador, temp         ; Guarda nuevo valor  
      
    ; Solo incrementar tiempo si NO estamos en modo configuración    
    ; PUNTO CRÍTICO: Verificar explícitamente los modos   
    CPI modo, 0                ; Compara con modo 0 (reloj)  
    BRNE CHECK_MODO_FECHA_AUTO ; Si no es modo 0, verifica modo 1  
    ; Si modo = 0 (reloj), incrementar tiempo    
    CALL INCREMENTAR_TIEMPO    ; Llama función de incremento de tiempo  
    CALL VERIFICAR_ALARMA      ; Verifica si hay que activar la alarma  
    RJMP CHECK_ALARMA_ACTIVA   ; Salta a verificar alarma activa  
      
CHECK_MODO_FECHA_AUTO:         ; Verificación para modo fecha  
    CPI modo, 1                ; Compara con modo 1 (fecha)  
    BRNE CHECK_ALARMA_ACTIVA   ; Si no es modo 0 ni 1, no incrementar  

CHECK_ALARMA_ACTIVA:           ; Verifica si la alarma está activa  
    ; Verificar si la alarma está activa  
    LDS temp, alarm_active     ; Carga estado de alarma  
    CPI temp, 1                ; Compara si está activa (1)  
    BRNE FIN_ISR               ; Si no está activa, termina  

    ; Incrementar contador de alarma  
    LDS temp, alarm_counter    ; Carga contador de alarma  
    INC temp                   ; Incrementa contador  
    STS alarm_counter, temp    ; Guarda nuevo valor  
    CPI temp, 30               ; Compara si llegó a 30 segundos  
    BRLO FIN_ISR               ; Si es menor, termina  

    ; Si ha pasado 30 segundos, desactivar alarma  
    LDI temp, 0                ; Valor = 0 (alarma inactiva)  
    STS alarm_active, temp     ; Desactiva alarma  
    STS alarm_counter, temp    ; Reinicia contador  
    CBI PORTB, PB5             ; Apagar LED de alarma  
      
FIN_ISR:                       ; Fin de rutina de interrupción  
    POP temp2                  ; Restaura registros  
    POP temp     
    OUT SREG, temp             ; Restaura registro de estado  
    POP temp     
    RETI                       ; Retorno de interrupción  
    
; VERSIÓN CORREGIDA: Rutina ISR_PCINT0 para incluir PB3    
ISR_PCINT0:                    ; Rutina de interrupción para botones  
    PUSH temp                  ; Guarda registros en pila  
    IN temp, SREG              ; Guarda registro de estado  
    PUSH temp     
    PUSH temp2   
    
    ; Verificar botón PB0 (modo)     
    SBIC PINB, PB0             ; Verifica si PB0 está presionado  
    RJMP CHECK_PB1_PRESS       ; Si no está presionado, verifica PB1  
      
    ; Cambiar modo    
    CALL CAMBIAR_MODO          ; Llama función para cambiar modo  
    RJMP FIN_PCINT0            ; Salta a fin de rutina  
      
CHECK_PB1_PRESS:               ; Verificación para PB1 (incrementar)  
    ; Verificar botón PB1 (incrementar)     
    SBIC PINB, PB1             ; Verifica si PB1 está presionado  
    RJMP CHECK_PB2_PRESS       ; Si no está presionado, verifica PB2  
      
    ; Acción según modo (incrementar)    
    CPI modo, 2                ; Compara si modo >= 2 (configuración)  
    BRLO FIN_PCINT0            ; Si modo < 2, ignorar  
      
    ; En modo configuración, manejar botones a través de las funciones específicas    
    CALL BOTON_HORAS           ; Llama función para botón horas  
    CALL BOTON_MINUTOS         ; Llama función para botón minutos  
    RJMP FIN_PCINT0            ; Salta a fin de rutina  
      
CHECK_PB2_PRESS:               ; Verificación para PB2 (decrementar)  
    ; Verificar botón PB2 (decrementar)      
    SBIC PINB, PB2             ; Verifica si PB2 está presionado  
    RJMP CHECK_PB3_PRESS       ; Si no está presionado, verifica PB3  

    ; NUEVA FUNCIONALIDAD: Verificar si estamos en modo hora (MODO=0) y la alarma está activa  
    CPI modo, 0                ; Compara con modo 0 (reloj)  
    BRNE CHECK_MODO_CONFIG     ; Si no estamos en modo hora, verificar config  
    
    ; Estamos en modo hora, verificar si la alarma está activa  
    LDS temp, alarm_active     ; Carga estado de alarma  
    CPI temp, 1                ; Compara si está activa (1)  
    BRNE CHECK_MODO_CONFIG     ; Si la alarma no está activa, verifica config  
    
    ; La alarma está activa y estamos en modo hora, apagar la alarma  
    LDI temp, 0                ; Valor = 0 (alarma inactiva)  
    STS alarm_active, temp     ; Desactiva alarma  
    STS alarm_counter, temp    ; Reinicia contador  
    CBI PORTB, PB5             ; Apagar LED de alarma  
    
    ; Establecer bit 1 de flags para indicar alarma apagada manualmente  
    ORI flags, (1<<1)          ; Establece bit 1 (flag de alarma apagada)  
    
    RJMP FIN_PCINT0            ; Salta a fin de rutina  
      
CHECK_MODO_CONFIG:             ; Verificación para modos de configuración  
    ; Acción según modo (decrementar)     
    CPI modo, 2                ; Compara si modo >= 2 (configuración)  
    BRLO FIN_PCINT0            ; Si modo < 2, ignorar  
       
    ; En modo configuración, manejar botones a través de las funciones específicas     
    CALL BOTON_HORAS           ; Llama función para botón horas  
    CALL BOTON_MINUTOS         ; Llama función para botón minutos  
    RJMP FIN_PCINT0            ; Salta a fin de rutina  

CHECK_PB3_PRESS:               ; Verificación para PB3 (cambiar selección)  
    ; Verificar botón PB3 (cambiar selección)    
    SBIC PINB, PB3             ; Verifica si PB3 está presionado  
    RJMP FIN_PCINT0            ; Si no está presionado, termina  
      
    ; Solo cambiar selección si estamos en modo configuración    
    CPI modo, 2                ; Compara si modo >= 2 (configuración)  
    BRLO FIN_PCINT0            ; Si modo < 2, ignorar  
  
    ; Cambiar entre hora/minutos o día/mes    
    CALL CAMBIAR_CONFIG_SEL    ; Alterna entre configurar hora/día (1) o minutos/mes (0)  
      
FIN_PCINT0:                    ; Fin de rutina de interrupción  
    POP temp2                  ; Restaura registros  
    POP temp   
    OUT SREG, temp             ; Restaura registro de estado  
    POP temp     
    RETI                       ; Retorno de interrupción  
   
; Función para cambiar el modo (separada para mejor organización)     
CAMBIAR_MODO:                  ; Función para cambiar el modo del reloj  
    ; Cambiar modo     
    INC modo                   ; Incrementa modo  
    CPI modo, 5                ; Compara si llegó a 5  
    BRNE ACTUALIZAR_MODO_CAMBIO ; Si no es 5, actualiza LEDs  
    CLR modo                   ; Si es 5, reinicia a modo 0  
      
ACTUALIZAR_MODO_CAMBIO:        ; Actualiza LEDs según nuevo modo  
    ; Resetear selección a 1 (horas o días) cuando cambia el modo    
    LDI temp, 1                ; Valor = 1 (configura horas/días)  
    MOV config_sel, temp       ; Actualiza selector  
      
    CALL ACTUALIZAR_LEDS_MODO  ; Actualiza LEDs indicadores  
    RET                        ; Retorno de la función  