;************************************************************     
; Universidad del Valle de Guatemala     
; IE2023: Programación de Microcontroladores     
;     
; Reloj Digital con 4 displays (horas:minutos)     
; Multiplexación en PC0-PC3 (cambiado de PB0-PB3)     
; Botones en PB0-PB3 (cambiado de PC0-PC2)     
; LEDs indicadores en PB4, PC4, PC5 y PB5 (alarma)     
;************************************************************     
.include "m328Pdef.inc"     
.cseg     
.org 0x0000     
   
JMP START     
.org OVF0addr     
   
JMP TMR0_ISR     
.org 0x0006 ; Dirección para PCINT0 (PCINT[0:7]) para botones en PORTB     
   
JMP ISR_PCINT0        
; Tabla de valores para display de 7 segmentos     
.org 0x0030 ; Dirección segura para el resto del código     
DISPLAY:     
   
.db 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F  

; Definición de registros     
.def temp = r16      ; Registro temporal     
.def flags = r23     ; Registro para flags (bit 0 para parpadeo, bit 1 para alarma activa)     
.def temp2 = r18     ; Registro temporal adicional    
.def modo = r19      ; Registro para modo     
.def config_sel = r17 ; Registro para selección de configuración    
                      ; 0 = minutos/meses    
                      ; 1 = horas/días    
.def resto = r22     ; Registro para almacenar restos en divisiones    
; 0 = reloj     
; 1 = fecha     
; 2 = config hora     
; 3 = config fecha  
; 4 = config alarma  

; Variables en .dseg     
.dseg     
cont_sec:    .byte 1  ; Contador de segundos     
cont_min_u:  .byte 1  ; Unidades de minutos     
cont_min_d:  .byte 1  ; Decenas de minutos     
cont_hr_u:   .byte 1  ; Unidades de horas     
cont_hr_d:   .byte 1  ; Decenas de horas     
contador:    .byte 1  ; Contador para timer     
led_timer:   .byte 1  ; Contador para LED     
dia_u:       .byte 1  ; Unidades de día     
dia_d:       .byte 1  ; Decenas de día     
mes_u:       .byte 1  ; Unidades de mes   
mes_d:       .byte 1  ; Decenas de mes  
alarm_min_u: .byte 1  ; Unidades de minutos de alarma  
alarm_min_d: .byte 1  ; Decenas de minutos de alarma  
alarm_hr_u:  .byte 1  ; Unidades de horas de alarma  
alarm_hr_d:  .byte 1  ; Decenas de horas de alarma  
alarm_active:.byte 1  ; Flag para indicar si la alarma está sonando  
alarm_counter:.byte 1 ; Contador para duración de alarma (30 segundos)  

.cseg     
   
START:     
    LDI temp, LOW(RAMEND)     
    OUT SPL, temp     
    LDI temp, HIGH(RAMEND)     
    OUT SPH, temp     
SETUP:    
    CLI     
   
    ; Configuración del prescaler del reloj     
    LDI temp, (1<<CS02)|(1<<CS00) ; Prescaler de 1024     
    OUT TCCR0B, temp     
    LDI temp, 0 ; Valor inicial para timer     
    OUT TCNT0, temp   
   
    ; Habilitar interrupción de Timer 0     
    LDI temp, (1<<TOIE0)     
    STS TIMSK0, temp     
   
    ; Configuración de puertos     
    ; PORTB: PB0-PB3 como entradas (botones), PB4 y PB5 como salidas (LED modo hora y alarma)     
    LDI temp, (1<<PB4)|(1<<PB5) ; PB4 y PB5 como salidas     
    OUT DDRB, temp     
    LDI temp, (1<<PB0)|(1<<PB1)|(1<<PB2)|(1<<PB3) ; Pull-up en PB0, PB1, PB2, PB3     
    OUT PORTB, temp  

    ; PORTC: PC0-PC3 como salidas (multiplexor), PC4-PC5 como salidas (LEDs)     
    LDI temp, (1<<PC0)|(1<<PC1)|(1<<PC2)|(1<<PC3)|(1<<PC4)|(1<<PC5)     
    OUT DDRC, temp     
    LDI temp, 0x00 ; Inicializar en 0   
    OUT PORTC, temp     
   
    ; PORTD: Todo como salidas (segmentos)     
    LDI temp, 0xFF     
    OUT DDRD, temp    
     
    ; Configuración de interrupciones pin change para PORTB (botones)     
    LDI temp, (1<<PCIE0) ; Habilitar PCINT grupo 0 (PORTB)     
    STS PCICR, temp     
    LDI temp, (1<<PCINT0)|(1<<PCINT1)|(1<<PCINT2)|(1<<PCINT3) ; Habilitar PCINT0-3 (PB0-PB3)     
    STS PCMSK0, temp     
   
    ; Inicialización de variables     
    LDI temp, 0     
    STS cont_sec, temp   
    STS cont_min_u, temp     
    STS cont_min_d, temp     
    STS cont_hr_u, temp     
    STS cont_hr_d, temp     
    STS contador, temp  
    STS led_timer, temp  
    STS alarm_active, temp  
    STS alarm_counter, temp  
   
    ; Inicializar fecha (01/01)     
    LDI temp, 1     
    STS dia_u, temp     
    LDI temp, 0     
    STS dia_d, temp     
    LDI temp, 1   
    STS mes_u, temp     
    LDI temp, 0     
    STS mes_d, temp    
    
    ; Inicializar alarma (12:12)  
    LDI temp, 2  
    STS alarm_hr_u, temp  
    STS alarm_min_u, temp  
    LDI temp, 1  
    STS alarm_hr_d, temp  
    STS alarm_min_d, temp  
     
    CLR flags     
    CLR modo     
    
    ; Inicializar config_sel en 1 (por defecto configurando horas/días)    
    LDI temp, 1    
    MOV config_sel, temp    
   
    ; Inicializar LED de modo hora (PB4)     
    SBI PORTB, PB4     
    CBI PORTC, PC4 ; Asegurar que PC4 esté apagado     
    CBI PORTC, PC5 ; Asegurar que PC5 esté apagado  
    CBI PORTB, PB5 ; Asegurar que la alarma esté apagada  
   
    SEI     
MAIN_LOOP:  
    CALL MOSTRAR_DISPLAYS  
    RJMP MAIN_LOOP     
   
ACTUALIZAR_LEDS_MODO:   
    PUSH temp   
    PUSH temp2  
    ; Apagar todos los LEDs primero   
    CBI PORTB, PB4   
    CBI PORTC, PC4   
    CBI PORTC, PC5   
   
    CPI modo, 0   
    BRNE CHECK_MODO_1   
    SBI PORTB, PB4 ; Modo 0 (hora): Encender PB4   
    RJMP SET_LEDS   
   
CHECK_MODO_1:   
    CPI modo, 1   
    BRNE CHECK_MODO_2   
    SBI PORTC, PC4 ; Modo 1 (fecha): Encender PC4   
    RJMP SET_LEDS   
   
CHECK_MODO_2:   
    CPI modo, 2   
    BRNE CHECK_MODO_3   
    SBI PORTB, PB4 ; Modo 2 (config hora): Encender PB4 (parpadea) y PC5 (fijo)   
    SBI PORTC, PC5  
    RJMP SET_LEDS   
   
CHECK_MODO_3:   
    CPI modo, 3  
    BRNE CHECK_MODO_4  
    SBI PORTC, PC4 ; Modo 3 (config fecha): Encender PC4 (parpadea) y PC5 (fijo)  
    SBI PORTC, PC5  
    RJMP SET_LEDS  

CHECK_MODO_4:  
    CPI modo, 4  
    BRNE SET_LEDS  
    SBI PORTB, PB4 ; Modo 4 (config alarma): Encender PB4 (parpadea) y PC5 apagado  
    ; PC5 se mantiene apagado  
   
SET_LEDS:   
    POP temp2  
    POP temp   
    RET   
   
MOSTRAR_DISPLAYS:     
    CPI modo, 1 ; Verificar modo     
    BRNE CHECK_MODO_2_DISPLAY     
    JMP MOSTRAR_FECHA ; Si modo = 1, mostrar fecha (usar JMP en lugar de BREQ)     
   
CHECK_MODO_2_DISPLAY:     
    CPI modo, 2 ; Verificar modo     
    BRNE CHECK_MODO_3_DISPLAY     
    JMP MOSTRAR_CONFIG_HORA ; Si modo = 2, mostrar config hora (usar JMP)     
   
CHECK_MODO_3_DISPLAY:    
    CPI modo, 3 ; Verificar modo     
    BRNE CHECK_MODO_4_DISPLAY  
    JMP MOSTRAR_CONFIG_FECHA ; Si modo = 3, mostrar config fecha (usar JMP)  

CHECK_MODO_4_DISPLAY:  
    CPI modo, 4 ; Verificar modo  
    BRNE MOSTRAR_RELOJ  
    JMP MOSTRAR_CONFIG_ALARMA ; Si modo = 4, mostrar config alarma (usar JMP)  
   
MOSTRAR_RELOJ:     
    ; Mostrar modo reloj (modificado para PC0-PC3)  
    ; Display 4 (PC3) - Decenas de horas     
    CALL APAGAR_DISPLAYS     
   
    LDI ZL, LOW(DISPLAY*2)     
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, cont_hr_d     
    ADD ZL, temp     
    LPM temp, Z     
    OUT PORTD, temp     
    SBI PORTC, PC3     
    CALL RETARDO     
     
    ; Display 3 (PC2) - Unidades de horas     
    CALL APAGAR_DISPLAYS   
    LDI ZL, LOW(DISPLAY*2)     
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, cont_hr_u     
    ADD ZL, temp     
    LPM temp, Z     
    SBRC flags, 0     
    ORI temp, 0x80    
    OUT PORTD, temp     
    SBI PORTC, PC2     
    CALL RETARDO     
     
    ; Display 2 (PC1) - Decenas de minutos  
    CALL APAGAR_DISPLAYS     
   
    LDI ZL, LOW(DISPLAY*2)   
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, cont_min_d     
    ADD ZL, temp     
    LPM temp, Z     
    SBRC flags, 0     
    ORI temp, 0x80     
    OUT PORTD, temp     
    SBI PORTC, PC1     
    CALL RETARDO     
     
    ; Display 1 (PC0) - Unidades de minutos     
    CALL APAGAR_DISPLAYS     
   
    LDI ZL, LOW(DISPLAY*2)     
    LDI ZH, HIGH(DISPLAY*2)   
    LDS temp, cont_min_u     
    ADD ZL, temp     
    LPM temp, Z     
    OUT PORTD, temp     
    SBI PORTC, PC0    
    CALL RETARDO     
    RET  

MOSTRAR_FECHA:     
    ; Display 4 (PC3) - Decenas de día     
    CALL APAGAR_DISPLAYS     
   
    LDI ZL, LOW(DISPLAY*2)     
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, dia_d   
    ADD ZL, temp     
    LPM temp, Z     
    OUT PORTD, temp     
    SBI PORTC, PC3     
    CALL RETARDO     
     
    ; Display 3 (PC2) - Unidades de día     
    CALL APAGAR_DISPLAYS     
     
    LDI ZL, LOW(DISPLAY*2)     
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, dia_u     
    ADD ZL, temp     
    LPM temp, Z     
    ORI temp, 0x80 ; Punto decimal para separador   
    OUT PORTD, temp     
    SBI PORTC, PC2     
    CALL RETARDO  

    ; Display 2 (PC1) - Decenas de mes    
    CALL APAGAR_DISPLAYS     
     
    LDI ZL, LOW(DISPLAY*2)     
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, mes_d     
    ADD ZL, temp     
    LPM temp, Z     
    OUT PORTD, temp     
    SBI PORTC, PC1     
    CALL RETARDO     
     
    ; Display 1 (PC0) - Unidades de mes   
    CALL APAGAR_DISPLAYS     
     
    LDI ZL, LOW(DISPLAY*2)     
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, mes_u     
    ADD ZL, temp     
    LPM temp, Z     
    OUT PORTD, temp     
    SBI PORTC, PC0     
    CALL RETARDO     
    RET     
   
MOSTRAR_CONFIG_HORA:  
    ; Mostrar hora con parpadeo en horas o minutos según config_sel    
    ; Display 4 (PC3) - Decenas de horas     
    CALL APAGAR_DISPLAYS   
    LDI ZL, LOW(DISPLAY*2)    
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, cont_hr_d     
    ADD ZL, temp     
    LPM temp, Z    
    
    ; Si config_sel = 1 (configurando horas) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 1    
    BRNE NO_BLINK_HR_D    
    SBRC flags, 0    
    CLR temp ; Apagar segmento para efecto de parpadeo    
NO_BLINK_HR_D:    
    OUT PORTD, temp     
    SBI PORTC, PC3     
    CALL RETARDO     
     
    ; Display 3 (PC2) - Unidades de horas   
    CALL APAGAR_DISPLAYS     
     
    LDI ZL, LOW(DISPLAY*2)     
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, cont_hr_u     
    ADD ZL, temp     
    LPM temp, Z     
     
    ; Si config_sel = 1 (configurando horas) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 1    
    BRNE ADD_DOT_HR    
    SBRC flags, 0    
    CLR temp ; Apagar segmento para efecto de parpadeo    
ADD_DOT_HR:    
    
    ; Añadir punto decimal siempre    
    ORI temp, 0x80     
    OUT PORTD, temp     
    SBI PORTC, PC2   
    CALL RETARDO     
     
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
NO_BLINK_MIN_D:    
    OUT PORTD, temp   
    SBI PORTC, PC1     
    CALL RETARDO     
     
    ; Display 1 (PC0) - Unidades de minutos     
    CALL APAGAR_DISPLAYS     
     
    LDI ZL, LOW(DISPLAY*2)     
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, cont_min_u     
    ADD ZL, temp     
    LPM temp, Z     
    
    ; Si config_sel = 0 (configurando minutos) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 0    
    BRNE NO_BLINK_MIN_U    
    SBRC flags, 0    
    CLR temp ; Apagar segmento para efecto de parpadeo    
NO_BLINK_MIN_U:   
    OUT PORTD, temp  
    SBI PORTC, PC0     
    CALL RETARDO     
    RET     
   
MOSTRAR_CONFIG_FECHA:     
    ; Display 4 (PC3) - Decenas de día     
    CALL APAGAR_DISPLAYS     
     
    LDI ZL, LOW(DISPLAY*2)     
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, dia_d     
    ADD ZL, temp     
    LPM temp, Z     
    
    ; Si config_sel = 1 (configurando días) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 1    
    BRNE NO_BLINK_DIA_D   
    SBRC flags, 0    
    CLR temp ; Apagar segmento para efecto de parpadeo    
NO_BLINK_DIA_D:    
    OUT PORTD, temp     
    SBI PORTC, PC3     
    CALL RETARDO     
     
    ; Display 3 (PC2) - Unidades de día     
    CALL APAGAR_DISPLAYS  
    LDI ZL, LOW(DISPLAY*2)     
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, dia_u     
    ADD ZL, temp     
    LPM temp, Z     
    
    ; Si config_sel = 1 (configurando días) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 1   
    BRNE ADD_DOT_DIA    
    SBRC flags, 0    
    LDI temp, 0x80 ; Mantener solo el punto decimal para efecto de parpadeo    
ADD_DOT_DIA:    
    
    ; Añadir punto decimal siempre    
    ORI temp, 0x80     
    OUT PORTD, temp     
    SBI PORTC, PC2     
    CALL RETARDO     
     
    ; Display 2 (PC1) - Decenas de mes     
    CALL APAGAR_DISPLAYS     
     
    LDI ZL, LOW(DISPLAY*2)     
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, mes_d  
    ADD ZL, temp   
    LPM temp, Z     
    
    ; Si config_sel = 0 (configurando meses) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 0    
    BRNE NO_BLINK_MES_D    
    SBRC flags, 0    
    CLR temp ; Apagar segmento para efecto de parpadeo    
NO_BLINK_MES_D:    
    OUT PORTD, temp     
    SBI PORTC, PC1     
    CALL RETARDO     
     
    ; Display 1 (PC0) - Unidades de mes     
    CALL APAGAR_DISPLAYS     
     
    LDI ZL, LOW(DISPLAY*2)     
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, mes_u     
    ADD ZL, temp   
    LPM temp, Z     
    
    ; Si config_sel = 0 (configurando meses) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 0    
    BRNE NO_BLINK_MES_U  
    SBRC flags, 0    
    CLR temp ; Apagar segmento para efecto de parpadeo    
NO_BLINK_MES_U:    
    OUT PORTD, temp     
    SBI PORTC, PC0     
    CALL RETARDO     
    RET  

; Función para mostrar la configuración de alarma  
MOSTRAR_CONFIG_ALARMA:     
    ; Display 4 (PC3) - Decenas de horas de alarma     
    CALL APAGAR_DISPLAYS   
    LDI ZL, LOW(DISPLAY*2)    
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, alarm_hr_d     
    ADD ZL, temp     
    LPM temp, Z    
    
    ; Si config_sel = 1 (configurando horas) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 1    
    BRNE NO_BLINK_ALARM_HR_D    
    SBRC flags, 0    
    CLR temp ; Apagar segmento para efecto de parpadeo    
NO_BLINK_ALARM_HR_D:    
    OUT PORTD, temp     
    SBI PORTC, PC3     
    CALL RETARDO     
     
    ; Display 3 (PC2) - Unidades de horas de alarma   
    CALL APAGAR_DISPLAYS     
     
    LDI ZL, LOW(DISPLAY*2)     
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, alarm_hr_u     
    ADD ZL, temp     
    LPM temp, Z     
     
    ; Si config_sel = 1 (configurando horas) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 1    
    BRNE ADD_DOT_ALARM_HR    
    SBRC flags, 0    
    CLR temp ; Apagar segmento para efecto de parpadeo    
ADD_DOT_ALARM_HR:    
    
    ; Añadir punto decimal siempre    
    ORI temp, 0x80     
    OUT PORTD, temp     
    SBI PORTC, PC2   
    CALL RETARDO     
     
    ; Display 2 (PC1) - Decenas de minutos de alarma     
    CALL APAGAR_DISPLAYS     
     
    LDI ZL, LOW(DISPLAY*2)     
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, alarm_min_d     
    ADD ZL, temp     
    LPM temp, Z    
    
    ; Si config_sel = 0 (configurando minutos) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 0    
    BRNE NO_BLINK_ALARM_MIN_D    
    SBRC flags, 0    
    CLR temp ; Apagar segmento para efecto de parpadeo    
NO_BLINK_ALARM_MIN_D:    
    OUT PORTD, temp   
    SBI PORTC, PC1     
    CALL RETARDO     
     
    ; Display 1 (PC0) - Unidades de minutos de alarma     
    CALL APAGAR_DISPLAYS     
     
    LDI ZL, LOW(DISPLAY*2)     
    LDI ZH, HIGH(DISPLAY*2)     
    LDS temp, alarm_min_u     
    ADD ZL, temp     
    LPM temp, Z     
    
    ; Si config_sel = 0 (configurando minutos) y bit de parpadeo activado, apagar segmento    
    CPI config_sel, 0    
    BRNE NO_BLINK_ALARM_MIN_U    
    SBRC flags, 0    
    CLR temp ; Apagar segmento para efecto de parpadeo    
NO_BLINK_ALARM_MIN_U:   
    OUT PORTD, temp  
    SBI PORTC, PC0     
    CALL RETARDO     
    RET  
   
APAGAR_DISPLAYS:     
    CBI PORTC, PC0     
    CBI PORTC, PC1     
    CBI PORTC, PC2     
    CBI PORTC, PC3   
    RET     
   
RETARDO:     
    PUSH r17     
    LDI r17, 10     
LOOP_RETARDO:     
    DEC r17     
    BRNE LOOP_RETARDO     
    POP r17     
    RET     
   
; Función corregida para incrementar el tiempo correctamente     
INCREMENTAR_TIEMPO:  
    ; Incrementar segundos (no se muestran)     
    LDS temp, cont_sec    
    INC temp     
    CPI temp, 60   
    BRNE GUARDAR_SEC     
   
    ; Si segundos llega a 60, reiniciar y incrementar minutos     
    LDI temp, 0     
    STS cont_sec, temp     
   
    ; Incrementar unidades de minutos     
    LDS temp, cont_min_u     
    INC temp     
    CPI temp, 10     
    BRNE GUARDAR_MIN_U     
   
    ; Si unidades de minutos llega a 10, reiniciar e incrementar decenas     
    LDI temp, 0     
    STS cont_min_u, temp     
   
    ; Incrementar decenas de minutos   
    LDS temp, cont_min_d     
    INC temp     
    CPI temp, 6     
    BRNE GUARDAR_MIN_D  
    ; Si decenas de minutos llega a 6, reiniciar e incrementar horas     
    LDI temp, 0     
    STS cont_min_d, temp     
   
    ; Incrementar unidades de horas     
    LDS temp, cont_hr_u     
    INC temp     
   
    ; Verificar si estamos en 24 horas (23:59 -> 00:00)    
    LDS temp2, cont_hr_d     
    CPI temp2, 2   
    BRNE CHECK_HR_U_NORMAL     
    CPI temp, 4     
    BRNE CHECK_HR_U_NORMAL     
   
    ; Si llegamos a 24 horas, reiniciar a 00:00 e incrementar día     
    LDI temp, 0     
    STS cont_hr_u, temp     
    LDI temp, 0     
    STS cont_hr_d, temp     
   
    ; Incrementar día - ASEGURARNOS DE QUE ESTO SE EJECUTE     
    PUSH temp     
    PUSH temp2     
    CALL INCREMENTAR_DIA_AUTOMATICO     
    POP temp2  
    POP temp     
    RET     
   
CHECK_HR_U_NORMAL:     
    ; Verificar si unidades de hora llega a 10     
    CPI temp, 10     
    BRNE GUARDAR_HR_U     
   
    ; Si unidades de hora llega a 10, reiniciar e incrementar decenas     
    LDI temp, 0     
    STS cont_hr_u, temp     
   
    ; Incrementar decenas de horas     
    LDS temp, cont_hr_d    
    INC temp     
    STS cont_hr_d, temp     
    RET     
   
GUARDAR_HR_U:   
    STS cont_hr_u, temp     
    RET     
   
GUARDAR_MIN_D:     
    STS cont_min_d, temp     
    RET  
GUARDAR_MIN_U:     
    STS cont_min_u, temp     
    RET     
   
GUARDAR_SEC:     
    STS cont_sec, temp     
    RET     
    
; Función para incrementar horas (para botón PB1 en modo incremento)     
INCREMENTAR_HORAS:     
    ; Incrementar unidades de horas     
    LDS temp, cont_hr_u   
    INC temp     
   
    ; Verificar si estamos en 24 horas (23:59 -> 00:00)     
    LDS temp2, cont_hr_d     
    CPI temp2, 2     
    BRNE INC_HR_CHECK_U     
    CPI temp, 4     
    BRNE INC_HR_CHECK_U    
   
    ; Si llegamos a 24 horas, reiniciar a 00:00     
    LDI temp, 0     
    STS cont_hr_u, temp     
    LDI temp, 0     
    STS cont_hr_d, temp  
    RET     
   
INC_HR_CHECK_U:   
    ; Verificar si unidades de hora llega a 10     
    CPI temp, 10     
    BRNE INC_HR_SAVE_U     
   
    ; Si unidades de hora llega a 10, reiniciar e incrementar decenas     
    LDI temp, 0     
    STS cont_hr_u, temp     
   
    ; Incrementar decenas de horas     
    LDS temp, cont_hr_d     
    INC temp     
    STS cont_hr_d, temp     
    RET     
   
INC_HR_SAVE_U:     
    STS cont_hr_u, temp   
    RET     
    
; FUNCIÓN CORREGIDA: Decrementar horas (para botón PB2 en modo decremento)    
DECREMENTAR_HORAS:    
    ; Verificar si estamos en 00:xx    
    LDS temp, cont_hr_d    
    CPI temp, 0  
    BRNE DEC_HR_NOT_ZERO_D    
      
    LDS temp, cont_hr_u    
    CPI temp, 0    
    BRNE DEC_HR_NOT_ZERO_U    
      
    ; Si llegamos a 00 horas, cambiar a 23:00 (underflow)    
    LDI temp, 3    
    STS cont_hr_u, temp    
    LDI temp, 2    
    STS cont_hr_d, temp    
    RET    
      
DEC_HR_NOT_ZERO_U:    
    ; Decrementar unidades de hora    
    DEC temp    
    STS cont_hr_u, temp    
    RET   
DEC_HR_NOT_ZERO_D:    
    ; Si decenas > 0, verificar si unidades es 0    
    LDS temp, cont_hr_u    
    CPI temp, 0    
    BRNE DEC_HR_NOT_ZERO_U    
      
    ; Si unidades = 0, poner unidades en 9 y decrementar decenas    
    LDI temp, 9  
    STS cont_hr_u, temp    
    LDS temp, cont_hr_d    
    DEC temp    
    STS cont_hr_d, temp    
    RET    
    
; Función para incrementar minutos (para botón PB1 en modo incremento)     
INCREMENTAR_MINUTOS:     
    ; Incrementar unidades de minutos     
    LDS temp, cont_min_u     
    INC temp    
    CPI temp, 10     
    BRNE INC_MIN_SAVE_U   
    ; Si unidades de minutos llega a 10, reiniciar e incrementar decenas     
    LDI temp, 0     
    STS cont_min_u, temp     
   
    ; Incrementar decenas de minutos     
    LDS temp, cont_min_d     
    INC temp     
    CPI temp, 6     
    BRNE INC_MIN_SAVE_D     
   
    ; Si decenas de minutos llega a 6, reiniciar     
    LDI temp, 0  
INC_MIN_SAVE_D:     
    STS cont_min_d, temp     
    RET     
   
INC_MIN_SAVE_U:   
    STS cont_min_u, temp     
    RET     
    
; FUNCIÓN CORREGIDA: Decrementar minutos (para botón PB2 en modo decremento)    
DECREMENTAR_MINUTOS:    
    ; Verificar si estamos en xx:00    
    LDS temp, cont_min_d    
    CPI temp, 0    
    BRNE DEC_MIN_NOT_ZERO_D    
      
    LDS temp, cont_min_u    
    CPI temp, 0    
    BRNE DEC_MIN_NOT_ZERO_U    
      
    ; Si llegamos a 00 minutos, cambiar a xx:59 (underflow)    
    LDI temp, 9    
    STS cont_min_u, temp    
    LDI temp, 5    
    STS cont_min_d, temp    
    RET  
DEC_MIN_NOT_ZERO_U:    
    ; Decrementar unidades de minutos    
    DEC temp   
    STS cont_min_u, temp    
    RET    
      
DEC_MIN_NOT_ZERO_D:    
    ; Si decenas > 0, verificar si unidades es 0    
    LDS temp, cont_min_u    
    CPI temp, 0    
    BRNE DEC_MIN_NOT_ZERO_U    
      
    ; Si unidades = 0, poner unidades en 9 y decrementar decenas    
    LDI temp, 9    
    STS cont_min_u, temp    
    LDS temp, cont_min_d    
    DEC temp    
    STS cont_min_d, temp    
    RET    
   
; Función para incrementar el día automáticamente (cuando cambia de 23:59 a 00:00)     
INCREMENTAR_DIA_AUTOMATICO:     
    PUSH r20     
    PUSH r21     
    PUSH temp  
    PUSH temp2    
     
    ; Obtener días máximos del mes actual     
    CALL OBTENER_DIAS_MES     
    MOV r21, temp ; r21 = días máximos     
   
    ; Calcular el día actual (decenas*10 + unidades)     
    LDS r20, dia_d     
    LDI temp, 10     
   
    ; Multiplicación manual (r20 * 10)     
    CLR temp2     
    MOV resto, r20     
   
MULT_LOOP_DIA_AUTO:     
    CPI resto, 0     
    BREQ MULT_DONE_DIA_AUTO     
    ADD temp2, temp   
    DEC resto     
    RJMP MULT_LOOP_DIA_AUTO     
   
MULT_DONE_DIA_AUTO:     
    ; Añadir unidades     
    LDS r20, dia_u     
    ADD temp2, r20 ; temp2 = día completo  
    ; Incrementar día     
    INC temp2     
   
    ; Verificar si hemos superado el máximo de días del mes     
    CP temp2, r21     
    BRLO NO_CAMBIO_MES ; Si es menor, no hay cambio de mes     
    BRNE CAMBIO_MES ; Si no es igual (es mayor), cambiar mes     
    RJMP NO_CAMBIO_MES ; Si es igual, tampoco hay cambio de mes    
   
CAMBIO_MES:   
    ; Si hemos superado el máximo, reiniciar a día 1 e incrementar mes     
    LDI temp, 1     
    STS dia_u, temp     
    LDI temp, 0     
    STS dia_d, temp     
   
    ; Incrementar mes     
    CALL INCREMENTAR_MES_AUTOMATICO     
    POP temp2     
    POP temp     
    POP r21     
    POP r20     
    RET     
   
NO_CAMBIO_MES:     
    ; Si no hemos superado el máximo, actualizar día normalmente  
    MOV temp, temp2     
    LDI temp2, 10     
    CALL DIV ; temp = decenas, resto = unidades     
    STS dia_d, temp     
    MOV temp, resto     
    STS dia_u, temp     
    POP temp2     
    POP temp     
    POP r21    
    POP r20     
    RET     
   
; Función para incrementar el mes automáticamente     
INCREMENTAR_MES_AUTOMATICO:     
    PUSH temp   
    PUSH r20     
   
    ; Incrementar unidades de mes     
    LDS temp, mes_u     
    INC temp     
   
    ; Verificar si llegamos a mes 13     
    LDS r20, mes_d     
    CPI r20, 1     
    BRNE CHECK_MES_U_AUTO     
    CPI temp, 3  
    BRNE CHECK_MES_U_AUTO     
   
    ; Si llegamos a mes 13, reiniciar a mes 1     
    LDI temp, 1     
    STS mes_u, temp   
    LDI temp, 0     
    STS mes_d, temp     
   
    ; Verificar si el día actual es válido para el nuevo mes     
    CALL VALIDAR_DIA_ACTUAL     
    POP r20     
    POP temp     
    RET     
   
CHECK_MES_U_AUTO:    
    ; Verificar si unidades de mes llega a 10     
    CPI temp, 10     
    BRNE SAVE_MES_U_AUTO     
   
    ; Si unidades de mes llega a 10, reiniciar e incrementar decenas     
    LDI temp, 0     
    STS mes_u, temp   
    ; Incrementar decenas de mes     
    LDS temp, mes_d     
    INC temp     
    STS mes_d, temp  
    ; Verificar si el día actual es válido para el nuevo mes     
    CALL VALIDAR_DIA_ACTUAL     
    POP r20     
    POP temp     
    RET     
   
SAVE_MES_U_AUTO:     
    STS mes_u, temp     
   
    ; Verificar si el día actual es válido para el nuevo mes     
    CALL VALIDAR_DIA_ACTUAL     
    POP r20   
    POP temp     
    RET     
   
; Función para obtener el número máximo de días para el mes actual     
OBTENER_DIAS_MES:     
    PUSH r20     
    PUSH r21    
    PUSH temp2     
   
    ; Calcular el mes actual (decenas*10 + unidades)     
    LDS r20, mes_d     
    LDI r21, 10  
    ; Multiplicación manual (r20 * 10)     
    CLR temp     
    MOV temp2, r20     
   
MULT_LOOP_MES:     
    CPI temp2, 0   
    BREQ MULT_DONE_MES     
    ADD temp, r21     
    DEC temp2     
    RJMP MULT_LOOP_MES     
   
MULT_DONE_MES:     
    ; Añadir unidades     
    LDS r21, mes_u     
    ADD temp, r21 ; temp = mes completo     
   
    ; Verificar el mes y asignar días     
    CPI temp, 2 ; Febrero     
    BRNE CHECK_MES_30     
    LDI temp, 28 ; Febrero tiene 28 días (no consideramos años bisiestos)     
    RJMP FIN_OBTENER_DIAS     
   
CHECK_MES_30:   
    CPI temp, 4 ; Abril     
    BREQ MES_30     
    CPI temp, 6 ; Junio  
    BREQ MES_30     
    CPI temp, 9 ; Septiembre     
    BREQ MES_30     
    CPI temp, 11 ; Noviembre     
    BREQ MES_30     
   
    ; Si no es mes de 30 días, asumimos 31 días     
    LDI temp, 31     
    RJMP FIN_OBTENER_DIAS     
   
MES_30:     
    LDI temp, 30     
   
FIN_OBTENER_DIAS:   
    POP temp2     
    POP r21     
    POP r20     
    RET     
   
; Función para validar que el día actual sea válido para el mes actual     
VALIDAR_DIA_ACTUAL:     
    PUSH r20     
    PUSH r21     
    PUSH temp     
    PUSH temp2  
    ; Obtener días máximos del mes actual     
    CALL OBTENER_DIAS_MES     
    MOV r21, temp ; r21 = días máximos     
   
    ; Calcular el día actual (decenas*10 + unidades)    
    LDS r20, dia_d   
    LDI temp, 10     
   
    ; Multiplicación manual (r20 * 10)     
    CLR temp2     
    MOV temp, r20     
   
MULT_LOOP_DIA:     
    CPI temp, 0     
    BREQ MULT_DONE_DIA     
    ADD temp2, temp     
    DEC temp     
    RJMP MULT_LOOP_DIA     
   
MULT_DONE_DIA:     
    ; Añadir unidades     
    LDS r20, dia_u     
    ADD temp2, r20 ; temp2 = día completo   
    ; Si el día actual es mayor que el máximo, ajustar al máximo     
    CP temp2, r21     
    BRLO DIA_VALIDO  
    ; Ajustar al último día del mes     
    MOV temp, r21     
   
    ; Calcular decenas y unidades     
    LDI temp2, 10     
    CALL DIV ; temp = decenas, resto = unidades     
    STS dia_d, temp     
    MOV temp, resto     
    STS dia_u, temp    
   
DIA_VALIDO:     
    POP temp2   
    POP temp     
    POP r21     
    POP r20     
    RET     
   
; Función auxiliar para división - CORREGIDA     
DIV:     
    ; Divide temp entre temp2, resultado en temp, resto en resto (r22)     
    PUSH r21     
    CLR r21 ; r21 será nuestro contador (cociente)     
   
DIV_LOOP:     
    CP temp, temp2  
    BRLO DIV_END ; Si temp < temp2, terminamos     
    SUB temp, temp2 ; temp = temp - temp2     
    INC r21 ; Incrementar cociente     
    RJMP DIV_LOOP     
   
DIV_END:     
    MOV resto, temp ; Guardar resto en registro resto     
    MOV temp, r21 ; Poner cociente en temp     
    POP r21     
    RET     
   
; FUNCIÓN MODIFICADA: Ahora permite incrementar o decrementar horas/días    
BOTON_HORAS:   
    ; Verificar en qué modo estamos     
    CPI modo, 2     
    BRNE CHECK_MODO_FECHA_DIAS  
    
    ; Modo configuración hora    
    ; Verificar si estamos configurando horas (config_sel = 1)    
    CPI config_sel, 1    
    BRNE FIN_BOTON_HORAS  ; Si no estamos configurando horas, ignorar botón    
      
    ; Incrementar horas si estamos presionando PB1, decrementar si PB2    
    SBIS PINB, PB1  ; Si PB1 está presionado (incrementar)    
    CALL INCREMENTAR_HORAS  
    SBIS PINB, PB2  ; Si PB2 está presionado (decrementar)    
    CALL DECREMENTAR_HORAS    
      
    RET    
      
CHECK_MODO_FECHA_DIAS:     
    CPI modo, 3     
    BRNE CHECK_MODO_ALARMA_HORAS  
      
    ; Modo configuración fecha    
    ; Verificar si estamos configurando días (config_sel = 1)    
    CPI config_sel, 1    
    BRNE FIN_BOTON_HORAS  ; Si no estamos configurando días, ignorar botón   
    ; Incrementar días si estamos presionando PB1, decrementar si PB2    
    SBIS PINB, PB1  ; Si PB1 está presionado (incrementar)    
    CALL INCREMENTAR_DIAS    
      
    SBIS PINB, PB2  ; Si PB2 está presionado (decrementar)    
    CALL DECREMENTAR_DIAS  
    RET  

CHECK_MODO_ALARMA_HORAS:  
    CPI modo, 4  
    BRNE FIN_BOTON_HORAS  

    ; Modo configuración alarma  
    ; Verificar si estamos configurando horas (config_sel = 1)  
    CPI config_sel, 1  
    BRNE FIN_BOTON_HORAS  ; Si no estamos configurando horas, ignorar botón  

    ; Incrementar horas si estamos presionando PB1, decrementar si PB2  
    SBIS PINB, PB1  ; Si PB1 está presionado (incrementar)  
    CALL INCREMENTAR_HORAS_ALARMA  

    SBIS PINB, PB2  ; Si PB2 está presionado (decrementar)  
    CALL DECREMENTAR_HORAS_ALARMA  
      
FIN_BOTON_HORAS:     
    RET     
    
; FUNCIÓN MODIFICADA: Ahora permite incrementar o decrementar minutos/meses    
BOTON_MINUTOS:    
    ; Verificar en qué modo estamos  
    CPI modo, 2    
    BRNE CHECK_CONFIG_FECHA_MESES    
      
    ; Modo configuración hora    
    ; Verificar si estamos configurando minutos (config_sel = 0)    
    CPI config_sel, 0    
    BRNE FIN_BOTON_MINUTOS  ; Si no estamos configurando minutos, ignorar botón    
      
    ; Incrementar minutos si estamos presionando PB1, decrementar si PB2    
    SBIS PINB, PB1  ; Si PB1 está presionado (incrementar)    
    CALL INCREMENTAR_MINUTOS   
    SBIS PINB, PB2  ; Si PB2 está presionado (decrementar)    
    CALL DECREMENTAR_MINUTOS    
      
    RET    
      
CHECK_CONFIG_FECHA_MESES:    
    CPI modo, 3    
    BRNE CHECK_CONFIG_ALARMA_MINUTOS    
      
    ; Modo configuración fecha    
    ; Verificar si estamos configurando meses (config_sel = 0)    
    CPI config_sel, 0    
    BRNE FIN_BOTON_MINUTOS  ; Si no estamos configurando meses, ignorar botón    
      
    ; Incrementar meses si estamos presionando PB1, decrementar si PB2  
    SBIS PINB, PB1  ; Si PB1 está presionado (incrementar)    
    CALL INCREMENTAR_MESES    
      
    SBIS PINB, PB2  ; Si PB2 está presionado (decrementar)    
    CALL DECREMENTAR_MESES  
    RET  

CHECK_CONFIG_ALARMA_MINUTOS:  
    CPI modo, 4  
    BRNE FIN_BOTON_MINUTOS  

    ; Modo configuración alarma  
    ; Verificar si estamos configurando minutos (config_sel = 0)  
    CPI config_sel, 0  
    BRNE FIN_BOTON_MINUTOS  ; Si no estamos configurando minutos, ignorar botón  

    ; Incrementar minutos si estamos presionando PB1, decrementar si PB2  
    SBIS PINB, PB1  ; Si PB1 está presionado (incrementar)  
    CALL INCREMENTAR_MINUTOS_ALARMA  

    SBIS PINB, PB2  ; Si PB2 está presionado (decrementar)  
    CALL DECREMENTAR_MINUTOS_ALARMA  
      
FIN_BOTON_MINUTOS:    
    RET    
    
; FUNCIÓN: Cambiar entre configurar horas/minutos o días/meses    
CAMBIAR_CONFIG_SEL:   
    ; Alternar entre 0 y 1    
    LDI temp, 1    
    EOR config_sel, temp    
    RET    
    
; Función para incrementar días    
INCREMENTAR_DIAS:     
    PUSH r20     
    PUSH r21     
    PUSH temp     
    PUSH temp2     
      
    ; Obtener días máximos del mes actual     
    CALL OBTENER_DIAS_MES     
    MOV r21, temp ; r21 = días máximos  
    ; Calcular el día actual (decenas*10 + unidades)     
    LDS r20, dia_d     
    LDI temp, 10     
      
    ; Multiplicación manual (r20 * 10)     
    CLR temp2     
    MOV resto, r20     
   
MULT_LOOP_DIA_BOTON_INC:     
    CPI resto, 0     
    BREQ MULT_DONE_DIA_BOTON_INC   
    ADD temp2, temp     
    DEC resto     
    RJMP MULT_LOOP_DIA_BOTON_INC     
   
MULT_DONE_DIA_BOTON_INC:     
    ; Añadir unidades     
    LDS r20, dia_u     
    ADD temp2, r20 ; temp2 = día completo     
      
    ; Incrementar día     
    INC temp2     
      
    ; Verificar si hemos superado el máximo de días del mes     
    CP temp2, r21  
    BRLO NO_OVERFLOW_DIA_INC ; Si es menor, no hay overflow     
    BRNE OVERFLOW_DIA_INC ; Si no es igual (es mayor), hacer overflow     
    RJMP NO_OVERFLOW_DIA_INC ; Si es igual, tampoco hay overflow     
      
OVERFLOW_DIA_INC:     
    ; Si hemos superado el máximo, reiniciar a día 1     
    LDI temp, 1     
    STS dia_u, temp     
    LDI temp, 0     
    STS dia_d, temp     
      
    POP temp2   
    POP temp     
    POP r21     
    POP r20     
    RET     
      
NO_OVERFLOW_DIA_INC:     
    ; Si no hemos superado el máximo, actualizar día normalmente     
    MOV temp, temp2     
    LDI temp2, 10     
    CALL DIV ; temp = decenas, resto = unidades     
    STS dia_d, temp     
    MOV temp, resto     
    STS dia_u, temp  
    POP temp2     
    POP temp     
    POP r21     
    POP r20     
    RET    
    
; FUNCIÓN CORREGIDA: Decrementar días    
DECREMENTAR_DIAS:    
    PUSH r20    
    PUSH r21    
    PUSH temp    
    PUSH temp2   
    ; Calcular el día actual (decenas*10 + unidades)    
    LDS r20, dia_d    
    LDI temp, 10    
      
    ; Multiplicación manual (r20 * 10)    
    CLR temp2    
    MOV resto, r20    
   
MULT_LOOP_DIA_BOTON_DEC:    
    CPI resto, 0    
    BREQ MULT_DONE_DIA_BOTON_DEC    
    ADD temp2, temp    
    DEC resto    
    RJMP MULT_LOOP_DIA_BOTON_DEC  
MULT_DONE_DIA_BOTON_DEC:    
    ; Añadir unidades    
    LDS r20, dia_u    
    ADD temp2, r20 ; temp2 = día completo    
      
    ; Verificar si estamos en día 1    
    CPI temp2, 1    
    BRNE NO_UNDERFLOW_DIA    
      
    ; Si es día 1, cambiar al último día del mes    
    CALL OBTENER_DIAS_MES   
    MOV temp2, temp ; temp2 = último día del mes    
    RJMP ACTUALIZAR_DIA_DEC    
      
NO_UNDERFLOW_DIA:    
    ; Si no es día 1, simplemente decrementar    
    DEC temp2    
      
ACTUALIZAR_DIA_DEC:    
    ; Actualizar día    
    MOV temp, temp2    
    LDI temp2, 10    
    CALL DIV ; temp = decenas, resto = unidades    
    STS dia_d, temp    
    MOV temp, resto  
    STS dia_u, temp    
      
    POP temp2    
    POP temp    
    POP r21    
    POP r20    
    RET    
    
; Función para incrementar meses     
INCREMENTAR_MESES:     
    PUSH r20     
    PUSH temp   
    ; Incrementar unidades de mes     
    LDS temp, mes_u     
    INC temp     
      
    ; Verificar si llegamos a mes 13     
    LDS r20, mes_d     
    CPI r20, 1     
    BRNE CHECK_MES_U     
    CPI temp, 3     
    BRNE CHECK_MES_U     
      
    ; Si llegamos a mes 13, reiniciar a mes 1     
    LDI temp, 1     
    STS mes_u, temp  
    LDI temp, 0     
    STS mes_d, temp     
      
    ; Verificar si el día actual es válido para el nuevo mes     
    CALL VALIDAR_DIA_ACTUAL     
      
    POP temp     
    POP r20     
    RET     
      
CHECK_MES_U:   
    ; Verificar si unidades de mes llega a 10     
    CPI temp, 10     
    BRNE SAVE_MES_U     
      
    ; Si unidades de mes llega a 10, reiniciar e incrementar decenas     
    LDI temp, 0     
    STS mes_u, temp     
      
    ; Incrementar decenas de mes     
    LDS temp, mes_d     
    INC temp     
    STS mes_d, temp     
      
    ; Verificar si el día actual es válido para el nuevo mes     
    CALL VALIDAR_DIA_ACTUAL  
    POP temp     
    POP r20     
    RET     
      
SAVE_MES_U:     
    STS mes_u, temp     
      
    ; Verificar si el día actual es válido para el nuevo mes     
    CALL VALIDAR_DIA_ACTUAL   
    POP temp     
    POP r20     
    RET    
    
; FUNCIÓN CORREGIDA: Decrementar meses (usando registros válidos)    
DECREMENTAR_MESES:   
    PUSH r20   
    PUSH r21   
    PUSH temp   
    PUSH temp2   
   
    ; Calcular el mes actual (decenas*10 + unidades)   
    LDS r20, mes_d          ; Cargar decenas del mes   
    LDI r21, 10             ; Base decimal   
    CLR temp2               ; Inicializar acumulador  
    ; Multiplicar decenas por 10   
    MOV resto, r20          ; Contador de decenas   
MULT_LOOP_MES_DEC:   
    CPI resto, 0   
    BREQ MULT_DONE_MES_DEC   
    ADD temp2, r21          ; temp2 += 10   
    DEC resto   
    RJMP MULT_LOOP_MES_DEC   
   
MULT_DONE_MES_DEC:   
    ; Sumar unidades del mes   
    LDS r20, mes_u   
    ADD temp2, r20          ; temp2 = mes completo (1-12)   
   
    ; Verificar si el mes es 1 (underflow a 12)   
    CPI temp2, 1   
    BRNE NO_UNDERFLOW_MES   
   
    ; Cambiar a mes 12 (diciembre)   
    LDI temp, 1             ; mes_d = 1 (decena)   
    STS mes_d, temp   
    LDI temp, 2             ; mes_u = 2 (unidad)   
    STS mes_u, temp   
    RJMP VALIDAR_MES_DEC   
   
NO_UNDERFLOW_MES:  
    ; Decrementar unidades del mes   
    LDS temp, mes_u   
    CPI temp, 0   
    BRNE DEC_MES_U          ; Si unidades != 0, decrementar normalmente   
   
    ; Si unidades es 0 (ej: 10 ? 09)   
    LDI temp, 9             ; mes_u = 9   
    STS mes_u, temp   
    LDS temp, mes_d   
    DEC temp                ; mes_d -= 1 (ej: 1 ? 0 para 10 ? 09)   
    STS mes_d, temp   
    RJMP VALIDAR_MES_DEC   
   
DEC_MES_U:   
    ; Decrementar unidades normalmente   
    DEC temp   
    STS mes_u, temp   
   
VALIDAR_MES_DEC:   
    ; Asegurar que el día actual sea válido para el nuevo mes   
    CALL VALIDAR_DIA_ACTUAL   
   
    POP temp2   
    POP temp   
    POP r21   
    POP r20  
    RET  

; Funciones para manejar la alarma  
; Incrementar horas de alarma  
INCREMENTAR_HORAS_ALARMA:  
    ; Incrementar unidades de horas de alarma  
    LDS temp, alarm_hr_u  
    INC temp  
   
    ; Verificar si llegamos a 24 horas  
    LDS temp2, alarm_hr_d  
    CPI temp2, 2  
    BRNE INC_ALARM_HR_CHECK_U  
    CPI temp, 4  
    BRNE INC_ALARM_HR_CHECK_U  
   
    ; Si llegamos a 24 horas, reiniciar a 00:00  
    LDI temp, 0  
    STS alarm_hr_u, temp  
    LDI temp, 0  
    STS alarm_hr_d, temp  
    RET  
   
INC_ALARM_HR_CHECK_U:  
    ; Verificar si unidades de hora llega a 10  
    CPI temp, 10  
    BRNE INC_ALARM_HR_SAVE_U  
   
    ; Si unidades llega a 10, reiniciar e incrementar decenas  
    LDI temp, 0  
    STS alarm_hr_u, temp  
   
    ; Incrementar decenas de horas  
    LDS temp, alarm_hr_d  
    INC temp  
    STS alarm_hr_d, temp  
    RET  
   
INC_ALARM_HR_SAVE_U:  
    STS alarm_hr_u, temp  
    RET  

; Decrementar horas de alarma  
DECREMENTAR_HORAS_ALARMA:  
    ; Verificar si estamos en 00:xx  
    LDS temp, alarm_hr_d  
    CPI temp, 0  
    BRNE DEC_ALARM_HR_NOT_ZERO_D  
      
    LDS temp, alarm_hr_u  
    CPI temp, 0  
    BRNE DEC_ALARM_HR_NOT_ZERO_U  
      
    ; Si llegamos a 00 horas, cambiar a 23:xx (underflow)  
    LDI temp, 3  
    STS alarm_hr_u, temp  
    LDI temp, 2  
    STS alarm_hr_d, temp  
    RET  
      
DEC_ALARM_HR_NOT_ZERO_U:  
    ; Decrementar unidades de hora  
    DEC temp  
    STS alarm_hr_u, temp  
    RET  

DEC_ALARM_HR_NOT_ZERO_D:  
    ; Si decenas > 0, verificar si unidades es 0  
    LDS temp, alarm_hr_u  
    CPI temp, 0  
    BRNE DEC_ALARM_HR_NOT_ZERO_U  
      
    ; Si unidades = 0, poner unidades en 9 y decrementar decenas  
    LDI temp, 9  
    STS alarm_hr_u, temp  
    LDS temp, alarm_hr_d  
    DEC temp  
    STS alarm_hr_d, temp  
    RET  

; Incrementar minutos de alarma  
INCREMENTAR_MINUTOS_ALARMA:  
    ; Incrementar unidades de minutos  
    LDS temp, alarm_min_u  
    INC temp  
    CPI temp, 10  
    BRNE INC_ALARM_MIN_SAVE_U  
   
    ; Si unidades llega a 10, reiniciar e incrementar decenas  
    LDI temp, 0  
    STS alarm_min_u, temp  
   
    ; Incrementar decenas de minutos  
    LDS temp, alarm_min_d  
    INC temp  
    CPI temp, 6  
    BRNE INC_ALARM_MIN_SAVE_D  
   
    ; Si decenas llega a 6, reiniciar  
    LDI temp, 0  

INC_ALARM_MIN_SAVE_D:  
    STS alarm_min_d, temp  
    RET  
   
INC_ALARM_MIN_SAVE_U:  
    STS alarm_min_u, temp  
    RET  

; Decrementar minutos de alarma  
DECREMENTAR_MINUTOS_ALARMA:  
    ; Verificar si estamos en xx:00  
    LDS temp, alarm_min_d  
    CPI temp, 0  
    BRNE DEC_ALARM_MIN_NOT_ZERO_D  
      
    LDS temp, alarm_min_u  
    CPI temp, 0  
    BRNE DEC_ALARM_MIN_NOT_ZERO_U  
      
    ; Si llegamos a 00 minutos, cambiar a xx:59 (underflow)  
    LDI temp, 9  
    STS alarm_min_u, temp  
    LDI temp, 5  
    STS alarm_min_d, temp  
    RET  

DEC_ALARM_MIN_NOT_ZERO_U:  
    ; Decrementar unidades de minutos  
    DEC temp  
    STS alarm_min_u, temp  
    RET  
      
DEC_ALARM_MIN_NOT_ZERO_D:  
    ; Si decenas > 0, verificar si unidades es 0  
    LDS temp, alarm_min_u  
    CPI temp, 0  
    BRNE DEC_ALARM_MIN_NOT_ZERO_U  
      
    ; Si unidades = 0, poner unidades en 9 y decrementar decenas  
    LDI temp, 9  
    STS alarm_min_u, temp  
    LDS temp, alarm_min_d  
    DEC temp  
    STS alarm_min_d, temp  
    RET  

; Verificar si la hora actual coincide con la hora de la alarma  
VERIFICAR_ALARMA:   
    PUSH temp   
    PUSH temp2   
   
    ; Verificar si la alarma ya está activa   
    LDS temp, alarm_active   
    CPI temp, 1   
    BREQ FIN_VERIFICAR_ALARMA ; Si ya está activa, no hacer nada más   
    
    ; NUEVO: Verificar bit de alarma apagada manualmente  
    SBRC flags, 1  ; Saltar siguiente instrucción si bit 1 está borrado  
    RJMP COMPROBAR_CAMBIO_HORA  ; Si alarma fue apagada, verificar si cambió la hora  
   
CONTINUAR_VERIFICACION:  
    ; Comparar horas   
    LDS temp, cont_hr_d   
    LDS temp2, alarm_hr_d   
    CP temp, temp2   
    BRNE FIN_VERIFICAR_ALARMA ; Si decenas de hora no coinciden, salir   
   
    LDS temp, cont_hr_u   
    LDS temp2, alarm_hr_u   
    CP temp, temp2   
    BRNE FIN_VERIFICAR_ALARMA ; Si unidades de hora no coinciden, salir   
   
    ; Comparar minutos   
    LDS temp, cont_min_d   
    LDS temp2, alarm_min_d   
    CP temp, temp2   
    BRNE FIN_VERIFICAR_ALARMA ; Si decenas de minutos no coinciden, salir  
    
    LDS temp, cont_min_u   
    LDS temp2, alarm_min_u   
    CP temp, temp2   
    BRNE FIN_VERIFICAR_ALARMA ; Si unidades de minutos no coinciden, salir   
   
    ; Si todo coincide, activar la alarma   
    LDI temp, 1   
    STS alarm_active, temp   
    LDI temp, 0   
    STS alarm_counter, temp   
    SBI PORTB, PB5 ; Encender LED de alarma (PB5)   
    RJMP FIN_VERIFICAR_ALARMA  
    
COMPROBAR_CAMBIO_HORA:  
    ; Verificar si la hora actual ya no coincide con la hora de alarma  
    ; para limpiar el bit de alarma apagada manualmente  
    
    ; Comparar horas  
    LDS temp, cont_hr_d  
    LDS temp2, alarm_hr_d  
    CP temp, temp2  
    BRNE RESET_ALARM_FLAG  
    
    LDS temp, cont_hr_u  
    LDS temp2, alarm_hr_u  
    CP temp, temp2  
    BRNE RESET_ALARM_FLAG  
    
    ; Comparar minutos  
    LDS temp, cont_min_d  
    LDS temp2, alarm_min_d  
    CP temp, temp2  
    BRNE RESET_ALARM_FLAG  
    
    LDS temp, cont_min_u  
    LDS temp2, alarm_min_u  
    CP temp, temp2  
    BRNE RESET_ALARM_FLAG  
    
    ; Si todavía coincide la hora, mantener bit y salir  
    RJMP FIN_VERIFICAR_ALARMA  
    
RESET_ALARM_FLAG:  
    ; La hora ya no coincide, resetear bit de alarma apagada  
    ANDI flags, ~(1<<1)  ; Limpiar bit 1  
    RJMP CONTINUAR_VERIFICACION  ; Ahora sí verificar la alarma  
   
FIN_VERIFICAR_ALARMA:   
    POP temp2   
    POP temp   
    RET  
    
; FUNCIÓN CORREGIDA: Manejo del temporizador con incrementos no deseados corregidos    
TMR0_ISR:   
    PUSH temp   
    IN temp, SREG   
    PUSH temp   
    PUSH temp2   
   
    LDI temp, 0  
    OUT TCNT0, temp   
   
    ; Incrementar contador LED   
    LDS temp, led_timer   
    INC temp   
    STS led_timer, temp   
   
    CPI temp, 30  
    BRNE SKIP_LED   
    LDI temp, 0   
    STS led_timer, temp   
   
    ; Toggle flag de parpadeo   
    LDI temp, 0x01   
    EOR flags, temp  

    CPI modo, 2 ; Modo config hora   
    BRNE CHECK_LED_MODO_3   
    ; Parpadear PB4   
    IN temp, PORTB   
    LDI temp2, (1<<PB4)   
    EOR temp, temp2   
    OUT PORTB, temp   
    RJMP SKIP_LED   
   
CHECK_LED_MODO_3:   
    CPI modo, 3 ; Modo config fecha   
    BRNE CHECK_LED_MODO_4  
    ; Parpadear PC4   
    IN temp, PORTC   
    LDI temp2, (1<<PC4)   
    EOR temp, temp2   
    OUT PORTC, temp  
    RJMP SKIP_LED  

CHECK_LED_MODO_4:  
    CPI modo, 4 ; Modo config alarma  
    BRNE SKIP_LED  
    ; Parpadear PB4  
    IN temp, PORTB  
    LDI temp2, (1<<PB4)  
    EOR temp, temp2  
    OUT PORTB, temp  
   
SKIP_LED:     
    ; Incrementar contador principal     
    LDS temp, contador     
    INC temp     
    STS contador, temp     
    CPI temp, 61 ; Aproximadamente 1 segundo  
    BRNE CHECK_ALARMA_ACTIVA  
      
    LDI temp, 0     
    STS contador, temp     
      
    ; Solo incrementar tiempo si NO estamos en modo configuración    
    ; PUNTO CRÍTICO: Verificar explícitamente los modos   
    CPI modo, 0    
    BRNE CHECK_MODO_FECHA_AUTO    
    ; Si modo = 0 (reloj), incrementar tiempo    
    CALL INCREMENTAR_TIEMPO  
    CALL VERIFICAR_ALARMA ; Verificar si hay que activar la alarma  
    RJMP CHECK_ALARMA_ACTIVA  
      
CHECK_MODO_FECHA_AUTO:    
    CPI modo, 1    
    BRNE CHECK_ALARMA_ACTIVA  ; Si no es modo 0 ni 1, no incrementar  

CHECK_ALARMA_ACTIVA:  
    ; Verificar si la alarma está activa  
    LDS temp, alarm_active  
    CPI temp, 1  
    BRNE FIN_ISR  

    ; Incrementar contador de alarma  
    LDS temp, alarm_counter  
    INC temp  
    STS alarm_counter, temp  
    CPI temp, 30 ; 30 segundos  
    BRLO FIN_ISR  

    ; Si ha pasado 30 segundos, desactivar alarma  
    LDI temp, 0  
    STS alarm_active, temp  
    STS alarm_counter, temp  
    CBI PORTB, PB5 ; Apagar LED de alarma  
      
FIN_ISR:     
    POP temp2     
    POP temp     
    OUT SREG, temp     
    POP temp     
    RETI  
    
; VERSIÓN CORREGIDA: Rutina ISR_PCINT0 para incluir PB3    
ISR_PCINT0:     
    PUSH temp     
    IN temp, SREG     
    PUSH temp     
    PUSH temp2   
    ; Verificar botón PB0 (modo)     
    SBIC PINB, PB0     
    RJMP CHECK_PB1_PRESS    
      
    ; Cambiar modo    
    CALL CAMBIAR_MODO     
    RJMP FIN_PCINT0     
      
CHECK_PB1_PRESS:     
    ; Verificar botón PB1 (incrementar)     
    SBIC PINB, PB1     
    RJMP CHECK_PB2_PRESS    
      
    ; Acción según modo (incrementar)    
    CPI modo, 2    
    BRLO FIN_PCINT0  ; Si modo < 2, ignorar    
      
    ; En modo configuración, manejar botones a través de las funciones específicas    
    CALL BOTON_HORAS  
    CALL BOTON_MINUTOS    
    RJMP FIN_PCINT0     
      
CHECK_PB2_PRESS:      
    ; Verificar botón PB2 (decrementar)      
    SBIC PINB, PB2    
    RJMP CHECK_PB3_PRESS  

    ; NUEVA FUNCIONALIDAD: Verificar si estamos en modo hora (MODO=0) y la alarma está activa  
    CPI modo, 0  
    BRNE CHECK_MODO_CONFIG  ; Si no estamos en modo hora, verificar el modo configuración  
    
    ; Estamos en modo hora, verificar si la alarma está activa  
    LDS temp, alarm_active  
    CPI temp, 1  
    BRNE CHECK_MODO_CONFIG  ; Si la alarma no está activa, verificar el modo configuración  
    
    ; La alarma está activa y estamos en modo hora, apagar la alarma  
    LDI temp, 0  
    STS alarm_active, temp  
    STS alarm_counter, temp  
    CBI PORTB, PB5  ; Apagar LED de alarma  
    
    ; Establecer bit 1 de flags para indicar alarma apagada manualmente  
    ORI flags, (1<<1)  ; Establecer bit 1  
    
    RJMP FIN_PCINT0  
      
CHECK_MODO_CONFIG:  
    ; Acción según modo (decrementar)     
    CPI modo, 2  
    BRLO FIN_PCINT0  ; Si modo < 2, ignorar     
       
    ; En modo configuración, manejar botones a través de las funciones específicas     
    CALL BOTON_HORAS     
    CALL BOTON_MINUTOS     
    RJMP FIN_PCINT0

CHECK_PB3_PRESS:    
    ; Verificar botón PB3 (cambiar selección)    
    SBIC PINB, PB3    
    RJMP FIN_PCINT0    
      
    ; Solo cambiar selección si estamos en modo configuración    
    CPI modo, 2    
    BRLO FIN_PCINT0  ; Si modo < 2, ignorar  
    ; Cambiar entre hora/minutos o día/mes    
    CALL CAMBIAR_CONFIG_SEL    
      
FIN_PCINT0:     
    POP temp2     
    POP temp   
    OUT SREG, temp     
    POP temp     
    RETI     
   
; Función para cambiar el modo (separada para mejor organización)     
CAMBIAR_MODO:     
    ; Cambiar modo     
    INC modo     
    CPI modo, 5     
    BRNE ACTUALIZAR_MODO_CAMBIO     
    CLR modo     
      
ACTUALIZAR_MODO_CAMBIO:     
    ; Resetear selección a 1 (horas o días) cuando cambia el modo    
    LDI temp, 1    
    MOV config_sel, temp    
      
    CALL ACTUALIZAR_LEDS_MODO     
    RET  