/*  
 * proyecto_rostro.c  
 * Modificado: 13/05/2025  
 * Description: Modo manual, EEPROM y Adafruit
 */  
#define F_CPU 16000000UL  
#define FILTER_SAMPLES 3  

#include <avr/io.h>  
#include <stdlib.h>  
#include <avr/interrupt.h>  
#include <util/delay.h>  
#include <avr/eeprom.h>  // Incluido para las funciones de EEPROM

volatile uint8_t mode = 0;   // 0: Manual | 1: EEPROM | 2: Adafruit IO  
volatile uint8_t button_pressed = 0;  
volatile uint16_t adc_values[4] = {0,0,0,0};  

#define BTN_PIN          PD4  
#define LED_MANUAL_PIN   PD3  
#define LED_EEPROM_PIN   PD2  

#define EEPROM_M1_ADDR    0  
#define EEPROM_M2_ADDR    1  
#define EEPROM_M3_ADDR    2  
#define EEPROM_M4_ADDR    3  

// ==== Prototipos ====  
void setup(void);  
uint16_t filtered_adc(uint8_t channel);  
void usart_init(void);  
void usart_tx_char(char data);  
void usart_tx_string(const char* str);  
char usart_rx_char(void);  
uint8_t usart_rx_available(void);  
void usart_flush_rx(void);  
void check_button(void);  
void eeprom_menu(void);  
void move_servo(uint8_t servo, uint8_t angle);  
void print_number(uint16_t num);  
void show_saved_angle(uint8_t servo);  
uint8_t adc_to_angle(uint16_t adc_value);  
void save_current_angle(uint8_t servo);  
void parse_adafruit_command(void);  

// ==== Buffers para recepción serial ====  
#define RX_BUFFER_SIZE  16  
char usart_rx_buffer[RX_BUFFER_SIZE];  
uint8_t rx_index = 0;  

// ==== Función principal ====  
int main(void) {  
    setup();  
    usart_init();  

    while (1) {  
        check_button();  

        if (button_pressed) {  
            mode = (mode + 1) % 3; // Ciclo 0->1->2->0...  
            button_pressed = 0;  
        }  

        // Actualizar LEDs según modo  
        if (mode == 0) {              // Modo Manual  
            PORTD |=  (1 << LED_MANUAL_PIN);  
            PORTD &= ~(1 << LED_EEPROM_PIN);  
        } else if (mode == 1) {       // Modo EEPROM  
            PORTD &= ~(1 << LED_MANUAL_PIN);  
            PORTD |=  (1 << LED_EEPROM_PIN);  
            eeprom_menu();  
        } else if (mode == 2) {       // Modo Adafruit IO (Serial)  
            PORTD |=  (1 << LED_MANUAL_PIN);  
            PORTD |=  (1 << LED_EEPROM_PIN);  

            // --- Procesar comandos seriales tipo "A:120\n" ---  
            parse_adafruit_command();  
        }  
    }  
}  

// == Procesa comandos de Adafruit IO, tipo "A:120"  
void parse_adafruit_command(void) {  
    while (usart_rx_available()) {  
        char c = usart_rx_char();  
        if (c == '\n' || c == '\r') {  
            usart_rx_buffer[rx_index] = '\0'; // Termina string  
            if (rx_index >= 3) {  
                // Formato esperado: X:NNN  
                char motor = usart_rx_buffer[0];  
                if (usart_rx_buffer[1] == ':' || usart_rx_buffer[1] == ';') {  
                    uint8_t angle = (uint8_t) atoi(&usart_rx_buffer[2]);  
                    if (angle > 180) angle = 180;  
                    switch (motor) {  
                        case 'A': case 'a': move_servo(0, angle); break;  
                        case 'B': case 'b': move_servo(1, angle); break;  
                        case 'C': case 'c': move_servo(2, angle); break;  
                        case 'D': case 'd': move_servo(3, angle); break;  
                        default: break;  
                    }  
                }  
            }  
            rx_index = 0; // Ready for next line  
        } else if (rx_index < RX_BUFFER_SIZE-1) {  
            usart_rx_buffer[rx_index++] = c;  
        } else { // Buffer full, reset  
            rx_index = 0;  
        }  
    }  
}  

// Configuración inicial  
void setup(void) {  
    // ADC con interrupción y prescaler 128  
    ADCSRA = (1 << ADEN) | (1 << ADIE)  
           | (1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0);  
    DIDR0  = 0xF0;    // Deshabilita digital en A4–A7  

    // Pines PWM como salida  
    DDRB |= (1 << PB1) | (1 << PB2) | (1 << PB3);  
    DDRD |= (1 << PD5);  

    // Timer1 (D9, D10)  
    TCCR1A = (1 << COM1A1) | (1 << COM1B1) | (1 << WGM11);  
    TCCR1B = (1 << WGM13)  | (1 << WGM12)  
           | (1 << CS11)   | (1 << CS10);   // prescaler 64  
    ICR1 = 4999;  // 20 ms  
    OCR1A = 375;  // 1.5 ms  
    OCR1B = 375;  

    // Timer0 (D5)  
    TCCR0A = (1 << COM0B1) | (1 << WGM01) | (1 << WGM00);  
    TCCR0B = (1 << CS02)   | (1 << CS00);  // prescaler 1024  
    OCR0B  = 23;  

    // Timer2 (D11)  
    TCCR2A = (1 << COM2A1) | (1 << WGM21) | (1 << WGM20);  
    TCCR2B = (1 << CS22)   | (1 << CS21) | (1 << CS20);  
    OCR2A  = 23;  

    // ADC inicia en A4 con AVcc  
    ADMUX = (1 << REFS0) | 4;  
    PORTC |= 0xF0;  // Pull-ups A4–A7  

    // Configura botón y LEDs  
    DDRD &= ~(1 << BTN_PIN);  
    PORTD |=  (1 << BTN_PIN);  // Pull-up  
    DDRD |=  (1 << LED_MANUAL_PIN) | (1 << LED_EEPROM_PIN);  

    ADCSRA |= (1 << ADSC);  // Primera conversión  
    sei();    // Habilita interrupciones  
}  

// USART  
void usart_init(void) {  
    uint16_t ubrr = 103;  // 9600 bps @16 MHz  
    UBRR0H = (ubrr >> 8);  
    UBRR0L = ubrr;  
    UCSR0B = (1 << RXEN0) | (1 << TXEN0);  
    UCSR0C = (1 << UCSZ01) | (1 << UCSZ00);  
}  
void usart_tx_char(char data) {  
    while (!(UCSR0A & (1 << UDRE0)));  
    UDR0 = data;  
}  
void usart_tx_string(const char* str) {  
    while (*str) usart_tx_char(*str++);  
}  
char usart_rx_char(void) {  
    while (!(UCSR0A & (1 << RXC0)));  
    return UDR0;  
}  
// Devuelve 1 si hay datos en buffer RX  
uint8_t usart_rx_available(void) {  
    return (UCSR0A & (1 << RXC0));  
}  
void usart_flush_rx(void) {  
    while (UCSR0A & (1 << RXC0)) { (void)UDR0; }  
}  
void print_number(uint16_t num) {  
    char buf[6]; uint8_t i = 0, j;  
    if (num == 0) { usart_tx_char('0'); return; }  
    while (num) { buf[i++] = (num % 10) + '0'; num /= 10; }  
    for (j = 0; j < i; j++)  
    usart_tx_char(buf[i-1-j]);  
}  

// Lectura filtrada de ADC  
uint16_t filtered_adc(uint8_t channel) {  
    static uint16_t samples[4][FILTER_SAMPLES];  
    static uint8_t idx[4] = {0};  
    samples[channel][idx[channel]] = ADC;  
    idx[channel] = (idx[channel] + 1) % FILTER_SAMPLES;  
    uint32_t sum = 0;  
    for (uint8_t k = 0; k < FILTER_SAMPLES; k++)  
        sum += samples[channel][k];  
    return sum / FILTER_SAMPLES;  
}  

// Detecta flanco de bajada del botón  
void check_button(void) {  
    static uint8_t prev = 1;  
    uint8_t st = (PIND & (1 << BTN_PIN)) >> BTN_PIN;  
    if (st == 0 && prev == 1) {  
        _delay_ms(10);  
        if ((PIND & (1 << BTN_PIN)) == 0) {  
            button_pressed = 1;  
        }  
    }  
    prev = st;  
}  

// Menú EEPROM mejorado con tiempos de espera más largos y separación entre guardar y mover
void eeprom_menu(void) {
    button_pressed = 0;  // Resetea la bandera del botón al entrar
    
    while (mode == 1) {  // Permanece en el menú mientras esté en modo EEPROM
        check_button();  // Verifica si se presionó el botón para salir
        
        if (button_pressed) {
            // Si se presionó el botón, cambiar al siguiente modo (modo Adafruit)
            usart_tx_string("\r\n[BOTÓN DETECTADO] Saliendo del modo EEPROM...\r\n");
            mode = 2;  // Cambia al modo Adafruit (siguiente en secuencia)
            button_pressed = 0;  // Resetea la bandera para evitar cambios adicionales en main()
            return;  // Sale de la función para volver al bucle principal
        }
        
        usart_tx_string("\r\n--- CONTROL DE MOTORES ---\r\n");
        usart_tx_string("1) Valores pre-establecidos (90°)\r\n");
        usart_tx_string("2) Guardar valor actual del servo\r\n");
        usart_tx_string("3) Mostrar valor guardado\r\n");
        usart_tx_string("4) Salir al modo Adafruit\r\n");
        usart_tx_string("Presione el botón en cualquier momento para salir\r\n");
        usart_tx_string("Elija opción: ");
        
        // Tiempo de espera aumentado a 6 segundos (600 × 10ms)
        uint16_t timeout_counter = 0;
        while (!usart_rx_available() && timeout_counter < 600) {
            check_button();
            if (button_pressed) break;  // Si detecta botón durante espera, sale
            _delay_ms(10);
            timeout_counter++;
        }
        
        if (button_pressed) continue;  // Si se presionó botón, regresa al inicio del bucle
        
        if (!usart_rx_available()) {
            usart_tx_string("\r\nTiempo de espera agotado, intentelo de nuevo.\r\n");
            continue;
        }
        
        char opt = usart_rx_char();
        usart_tx_char(opt);  // Eco para confirmar la selección
        usart_tx_string("\r\n");
        usart_flush_rx();  // Limpia resto de CR/LF
        
        switch (opt) {
            case '1': {
                // Valores preestablecidos a 90°
                for (uint8_t s = 0; s < 4; s++)
                    move_servo(s, 90);
                usart_tx_string("Motores a 90° preestablecidos.\r\n");
                break;
            }
            
            case '2': {
                // Selección de motor SOLO para guardar
                usart_tx_string("\r\nSeleccione MOTOR para guardar (A-D): ");
                
                // Espera con supervisión del botón - tiempo aumentado a 6 segundos
                timeout_counter = 0;
                while (!usart_rx_available() && timeout_counter < 600) {
                    check_button();
                    if (button_pressed) break;
                    _delay_ms(10);
                    timeout_counter++;
                }
                
                if (button_pressed) continue;  // Si se presionó botón, regresa al inicio
                
                if (!usart_rx_available()) {
                    usart_tx_string("\r\nTiempo de espera agotado, intentelo de nuevo.\r\n");
                    continue;
                }
                
                char m = usart_rx_char();
                usart_tx_char(m);  // Eco para confirmar
                usart_tx_string("\r\n");
                usart_flush_rx();
                
                uint16_t addr = 0;
                uint8_t servo = 0;
                
                switch (m) {
                    case 'A': case 'a': addr = EEPROM_M1_ADDR; servo = 0; break;
                    case 'B': case 'b': addr = EEPROM_M2_ADDR; servo = 1; break;
                    case 'C': case 'c': addr = EEPROM_M3_ADDR; servo = 2; break;
                    case 'D': case 'd': addr = EEPROM_M4_ADDR; servo = 3; break;
                    default: 
                        usart_tx_string("Opción inválida.\r\n"); 
                        continue;  // Vuelve al inicio del bucle
                }
                
                // Cálculo del ángulo actual desde ADC
                uint16_t raw = adc_values[servo];
                uint8_t ang = adc_to_angle(raw);
                
                // SOLO guardar, NO mover
                eeprom_write_byte((uint8_t*)(uint16_t)addr, ang);
                
                usart_tx_string("Valor actual guardado en EEPROM: ");
                print_number(ang);
                usart_tx_string("°.\r\n");
                break;
            }
            
            case '3': {
                usart_tx_string("\r\nSeleccione MOTOR para mover (A-D): ");
                
                // Espera con supervisión del botón - tiempo aumentado a 6 segundos
                timeout_counter = 0;
                while (!usart_rx_available() && timeout_counter < 600) {
                    check_button();
                    if (button_pressed) break;
                    _delay_ms(10);
                    timeout_counter++;
                }
                
                if (button_pressed) continue;  // Si se presionó botón, regresa al inicio
                
                if (!usart_rx_available()) {
                    usart_tx_string("\r\nTiempo de espera agotado, intentelo de nuevo.\r\n");
                    continue;
                }
                
                char m2 = usart_rx_char();
                usart_tx_char(m2);  // Eco para confirmar
                usart_tx_string("\r\n");
                usart_flush_rx();
                
                uint8_t servo2 = 0;
                
                switch (m2) {
                    case 'A': case 'a': servo2 = 0; break;
                    case 'B': case 'b': servo2 = 1; break;
                    case 'C': case 'c': servo2 = 2; break;
                    case 'D': case 'd': servo2 = 3; break;
                    default: 
                        usart_tx_string("Opción inválida.\r\n"); 
                        continue;  // Vuelve al inicio del bucle
                }
                
                show_saved_angle(servo2);
                break;
            }
            
            case '4':
                usart_tx_string("Cambiando a modo Adafruit IO...\r\n");
                mode = 2;  // Cambia directamente al modo Adafruit
                return;    // Sale de la función
                
            default:
                usart_tx_string("Opción inválida.\r\n");
        }
        
        // Pequeña pausa para revisar si se ha presionado el botón después de ejecutar una acción
        for (uint8_t i = 0; i < 20; i++) {
            check_button();
            if (button_pressed) break;
            _delay_ms(10);
        }
    }
}

// Mueve servo 0-3 a ángulo 0-180 - CORREGIDO para manejar todo el rango
void move_servo(uint8_t servo, uint8_t angle) {  
    // Limitar el ángulo al rango válido
    if (angle > 180) angle = 180;
    
    switch (servo) {  
        case 0: // Servo en Timer2A (8-bit)
            // Rango correcto para 0-180 grados: 8 (0°) a 38 (180°)
            OCR2A = 8 + ((uint32_t)angle * 30) / 180;  
            break;  
        case 1: // Servo en Timer1B (16-bit)
            // Rango correcto para 0-180 grados: 125 (0°) a 625 (180°)
            OCR1B = 125 + ((uint32_t)angle * 500) / 180;  
            break;  
        case 2: // Servo en Timer1A (16-bit)
            // Rango correcto para 0-180 grados: 125 (0°) a 625 (180°)
            OCR1A = 125 + ((uint32_t)angle * 500) / 180;  
            break;  
        case 3: // Servo en Timer0B (8-bit)
            // Rango correcto para 0-180 grados: 8 (0°) a 38 (180°)
            OCR0B = 8 + ((uint32_t)angle * 30) / 180;  
            break;  
    }  
}  

// Muestra y mueve al valor guardado en EEPROM  
void show_saved_angle(uint8_t servo) {  
    uint16_t addr = 0;  
    switch (servo) {  
        case 0: addr = EEPROM_M1_ADDR; break;  
        case 1: addr = EEPROM_M2_ADDR; break;  
        case 2: addr = EEPROM_M3_ADDR; break;  
        case 3: addr = EEPROM_M4_ADDR; break;  
    }  
    uint8_t ang = eeprom_read_byte((uint8_t*)(uint16_t)addr);  
    usart_tx_string("Valor guardado: ");  
    print_number(ang);  
    usart_tx_string("°\r\n");  
    
    // Mover al ángulo guardado
    move_servo(servo, ang);
    usart_tx_string("Servo movido a la posición guardada.\r\n");
}  

// Convierte valor ADC a ángulo (0-180) - CORREGIDO para precisión
uint8_t adc_to_angle(uint16_t adc_value) {  
    // Asegurar que adc_value está dentro del rango válido
    if (adc_value > 1023) adc_value = 1023;
    
    // Conversión de 0-1023 a 0-180 grados
    uint8_t angle = (uint8_t)((uint32_t)adc_value * 180UL / 1023UL);
    
    // Verificación adicional
    if (angle > 180) angle = 180;
    
    return angle;
}  

// Guarda el ángulo actual en EEPROM  
void save_current_angle(uint8_t servo) {  
    uint16_t addr;  
    switch (servo) {  
        case 0: addr = EEPROM_M1_ADDR; break;  
        case 1: addr = EEPROM_M2_ADDR; break;  
        case 2: addr = EEPROM_M3_ADDR; break;  
        case 3: addr = EEPROM_M4_ADDR; break;  
        default: return;  
    }  
    uint8_t angle = adc_to_angle(adc_values[servo]);  
    eeprom_write_byte((uint8_t*)(uint16_t)addr, angle);  

    usart_tx_string("Servo ");  
    usart_tx_char('A' + servo);  
    usart_tx_string(" guardado a ");  
    print_number(angle);  
    usart_tx_string("°\r\n");  
}  

// ISR de ADC: solo mueve servos en modo manual - CORREGIDO para usar todo el rango
ISR(ADC_vect) {  
    static uint8_t ch = 0;  

    adc_values[ch] = filtered_adc(ch);  

    ch = (ch + 1) % 4;  
    ADMUX = (1 << REFS0) | (ch + 4);  

    if (mode == 0) {  
        // Modo manual: mueve servos según potenciómetro
        // Usar el cálculo correcto para cada servo desde los valores ADC
        uint8_t angle0 = adc_to_angle(adc_values[0]);
        uint8_t angle1 = adc_to_angle(adc_values[1]);
        uint8_t angle2 = adc_to_angle(adc_values[2]);
        uint8_t angle3 = adc_to_angle(adc_values[3]);
        
        // Calcular valores OCR directamente
        OCR2A = 8 + ((uint32_t)angle0 * 30) / 180;
        OCR1B = 125 + ((uint32_t)angle1 * 500) / 180;
        OCR1A = 125 + ((uint32_t)angle2 * 500) / 180;
        OCR0B = 8 + ((uint32_t)angle3 * 30) / 180;
    }  
    
    // Límites de seguridad - aseguran que no se exceda el rango seguro para los servos
    if (OCR2A < 8)  OCR2A = 8;    // Mínimo (0°)
    if (OCR2A > 38) OCR2A = 38;   // Máximo (180°)
    
    if (OCR0B < 8)  OCR0B = 8;    // Mínimo (0°)
    if (OCR0B > 38) OCR0B = 38;   // Máximo (180°)

    ADCSRA |= (1 << ADSC);  
}