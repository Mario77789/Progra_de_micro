// ESP32: UART2 -> Adafruit IO, publicando 1 dato cada 2 s (S1, S2, S3)
// S1 (ultrasonico): 0/1 con umbral 5 cm
// S2 (luz): 0 / 45 / 90
// S3 (temperatura): 0/1 con umbral 27 °C

#include <WiFi.h>
#include "AdafruitIO_WiFi.h"
#include <HardwareSerial.h> 

// ====== CREDENCIALES ======
#define AIO_USER   "Mario_Cano"
#define AIO_KEY    "aio_qfMH82CrBHiRZfcP1jwA6MoBoywB"
#define WIFI_SSID  "Familia_CB"
#define WIFI_PASS  "336B5hxFvo"
// ==========================

// Feeds
#define FEED_ULTRA "sensor_ultrasonico"
#define FEED_LUZ   "sensor_luz"
#define FEED_TEMP  "sensor_temperatura"

// UART2 (mismo baud que tu maestro estable)
#define UART_BAUD  9600
#define RX2_PIN    16
#define TX2_PIN    17

// Lógica de mapeo
#define ULTRA_EVENT_CM   5        // <=5 cm -> 1
#define LUX_OFF_MAX      250      // 0..250  -> 0°
#define LUX_DIM_MAX      800      // 251..800-> 45°, >800->90°
#define TEMP_EVENT_C     27       // >=27 -> 1   (<<< umbral editable)

// Cadencia: 1 publicación / 2 s
#define PUB_PERIOD_MS    2000UL

AdafruitIO_WiFi io(AIO_USER, AIO_KEY, WIFI_SSID, WIFI_PASS);
AdafruitIO_Feed *f_ultra = io.feed(FEED_ULTRA);
AdafruitIO_Feed *f_luz   = io.feed(FEED_LUZ);
AdafruitIO_Feed *f_temp  = io.feed(FEED_TEMP);

HardwareSerial Maestro(2);

// Helpers
static inline int lux_to_angle(long lux){
  if (lux <= LUX_OFF_MAX)      return 0;
  else if (lux <= LUX_DIM_MAX) return 45;
  else                         return 90;
}

void setup(){
  Serial.begin(115200);
  delay(50);
  Serial.println("\nESP32 UART2 -> Adafruit IO (rotación S1/S2/S3, 1 dato/2s)");

  Maestro.begin(UART_BAUD, SERIAL_8N1, RX2_PIN, TX2_PIN);
  Maestro.setRxBufferSize(512);
  Maestro.setTimeout(250);
  Serial.printf("UART2 @ %d bps  (RX2=%d, TX2=%d)\n", UART_BAUD, RX2_PIN, TX2_PIN);

  Serial.println("Conectando a Adafruit IO...");
  io.connect();
  while (io.status() < AIO_CONNECTED) {
    Serial.printf("Estado AIO: %s\n", io.statusText());
    delay(500);
  }
  Serial.printf("Conectado: %s\n", io.statusText());
  Serial.println("S1:  S2:  S3:");
}

void loop(){
  io.run();

  // === Leer la línea del Maestro: "cm,lux,temp\n" ===
  static char linea[128];
  static bool  have_data = false;
  static int   last_cm = -1, last_temp = -1;
  static long  last_lux = -1;

  if (Maestro.available()){
    size_t n = Maestro.readBytesUntil('\n', linea, sizeof(linea)-1);
    if (n > 0){
      if (linea[n-1] == '\r') n--;
      linea[n] = '\0';

      int cm=-1, tC=-1; long lux=-1;
      if (sscanf(linea, "%d,%ld,%d", &cm, &lux, &tC) == 3){
        last_cm = cm; last_lux = lux; last_temp = tC; have_data = true;
        int ang = lux_to_angle(lux);
        Serial.printf("S1:%3d  S2:%3d  S3:%2dC   RAW='%s'\n", cm, ang, tC, linea);
      } else {
        Serial.printf("Linea invalida: '%s'\n", linea);
      }
    }
  }

  // === Publicación rotando: 0->S1, 1->S2, 2->S3 ===
  if (!have_data) return;

  static unsigned long next_pub = 0;
  static uint8_t step = 0;

  unsigned long now = millis();
  if ((long)(now - next_pub) < 0) return;

  switch (step){
    case 0: { // S1: Ultrasonico 0/1 con umbral 5 cm
      int v = (last_cm >= 0 && last_cm <= ULTRA_EVENT_CM) ? 1 : 0;
      f_ultra->save(v);
      Serial.printf("PUB -> %s = %d  (cm=%d, umbral=%d)\n",
                    FEED_ULTRA, v, last_cm, ULTRA_EVENT_CM);
    } break;

    case 1: { // S2: Luz 0/45/90
      int ang = lux_to_angle(last_lux);
      f_luz->save(ang);
      Serial.printf("PUB -> %s = %d  (lux=%ld)\n",
                    FEED_LUZ, ang, last_lux);
    } break;

    case 2: { // S3: Temp 0/1 con umbral 27 °C
      int v = (last_temp >= 0 && last_temp >= TEMP_EVENT_C) ? 1 : 0;
      f_temp->save(v);
      Serial.printf("PUB -> %s = %d  (temp=%d, umbral=%d)\n",
                    FEED_TEMP, v, last_temp, TEMP_EVENT_C);
    } break;
  }

  step = (step + 1) % 3;
  next_pub = now + PUB_PERIOD_MS;  // 1 mensaje cada 2 s
}
