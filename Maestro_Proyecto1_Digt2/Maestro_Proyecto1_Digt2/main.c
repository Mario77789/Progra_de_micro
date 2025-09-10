/*
 * Maestro_Proyecto1_Digt2.c
 *
 * Created: 10/08/2025 19:04:59
 *  Author: mario
 */ 

#define F_CPU 16000000UL
#include <avr/io.h>
#include <util/delay.h>
#include <stdio.h>
#include <avr/interrupt.h>
#include <stdint.h>
#include <util/twi.h>

#include "LCD8bits/LCD8bits.h"
#include "I2C/I2C.h"
#include "TSL2561/TSL2561.h"

// ---------- UART hacia ESP32 (solo TX) ----------
#define UART_ENABLE 1
#if UART_ENABLE
  #include "UART/UART.h"
  // ELIGE UNO: 115200 (rápido) o 9600 (seguro con HW-221)
  #define UART_BAUD 9600
#endif

// ---------------- Direcciones / comandos ----------------
#define SLAVE1_ADDR        0x20    // S1: ultrasónico (1 byte)
#define SLAVE3_ADDR        0x21    // S3: DHT11 [status,temp]
#define CMD_MEASURE        0x01

// ---------------- Tiempos turnos ----------------
#define S1_PREP_MS         40
#define S1_RETRY_MS        15
#define S1_MAX_TRIES       5

#define S3_PREP_MS         60
#define S3_RETRY_MS        100
#define S3_MAX_TRIES       3
#define S3_MIN_PERIOD_MS   1000     // DHT11 máx 1 Hz

// ---------------- Umbrales luz ----------------
#define TH_OFF_MAX_LUX     250.0f
#define TH_DIM_MAX_LUX     800.0f
#define LUX_PERIOD_MS      500

// ---------------- millis() ----------------
volatile uint32_t g_millis = 0;
ISR(TIMER0_OVF_vect){ g_millis++; }
static void timer0_millis_init(void){
    TCCR0A = 0;
    TCCR0B = (1<<CS01)|(1<<CS00); // /64 -> ~1.024 ms/overflow
    TIMSK0 = (1<<TOIE0);
}
static inline uint32_t millis(void){
    uint32_t m; uint8_t s=SREG; cli(); m=g_millis; SREG=s; return m;
}

// ---------------- SERVO en D10 (PB2/OC1B) ----------------
#define SERVO_PIN     PB2
#define SERVO_TOP     40000u
#define SERVO_MIN_US  500u
#define SERVO_MAX_US  2500u
static inline uint16_t us_to_counts(uint16_t us){ return (uint16_t)(us * 2u); }
static void servo_timer_init(void){
    ICR1  = SERVO_TOP;
    TCCR1A = (1<<WGM11);
    TCCR1B = (1<<WGM13)|(1<<WGM12) | (1<<CS11);
    DDRB  |= (1<<SERVO_PIN);
    TCCR1A |= (1<<COM1B1);
    OCR1B = us_to_counts(SERVO_MIN_US);
}
static inline void servo_write_us(uint16_t us){
    if (us < SERVO_MIN_US) us = SERVO_MIN_US;
    if (us > SERVO_MAX_US) us = SERVO_MAX_US;
    OCR1B = us_to_counts(us);
}
static void servo_set_angle(uint8_t deg){
    if (deg > 180) deg = 180;
    uint32_t us = SERVO_MIN_US + ((uint32_t)(SERVO_MAX_US - SERVO_MIN_US) * deg) / 180u;
    servo_write_us((uint16_t)us);
}
static void servo_set_from_lux(float lux){
    if (lux <= TH_OFF_MAX_LUX)      servo_set_angle(0);
    else if (lux <= TH_DIM_MAX_LUX) servo_set_angle(45);
    else                            servo_set_angle(90);
}

// ---------------- I2C helpers ----------------
static uint8_t slave_send_prepare(uint8_t addr){
    uint8_t st = I2C_Start((addr<<1) | TW_WRITE);
    if (st != TW_MT_SLA_ACK){ I2C_Stop(); return 0; }
    st = I2C_Write(CMD_MEASURE);
    if (st != TW_MT_DATA_ACK){ I2C_Stop(); return 0; }
    I2C_Stop(); return 1;
}
static uint8_t slave_read_u8(uint8_t addr, uint8_t* out){
    uint8_t st = I2C_Start((addr<<1) | TW_READ);
    if (st != TW_MR_SLA_ACK){ I2C_Stop(); return 0; }
    *out = I2C_ReadNACK();
    I2C_Stop(); return 1;
}
static uint8_t s3_read_status_temp(uint8_t *status, uint8_t *temp){
    uint8_t st = I2C_Start((SLAVE3_ADDR<<1) | TW_READ);
    if (st != TW_MR_SLA_ACK){ I2C_Stop(); return 0; }
    *status = I2C_ReadACK();
    *temp   = I2C_ReadNACK();
    I2C_Stop(); return 1;
}

// ---------------- Turnos S1 (1 byte) ----------------
typedef enum { ST_IDLE=0, ST_SENT_PREP, ST_WAIT, ST_TRY_READ } turn_state_t;
typedef struct {
    uint16_t prep_ms, retry_ms;
    uint8_t  max_tries;
    turn_state_t st;
    uint32_t next_deadline;
    uint8_t tries_left;
    uint8_t last_ok;
    uint8_t last_val;   // cm (0xFF error)
} s1_ctx_t;

static void s1_init(s1_ctx_t* c){
    c->prep_ms=S1_PREP_MS; c->retry_ms=S1_RETRY_MS; c->max_tries=S1_MAX_TRIES;
    c->st=ST_IDLE; c->next_deadline=0; c->tries_left=c->max_tries; c->last_ok=0; c->last_val=0xFF;
}
static void s1_step(s1_ctx_t* c){
    uint32_t now = millis();
    switch(c->st){
        case ST_IDLE:
            if (slave_send_prepare(SLAVE1_ADDR)){ c->st=ST_SENT_PREP; }
            else { c->last_ok=0; c->last_val=0xFF; c->next_deadline=now+c->retry_ms; c->st=ST_WAIT; }
            break;
        case ST_SENT_PREP:
            c->tries_left = c->max_tries;
            c->next_deadline = now + c->prep_ms;
            c->st = ST_WAIT;
            break;
        case ST_WAIT:
            if ((int32_t)(now - c->next_deadline) >= 0) c->st = ST_TRY_READ;
            break;
        case ST_TRY_READ:{
            uint8_t v=0xFF, ok = slave_read_u8(SLAVE1_ADDR, &v);
            if (ok && v != 0xFF){ c->last_ok=1; c->last_val=v; c->st=ST_IDLE; }
            else {
                c->last_ok=0; c->last_val=v;
                if (c->tries_left){ c->tries_left--; c->next_deadline=now+c->retry_ms; c->st=ST_WAIT; }
                else c->st=ST_IDLE;
            }
        } break;
    }
}

// ---------------- Turnos S3 ([status,temp]) ----------------
typedef struct {
    uint16_t prep_ms, retry_ms;
    uint8_t  max_tries;
    turn_state_t st;
    uint32_t next_deadline;
    uint8_t tries_left;
    uint8_t last_ok;
    uint8_t last_temp;     // °C
    uint32_t next_period_ms; // pacing 1 Hz
} s3_ctx_t;

static void s3_init(s3_ctx_t* c){
    c->prep_ms=S3_PREP_MS; c->retry_ms=S3_RETRY_MS; c->max_tries=S3_MAX_TRIES;
    c->st=ST_IDLE; c->next_deadline=0; c->tries_left=c->max_tries; c->last_ok=0; c->last_temp=0xFF; c->next_period_ms=0;
}
static void s3_step(s3_ctx_t* c){
    uint32_t now = millis();
    if ((int32_t)(now - c->next_period_ms) < 0) return;

    switch(c->st){
        case ST_IDLE:
            if (slave_send_prepare(SLAVE3_ADDR)){ c->st=ST_SENT_PREP; }
            else { c->last_ok=0; c->last_temp=0xFF; c->next_deadline=now+c->retry_ms; c->st=ST_WAIT; }
            break;
        case ST_SENT_PREP:
            c->tries_left = c->max_tries;
            c->next_deadline = now + c->prep_ms;
            c->st = ST_WAIT;
            break;
        case ST_WAIT:
            if ((int32_t)(now - c->next_deadline) >= 0) c->st = ST_TRY_READ;
            break;
        case ST_TRY_READ:{
            uint8_t st_ok=0, temp=0, ok = s3_read_status_temp(&st_ok, &temp);
            if (ok && st_ok == 0x00){
                c->last_ok=1; c->last_temp=temp; c->st=ST_IDLE;
                c->next_period_ms = now + S3_MIN_PERIOD_MS;
            } else if (ok && st_ok == 0xFE) {
                if (c->tries_left){ c->tries_left--; c->next_deadline=now+c->retry_ms; c->st=ST_WAIT; }
                else { c->last_ok=0; c->st=ST_IDLE; c->next_period_ms = now + S3_MIN_PERIOD_MS; }
            } else {
                c->last_ok=0; c->st=ST_IDLE; c->next_period_ms = now + S3_MIN_PERIOD_MS;
            }
        } break;
    }
}

// ---------------- TSL2561 (luz) ----------------
typedef struct { uint32_t next_ms; float last_lux; uint8_t ok; } lux_ctx_t;
static void lux_init(lux_ctx_t* l){ l->next_ms=0; l->last_lux=0.0f; l->ok=0; }
static void lux_step(lux_ctx_t* l){
    uint32_t now=millis(); if ((int32_t)(now - l->next_ms) < 0) return;
    uint16_t ch0=0, ch1=0;
    if (tsl2561_read_raw(TSL2561_ADDR_DEFAULT, &ch0, &ch1)){
        l->last_lux = tsl2561_calculate_lux(ch0, ch1, TSL2561_GAIN_1X, TSL2561_INTEG_402MS);
        l->ok = 1; servo_set_from_lux(l->last_lux);
    } else {
        l->ok = 0;
    }
    l->next_ms = now + LUX_PERIOD_MS;
}

// ---------------- UI fija ----------------
static void ui_draw_header(void){ LCD_sendStringXY(0,0, "S1:  S2:  S3:  "); }
static inline void put_at(char *row, uint8_t col, const char *s){
    for(uint8_t i=0; s[i] && (col+i)<16; i++) row[col+i] = s[i];
}
static void ui_update_line2(const s1_ctx_t* s1, const lux_ctx_t* lx, const s3_ctx_t* s3){
    char row[17]; for(uint8_t i=0;i<16;i++) row[i]=' '; row[16]='\0';
    if (s1->last_ok){ char v[5]; snprintf(v,sizeof(v), "%3u", s1->last_val); put_at(row, 0, v); }
    else put_at(row, 0, "ERR");
    if (lx->ok){
        int ang = (lx->last_lux <= TH_OFF_MAX_LUX) ? 0 : (lx->last_lux <= TH_DIM_MAX_LUX ? 45 : 90);
        char a[5]; snprintf(a,sizeof(a), "%3d", ang); put_at(row, 6, a);
    } else put_at(row, 6, "ERR");
    if (s3->last_ok){ char t[5]; snprintf(t,sizeof(t), "%2uC", s3->last_temp); put_at(row, 12, t); }
    else put_at(row, 12, "ERR");
    LCD_sendStringXY(1,0,row);
}

// ------------- UART CSV cada 4 s -------------
#if UART_ENABLE
static uint32_t next_uart_ms = 0;
static void uart_tx_step(const s1_ctx_t* s1, const lux_ctx_t* lx, const s3_ctx_t* s3){
    uint32_t now = millis();
    if ((int32_t)(now - next_uart_ms) < 0) return;

    int  cm  = s1->last_ok ? s1->last_val : -1;
    int  tC  = s3->last_ok ? s3->last_temp : -1;
    long lux = lx->ok ? (long)(lx->last_lux + 0.5f) : -1;

    char buf[48];
    snprintf(buf, sizeof(buf), "%d,%ld,%d\n", cm, lux, tC);
    UART_sendString(buf);

    next_uart_ms = now + 4000; // 4 s
}
#endif

// ---------------- main ----------------
int main(void){
    LCD_init(); LCD_clear();
    I2C_MasterInit();
    servo_timer_init();
    timer0_millis_init();
#if UART_ENABLE
    UART_init(UART_BAUD);
#endif
    sei();

    tsl2561_init(TSL2561_ADDR_DEFAULT, TSL2561_GAIN_1X, TSL2561_INTEG_402MS);
    ui_draw_header();

    s1_ctx_t s1; s1_init(&s1);
    s3_ctx_t s3; s3_init(&s3);
    lux_ctx_t lx; lux_init(&lx);

    uint32_t next_ui_ms=0;
    while(1){
        s1_step(&s1);
        s3_step(&s3);
        lux_step(&lx);

        uint32_t now=millis();
        if ((int32_t)(now - next_ui_ms) >= 0){
            ui_update_line2(&s1, &lx, &s3);
            next_ui_ms = now + 100;
        }
#if UART_ENABLE
        uart_tx_step(&s1, &lx, &s3);
#endif
        _delay_ms(1);
    }
}
