/*
 * Lab06_Digt2.c
 *
 * Created: 11/09/2025 20:04:42
 * Author : mario
 */ 

#define F_CPU 16000000UL
#include <avr/io.h>
#include <avr/interrupt.h>

/* ===================== UART ===================== */
#define BAUD    9600UL
#define UBRRVAL ((F_CPU/16/BAUD)-1)

static inline void UART_init(void) {
    UBRR0H = (uint8_t)(UBRRVAL >> 8);
    UBRR0L = (uint8_t)(UBRRVAL);
    UCSR0B = (1<<RXEN0) | (1<<TXEN0);       // RX y TX
    UCSR0C = (1<<UCSZ01) | (1<<UCSZ00);     // 8N1
}
static inline void UART_send(uint8_t c) {
    while (!(UCSR0A & (1<<UDRE0)));
    UDR0 = c;
}

/* ============ Mapa de botones (pull-up) ============ */
/* Arriba: D6/PD6, Abajo: D5/PD5, Izq: D8/PB0, Der: D2/PD2, A: D11/PB3, B: D7/PD7 */
typedef enum {
    BTN_UP = 0,      // D6  PD6
    BTN_DOWN,        // D5  PD5
    BTN_LEFT,        // D8  PB0
    BTN_RIGHT,       // D2  PD2
    BTN_A,           // D11 PB3
    BTN_B,           // D7  PD7
    BTN_COUNT
} btn_id_t;

static const uint8_t BTN_CHAR[BTN_COUNT] = {'U','D','L','R','A','B'};

/* Definiciones de puerto/pin para lectura rápida */
#define BTN_UP_PINREG      PIND
#define BTN_UP_PORTREG     PORTD
#define BTN_UP_DDRREG      DDRD
#define BTN_UP_BIT         PD6

#define BTN_DOWN_PINREG    PIND
#define BTN_DOWN_PORTREG   PORTD
#define BTN_DOWN_DDRREG    DDRD
#define BTN_DOWN_BIT       PD5

#define BTN_LEFT_PINREG    PINB
#define BTN_LEFT_PORTREG   PORTB
#define BTN_LEFT_DDRREG    DDRB
#define BTN_LEFT_BIT       PB0

#define BTN_RIGHT_PINREG   PIND
#define BTN_RIGHT_PORTREG  PORTD
#define BTN_RIGHT_DDRREG   DDRD
#define BTN_RIGHT_BIT      PD2

#define BTN_A_PINREG       PINB
#define BTN_A_PORTREG      PORTB
#define BTN_A_DDRREG       DDRB
#define BTN_A_BIT          PB3

#define BTN_B_PINREG       PIND
#define BTN_B_PORTREG      PORTD
#define BTN_B_DDRREG       DDRD
#define BTN_B_BIT          PD7

/* Con pull-up: presionado = nivel bajo en el pin */
#define READ_BTN(btn)   ( ((btn)==BTN_UP    ) ? !(BTN_UP_PINREG   & (1<<BTN_UP_BIT))    : \
                          ((btn)==BTN_DOWN  ) ? !(BTN_DOWN_PINREG & (1<<BTN_DOWN_BIT))  : \
                          ((btn)==BTN_LEFT  ) ? !(BTN_LEFT_PINREG & (1<<BTN_LEFT_BIT))  : \
                          ((btn)==BTN_RIGHT ) ? !(BTN_RIGHT_PINREG& (1<<BTN_RIGHT_BIT)) : \
                          ((btn)==BTN_A     ) ? !(BTN_A_PINREG    & (1<<BTN_A_BIT))     : \
                          /*BTN_B*/            !(BTN_B_PINREG     & (1<<BTN_B_BIT)) )

/* ============ Antirrebote con Timer1 (1 kHz) ============ */
#define DEBOUNCE_MS 20

volatile uint8_t need_debounce[BTN_COUNT];   // cambio detectado, requiere validación
volatile uint8_t stable_state[BTN_COUNT];    // 0=suelto, 1=presionado (estable)
volatile uint8_t event_press_mask = 0;       // bit i=1 ? enviar carácter del botón i
volatile uint8_t debounce_cnt[BTN_COUNT];    // cuenta regresiva en ms

/* Estados crudos anteriores por puerto para PCINT */
volatile uint8_t last_raw_PORTD;
volatile uint8_t last_raw_PORTB;

/* ===================== Inicializaciones ===================== */
static void buttons_init(void) {
    /* Entradas con pull-up interno */
    BTN_UP_DDRREG    &= ~(1<<BTN_UP_BIT);
    BTN_DOWN_DDRREG  &= ~(1<<BTN_DOWN_BIT);
    BTN_LEFT_DDRREG  &= ~(1<<BTN_LEFT_BIT);
    BTN_RIGHT_DDRREG &= ~(1<<BTN_RIGHT_BIT);
    BTN_A_DDRREG     &= ~(1<<BTN_A_BIT);
    BTN_B_DDRREG     &= ~(1<<BTN_B_BIT);

    BTN_UP_PORTREG    |= (1<<BTN_UP_BIT);
    BTN_DOWN_PORTREG  |= (1<<BTN_DOWN_BIT);
    BTN_LEFT_PORTREG  |= (1<<BTN_LEFT_BIT);
    BTN_RIGHT_PORTREG |= (1<<BTN_RIGHT_BIT);
    BTN_A_PORTREG     |= (1<<BTN_A_BIT);
    BTN_B_PORTREG     |= (1<<BTN_B_BIT);

    /* Estado estable inicial */
    for (uint8_t i=0;i<BTN_COUNT;i++) {
        stable_state[i]  = READ_BTN(i) ? 1 : 0;
        need_debounce[i] = 0;
        debounce_cnt[i]  = 0;
    }

    /* Captura de estado crudo inicial para PCINT */
    last_raw_PORTD = PIND;
    last_raw_PORTB = PINB;

    /* Habilitar interrupciones por cambio de pin */
    /* PORTD: PD2,PD5,PD6,PD7 ? PCINT[18,21,22,23] ? PCIE2 / PCMSK2 */
    PCICR  |= (1<<PCIE2);
    PCMSK2 |= (1<<PCINT18) | (1<<PCINT21) | (1<<PCINT22) | (1<<PCINT23);

    /* PORTB: PB0,PB3 ? PCINT[0,3] ? PCIE0 / PCMSK0 */
    PCICR  |= (1<<PCIE0);
    PCMSK0 |= (1<<PCINT0) | (1<<PCINT3);
}

static void timer1_init_1kHz(void) {
    /* CTC: 16 MHz / 64 = 250 kHz; 250 kHz / 1000 = 250 ? OCR1A=249 */
    TCCR1A = 0;
    TCCR1B = (1<<WGM12);         // CTC
    OCR1A  = 249;
    TCCR1B |= (1<<CS11) | (1<<CS10); // prescaler 64
    TIMSK1 = (1<<OCIE1A);        // habilita ISR OCR1A
}

/* ===================== ISRs ===================== */
ISR(PCINT2_vect) { /* PORTD */
    uint8_t now = PIND;
    uint8_t changed = now ^ last_raw_PORTD;
    last_raw_PORTD = now;

    if (changed & (1<<PD2)) { need_debounce[BTN_RIGHT] = 1; debounce_cnt[BTN_RIGHT] = DEBOUNCE_MS; }
    if (changed & (1<<PD5)) { need_debounce[BTN_DOWN]  = 1; debounce_cnt[BTN_DOWN]  = DEBOUNCE_MS; }
    if (changed & (1<<PD6)) { need_debounce[BTN_UP]    = 1; debounce_cnt[BTN_UP]    = DEBOUNCE_MS; }
    if (changed & (1<<PD7)) { need_debounce[BTN_B]     = 1; debounce_cnt[BTN_B]     = DEBOUNCE_MS; }
}

ISR(PCINT0_vect) { /* PORTB */
    uint8_t now = PINB;
    uint8_t changed = now ^ last_raw_PORTB;
    last_raw_PORTB = now;

    if (changed & (1<<PB0)) { need_debounce[BTN_LEFT] = 1; debounce_cnt[BTN_LEFT] = DEBOUNCE_MS; }
    if (changed & (1<<PB3)) { need_debounce[BTN_A]    = 1; debounce_cnt[BTN_A]    = DEBOUNCE_MS; }
}

ISR(TIMER1_COMPA_vect) { /* 1 kHz ? cada 1 ms */
    for (uint8_t i=0;i<BTN_COUNT;i++) {
        if (need_debounce[i]) {
            if (debounce_cnt[i] > 0) {
                debounce_cnt[i]--;
            } else {
                uint8_t now_pressed = READ_BTN(i) ? 1 : 0;  // presionado=1 con pull-up
                if (now_pressed != stable_state[i]) {
                    stable_state[i] = now_pressed;
                    if (now_pressed) {                    // solo en flanco de bajada (presión)
                        event_press_mask |= (1<<i);
                    }
                }
                need_debounce[i] = 0;
            }
        }
    }
}

/* ===================== main ===================== */
int main(void)
{
    UART_init();
    buttons_init();
    timer1_init_1kHz();
    sei();

    /* Replace with your application code */
    while (1) 
    {
        /* Procesar eventos de pulsación sin bloquear */
        uint8_t pending;
        cli();
        pending = event_press_mask;
        event_press_mask = 0;
        sei();

        if (pending) {
            for (uint8_t i=0;i<BTN_COUNT;i++) {
                if (pending & (1<<i)) {
                    UART_send(BTN_CHAR[i]);  // enviar 'U','D','L','R','A','B'
                }
            }
        }
        
    }
}
