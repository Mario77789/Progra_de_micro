/*
 * Maestro_Proyecto1_Digt2.c
 *
 * Created: 10/08/2025 18:10:50
 * Author : mario
 */ 



#define F_CPU 16000000UL
#include <avr/io.h>
#include <util/delay.h>
#include <stdio.h>
#include <avr/interrupt.h>
#include <stdint.h>
#include "LCD8bits/LCD8bits.h"
#include "I2C/I2C.h"
#include "UART/UART.h"
#include "TSL2561/TSL2561.h"

// ---------------- Configuración ----------------
#define SLAVE1_ADDR        0x20    // ultrasónico
#define SLAVE2_ADDR        0x21    // DHT11
#define CMD_MEASURE        0x01
#define UART_BAUD          9600

// Tiempos esclavos
#define S1_PREP_MS         40      // SRF05 ~30 ms
#define S1_RETRY_MS        15
#define S1_MAX_TRIES       5

#define S3_PREP_MS         40      // DHT11 ~20-30 ms de trama; margen
#define S3_RETRY_MS        100
#define S3_MAX_TRIES       3
#define S3_MIN_PERIOD_MS   1000    // DHT11 máx ~1 Hz

// TSL2561 (en maestro)
#define LUX_PERIOD_MS      500
#define LUX_FULL_SCALE     1000.0f // a 2/3 y 1/3 de esto se cambian niveles

// UI
#define PAGE_PERIOD_MS     1000    // rota S1/S2/S3 cada 1 s

// ---------------- millis() ----------------
volatile uint32_t g_millis = 0;
ISR(TIMER0_OVF_vect){ g_millis++; }

static void timer0_millis_init(void){
    TCCR0A = 0;
    TCCR0B = (1<<CS01)|(1<<CS00); // /64 -> ~1.024ms/overflow
    TIMSK0 = (1<<TOIE0);
}
static inline uint32_t millis(void){
    uint32_t m; uint8_t s=SREG; cli(); m=g_millis; SREG=s; return m;
}

// ---------------- LED D10 (PB2/OC1B) 3 niveles ----------------
static void ledpwm_init(void){
    DDRB |= (1<<PB2);                      // D10 salida
    TCCR1A = (1<<COM1B1) | (1<<WGM10);     // Fast PWM 8-bit, OC1B no invertido
    TCCR1B = (1<<WGM12)  | (1<<CS11)|(1<<CS10); // /64
    OCR1B  = 0;
}
static inline void ledpwm_set(uint8_t duty){ OCR1B = duty; }

// 3 niveles: lux >= 2/3 FS -> 0% ; 1/3 FS..2/3 FS -> 50% ; lux < 1/3 FS -> 100%
static void led_set_from_lux(float lux){
    float t1 = (LUX_FULL_SCALE/3.0f);
    float t2 = (2.0f*LUX_FULL_SCALE/3.0f);
    uint8_t duty;
    if (lux >= t2)      duty = 0;     // mucha luz -> LED apagado
    else if (lux >= t1) duty = 128;   // luz media -> 50%
    else                duty = 255;   // poca luz -> 100%
    ledpwm_set(duty);
}

// ---------------- I2C helpers maestro ----------------
static uint8_t slave_send_prepare(uint8_t addr){
    uint8_t st = I2C_Start((addr<<1)|TW_WRITE);
    if (st != TW_MT_SLA_ACK){ I2C_Stop(); return 0; }
    st = I2C_Write(CMD_MEASURE);
    if (st != TW_MT_DATA_ACK){ I2C_Stop(); return 0; }
    I2C_Stop(); return 1;
}
static uint8_t slave_read_u8(uint8_t addr, uint8_t* out){
    uint8_t st = I2C_Start((addr<<1)|TW_READ);
    if (st != TW_MR_SLA_ACK){ I2C_Stop(); return 0; }
    *out = I2C_ReadNACK();
    I2C_Stop(); return 1;
}

// ---------------- Máquinas de estado S1 (cm) y S3 (°C) ----------------
typedef enum { ST_IDLE=0, ST_SENT_PREP, ST_WAIT, ST_TRY_READ } turn_state_t;

typedef struct {
    uint8_t    addr;
    uint16_t   prep_ms, retry_ms;
    uint8_t    max_tries;
    // runtime
    turn_state_t st;
    uint32_t   next_deadline;
    uint8_t    tries_left;
    uint8_t    last_ok;
    uint8_t    last_val;     // cm para S1, °C para S3 (0xFF error)
    // pacing (solo S3)
    uint32_t   next_period_ms;
} turn_ctx_t;

static void turn_init(turn_ctx_t* c, uint8_t addr, uint16_t prep, uint16_t retry, uint8_t tries){
    c->addr = addr; c->prep_ms=prep; c->retry_ms=retry; c->max_tries=tries;
    c->st=ST_IDLE; c->next_deadline=0; c->tries_left=tries; c->last_ok=0; c->last_val=0xFF; c->next_period_ms=0;
}

static void turn_step(turn_ctx_t* c, uint16_t min_period_ms){
    uint32_t now = millis();

    // Respeta periodo mínimo (para DHT11)
    if (min_period_ms && (int32_t)(now - c->next_period_ms) < 0) return;

    switch(c->st){
        case ST_IDLE:{
            if (slave_send_prepare(c->addr)){
                c->st = ST_SENT_PREP;
            }else{
                c->last_ok=0; c->last_val=0xFF;
                c->next_deadline = now + c->retry_ms;
                c->st = ST_WAIT;
            }
        } break;

        case ST_SENT_PREP:{
            c->tries_left = c->max_tries;
            c->next_deadline = now + c->prep_ms;
            c->st = ST_WAIT;
        } break;

        case ST_WAIT:{
            if ((int32_t)(now - c->next_deadline) >= 0){
                c->st = ST_TRY_READ;
            }
        } break;

        case ST_TRY_READ:{
            uint8_t v=0xFF, ok = slave_read_u8(c->addr, &v);
            if (ok && v != 0xFF){
                c->last_ok=1; c->last_val=v;
                c->st=ST_IDLE;
                if (min_period_ms) c->next_period_ms = now + min_period_ms; // DHT11 pacing
            }else{
                c->last_ok=0; c->last_val=v;
                if (c->tries_left){
                    c->tries_left--;
                    c->next_deadline = now + c->retry_ms;
                    c->st = ST_WAIT;
                }else{
                    c->st=ST_IDLE;
                    if (min_period_ms) c->next_period_ms = now + min_period_ms;
                }
            }
        } break;
    }
}

// ---------------- TSL2561 (en maestro) ----------------
typedef struct { uint32_t next_ms; float last_lux; uint8_t ok; } lux_ctx_t;
static void lux_init(lux_ctx_t* l){ l->next_ms=0; l->last_lux=0.0f; l->ok=0; }
static void lux_step(lux_ctx_t* l){
    uint32_t now=millis(); if ((int32_t)(now - l->next_ms) < 0) return;
    uint16_t ch0=0, ch1=0;
    if (tsl2561_read_raw(TSL2561_ADDR_DEFAULT,&ch0,&ch1)){
        l->last_lux = tsl2561_calculate_lux(ch0,ch1, TSL2561_GAIN_1X, TSL2561_INTEG_402MS);
        l->ok = 1;
    }else{
        l->ok = 0;
    }
    l->next_ms = now + LUX_PERIOD_MS;

    // LED 3 niveles según luz
    if (l->ok) led_set_from_lux(l->last_lux);
    else       ledpwm_set(0); // si hay error de luz, apaga
}

// ---------------- UI (LCD/UART) ----------------
static void page_render(uint8_t page, const turn_ctx_t* s1, const lux_ctx_t* s2, const turn_ctx_t* s3){
    char line[17];
    if (page==0){
        LCD_sendStringXY(0,0, "S1 Ultrasonico  ");
        if (s1->last_ok) { snprintf(line,sizeof(line), "%3u cm          ", s1->last_val); }
        else             { snprintf(line,sizeof(line), "ERR             "); }
        LCD_sendStringXY(1,0,line);
    }else if (page==1){
        LCD_sendStringXY(0,0, "S2 Sensor de luz");
        if (s2->ok){
            int lux10 = (int)(s2->last_lux*10.0f);
            snprintf(line,sizeof(line), "%4u.%u lx       ", (unsigned)(lux10/10), (unsigned)(lux10%10));
        }else{
            snprintf(line,sizeof(line), "ERR             ");
        }
        LCD_sendStringXY(1,0,line);
    }else{
        LCD_sendStringXY(0,0, "S3 Temperatura  ");
        if (s3->last_ok) { snprintf(line,sizeof(line), "%3u C           ", s3->last_val); }
        else             { snprintf(line,sizeof(line), "ERR             "); }
        LCD_sendStringXY(1,0,line);
    }
}
static void uart_push_all(const turn_ctx_t* s1, const lux_ctx_t* s2, const turn_ctx_t* s3){
    // Formato: cm,lux,tempC  (lux con 2 decimales, sin %f)
    char buf[64];
    int cm = s1->last_ok ? s1->last_val : -1;
    if (s2->ok){
        long lx100 = (long)(s2->last_lux*100.0f);
        unsigned long ent = (lx100>=0)?(lx100/100):0, dec=(lx100>=0)?(lx100%100):0;
        int tC = s3->last_ok ? s3->last_val : -1;
        snprintf(buf,sizeof(buf), "%d,%lu.%02lu,%d\n", cm, ent, dec, tC);
    }else{
        int tC = s3->last_ok ? s3->last_val : -1;
        snprintf(buf,sizeof(buf), "%d,-1.00,%d\n", cm, tC);
    }
    UART_sendString(buf);
}

// ---------------- main ----------------
int main(void){
    LCD_init(); LCD_clear();
    UART_init(UART_BAUD);
    I2C_MasterInit();
    ledpwm_init();
    timer0_millis_init();
    sei();

    LCD_sendStringXY(0,0,"Iniciando...    ");
    if (!tsl2561_init(TSL2561_ADDR_DEFAULT, TSL2561_GAIN_1X, TSL2561_INTEG_402MS)){
        LCD_sendStringXY(1,0,"TSL ERR         ");
    }else{
        LCD_sendStringXY(1,0,"TSL OK          ");
    }
    _delay_ms(400);

    turn_ctx_t s1, s3;
    turn_init(&s1, SLAVE1_ADDR, S1_PREP_MS, S1_RETRY_MS, S1_MAX_TRIES);
    turn_init(&s3, SLAVE2_ADDR, S3_PREP_MS, S3_RETRY_MS, S3_MAX_TRIES);
    lux_ctx_t lx; lux_init(&lx);

    uint32_t next_ui_ms=0, next_page_ms=0; uint8_t page=0;

    while(1){
        // Ciclos no bloqueantes
        turn_step(&s1, 0);                     // S1 sin periodo mínimo
        turn_step(&s3, S3_MIN_PERIOD_MS);      // S3 respetando 1 Hz
        lux_step(&lx);                         // S2

        // UI ~10 Hz
        uint32_t now=millis();
        if ((int32_t)(now - next_ui_ms) >= 0){
            page_render(page, &s1, &lx, &s3);
            uart_push_all(&s1, &lx, &s3);
            next_ui_ms = now + 100;
        }
        if ((int32_t)(now - next_page_ms) >= 0){
            page = (page+1)%3;                 // rota S1?S2?S3
            next_page_ms = now + PAGE_PERIOD_MS;
        }

        _delay_ms(1);
    }
}
