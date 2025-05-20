#define F_CPU 16000000UL
#include <avr/io.h>
#include <util/delay.h>

// ---- UART ----
void UART_Init(unsigned int ubrr) {
	UBRR0H = (unsigned char)(ubrr >> 8);
	UBRR0L = (unsigned char)ubrr;
	UCSR0B = (1 << RXEN0) | (1 << TXEN0);
	UCSR0C = (1 << UCSZ01) | (1 << UCSZ00);
}

unsigned char UART_RxChar(void) {
	while (!(UCSR0A & (1 << RXC0)));
	return UDR0;
}

void UART_TxChar(unsigned char data) {
	while (!(UCSR0A & (1 << UDRE0)));
	UDR0 = data;
}

void UART_SendString(const char* str) {
	while (*str) {
		UART_TxChar(*str++);
	}
}

// ---- Main ----
int main(void) {
	// Configuración de pines
	DDRD |= (1 << DDD3) | (1 << DDD2);     // D3 y D2 como salidas (LEDs)
	DDRD &= ~(1 << DDD4);                  // D4 como entrada (botón)
	PORTD |= (1 << PORTD4);                // Pull-up interno en D4

	UART_Init(103);      // 9600 baudios para 16MHz

	uint8_t last_button = (PIND & (1 << PIND4));

	while (1) {
		// ------------ Serial para LED1 (D3) -------------
		if (UCSR0A & (1 << RXC0)) {
			unsigned char cmd = UART_RxChar();
			if (cmd == '1')
			PORTD |= (1 << PORTD3);   // Prender LED1
			else if (cmd == '0')
			PORTD &= ~(1 << PORTD3);  // Apagar LED1
		}

		// ------------ Botón para LED2 (D2) + envío serial -------------
		uint8_t btn_now = (PIND & (1 << PIND4)); // lee botón (activo bajo)
		if (!btn_now && last_button) {       // Flanco de bajada (presión)
			PORTD |= (1 << PORTD2);          // Prender LED2
			UART_SendString("BOTON\n");      // Avisar botón presionado
			_delay_ms(50);                   // Anti-rebote simple
			} else if (btn_now) {
			PORTD &= ~(1 << PORTD2);         // Apagar LED2 al soltar
		}
		last_button = btn_now;
	}
}