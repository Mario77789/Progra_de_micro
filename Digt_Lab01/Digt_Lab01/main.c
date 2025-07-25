/*
 * Digt_Lab01.c
 *
 * Created: 11/07/2025 10:45:22
 * Author : mario
 */ 

#define F_CPU 16000000UL
#include <avr/io.h>
#include <util/delay.h>
#include <avr/interrupt.h>
#include <stdbool.h>
#include "display/Display.h"

// Variables globales
volatile bool botones_habilitados = false;
volatile bool inicio_solicitado = false;

void apagar_todos_leds() {
    PORTB &= ~(63); // Apaga PB0–PB5
    PORTC &= ~(3);  // Apaga PC0–PC1
}

void encender_leds_jugador(uint8_t jugador) {
    if (jugador == 1) {
        PORTB |= (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3);
    } else if (jugador == 2) {
        PORTB |= (1 << 4) | (1 << 5);
        PORTC |= (1 << 0) | (1 << 1);
    }
}

void cuenta_regresiva() {
    botones_habilitados = false;
    apagar_todos_leds();

    for (int i = 5; i >= 0; i--) {
        mostrar_display(i);
        _delay_ms(1000);
    }

    botones_habilitados = true;
}

// Interrupción por cambio de pin (PCINT1 - PC2, PC3, PC4)
ISR(PCINT1_vect) {
    static uint8_t estado_anterior = 255;
    uint8_t estado_actual = PINC;
    uint8_t cambiado = estado_actual ^ estado_anterior;
    estado_anterior = estado_actual;

    // Botón inicio (PC3 = A3)
    if ((cambiado & (1 << 3)) && !(estado_actual & (1 << 3))) {
        inicio_solicitado = true;
    }
 
    // Botón Jugador 1 (PC2 = A2)
    if ((cambiado & (1 << 2)) && !(estado_actual & (1 << 2))) {
        if (botones_habilitados) {
            encender_leds_jugador(1);
        }
    }

    // Botón Jugador 2 (PC4 = A4)
    if ((cambiado & (1 << 4)) && !(estado_actual & (1 << 4))) {
        if (botones_habilitados) {
            encender_leds_jugador(2);
        }
    }
}

int main(void)
{
    // Display: PD0–PD6 como salida
    DDRD = 127; // 0x7F
    mostrar_display(0);

    // LEDs PB0–PB5 y PC0–PC1 como salida
    DDRB |= 63; // 0x3F
    DDRC |= 3;  // 0x03
    apagar_todos_leds();

    // Botones PC2 (J1), PC3 (Inicio), PC4 (J2) como entrada con pull-up
    DDRC &= ~( (1 << 2) | (1 << 3) | (1 << 4) );
    PORTC |= ( (1 << 2) | (1 << 3) | (1 << 4) );

    // Habilitar interrupciones por cambio en PCINT18–20 (PC2, PC3, PC4)
    PCICR |= (1 << 1); // PCIE1 para PINC
    PCMSK1 |= (1 << 2) | (1 << 3) | (1 << 4);
    sei();

    while (1) {
        if (inicio_solicitado) {
            inicio_solicitado = false;
            cuenta_regresiva();
        }
    }
}
