/*
 * Digital_2_Lab01.c
 *
 * Created: 11/07/2025 10:45:22
 * Author : mario
 */ 

#define F_CPU 16000000UL
#include <avr/io.h>
#include <util/delay.h>
#include <avr/interrupt.h>
#include <stdbool.h>


const uint8_t numeros[10] = {
    0b00111111, // 0
    0b00000110, // 1
    0b01011011, // 2
    0b01001111, // 3
    0b01100110, // 4
    0b01101101, // 5
    0b01111101, // 6
    0b00000111, // 7
    0b01111111, // 8
    0b01101111  // 9
};

// Variables 
volatile uint8_t contadorJ1 = 0;
volatile uint8_t contadorJ2 = 0;
volatile bool juegoActivo = false;
volatile bool inicioSolicitado = false;
volatile bool mostrarGanador = false;
volatile uint8_t jugadorGanador = 0;

// Mostrar número en display
void mostrar_display(uint8_t valor) {
    if (valor > 9) return;
    PORTD = numeros[valor];  
}

// Encender un solo LED del jugador según paso 
void encender_leds_jugador(uint8_t jugador, uint8_t paso) {
    // Apagar todos los LEDs primero
    PORTB &= ~((1 << PB0)|(1 << PB1)|(1 << PB2)|(1 << PB3)|(1 << PB4)|(1 << PB5));
    PORTC &= ~((1 << PC0)|(1 << PC1));

    if (jugador == 1 && paso < 4) {
        PORTB |= (1 << (3 - paso));  // PB3, PB2, PB1, PB0
    } else if (jugador == 2) {
        switch (paso) {
            case 0: PORTB |= (1 << PB4); break;
            case 1: PORTB |= (1 << PB5); break;
            case 2: PORTC |= (1 << PC0); break;
            case 3: PORTC |= (1 << PC1); break;
        }
    }
}

// Encender todos los LEDs de un jugador 
void encender_todos_leds_jugador(uint8_t jugador) {
    // Apagar todos primero
    PORTB &= ~((1 << PB0)|(1 << PB1)|(1 << PB2)|(1 << PB3)|(1 << PB4)|(1 << PB5));
    PORTC &= ~((1 << PC0)|(1 << PC1));

    if (jugador == 1) {
        PORTB |= (1 << PB0)|(1 << PB1)|(1 << PB2)|(1 << PB3);
    } else if (jugador == 2) {
        PORTB |= (1 << PB4)|(1 << PB5);
        PORTC |= (1 << PC0)|(1 << PC1);
    }
}

// Alternar visualización de LEDs entre ambos jugadores 
void refrescar_leds() {
    static bool mostrarJ1 = true;

    if (mostrarGanador) {
        encender_todos_leds_jugador(jugadorGanador); 
    } else {
        if (mostrarJ1) {
            encender_leds_jugador(1, contadorJ1);
        } else {
            encender_leds_jugador(2, contadorJ2);
        }
        mostrarJ1 = !mostrarJ1;
    }

    _delay_ms(5);
}

// Reiniciar variables y mostrar cuenta regresiva
void iniciar_carrera() {
    juegoActivo = false;
    mostrarGanador = false;
    jugadorGanador = 0;
    contadorJ1 = 0;
    contadorJ2 = 0;

    encender_leds_jugador(1, 0);
    encender_leds_jugador(2, 0);
    mostrar_display(0);
    _delay_ms(300);

    for (int i = 5; i >= 0; i--) {
        mostrar_display(i);
        _delay_ms(1000);
    }

    juegoActivo = true;
}

// Interrupción por cambio de pin 
ISR(PCINT1_vect) {
    static uint8_t lastState = 0xFF;
    uint8_t current = PINC;
    uint8_t changed = current ^ lastState;
    lastState = current;

    // Botón inicio (PC3 = A3)
    if ((changed & (1 << PC3)) && !(current & (1 << PC3))) {
        if (!juegoActivo) {
            inicioSolicitado = true;
        }
    }

    // Botón jugador 1 (PC2 = A2)
    if ((changed & (1 << PC2)) && !(current & (1 << PC2))) {
        if (juegoActivo && contadorJ1 < 4) {
            contadorJ1++;
        }
    }

    // Botón jugador 2 (PC4 = A4)
    if ((changed & (1 << PC4)) && !(current & (1 << PC4))) {
        if (juegoActivo && contadorJ2 < 4) {
            contadorJ2++;
        }
    }
}

int main(void)
{
    // Display: PD0–PD6 como salida
    DDRD = 0b01111111;

    // LEDs: PB0–PB5 y PC0–PC1 como salida
    DDRB |= 0b00111111;
    DDRC |= 0b00000011;

    // Botones PC2, PC3, PC4 como entrada con pull-up
    DDRC &= ~((1 << PC2)|(1 << PC3)|(1 << PC4));
    PORTC |= (1 << PC2)|(1 << PC3)|(1 << PC4);

    // Habilitar interrupciones por cambio en PC2, PC3 y PC4
    PCICR |= (1 << PCIE1); // Habilitar interrupciones para PINC
    PCMSK1 |= (1 << PCINT18)|(1 << PCINT19)|(1 << PCINT20); // PC2, PC3, PC4
    sei(); 

    while (1) 
    {
        if (inicioSolicitado) {
            inicioSolicitado = false;
            iniciar_carrera();
        }

        // Verificar si algún jugador ganó
        if (juegoActivo) {
            if (contadorJ1 == 4) {
                mostrar_display(1);
                jugadorGanador = 1;
                mostrarGanador = true;
                juegoActivo = false;
            } else if (contadorJ2 == 4) {
                mostrar_display(2);
                jugadorGanador = 2;
                mostrarGanador = true;
                juegoActivo = false;
            }
        }

        refrescar_leds(); // multiplexado visual
    }
}
