import sys
import time
import serial
from Adafruit_IO import MQTTClient

# Configuración de Adafruit IO
ADAFRUIT_IO_USERNAME = "Mario_Cano"
ADAFRUIT_IO_KEY = "aio_OhsL74nju5Gk5VSLboRTWhTBzDvr"

# Feeds de TX y RX para cada motor
MOTOR_FEEDS = {
    "A": {"TX": "MotorA_TX", "RX": "MotorA_RX"},
    "B": {"TX": "MotorB_TX", "RX": "MotorB_RX"},
    "C": {"TX": "MotorC_TX", "RX": "MotorC_RX"},
    "D": {"TX": "MotorD_TX", "RX": "MotorD_RX"}
}

# Configuración de la conexión serial
try:
    miarduino = serial.Serial(
        port='COM3',  # Cambia según tu puerto
        baudrate=9600,
        timeout=1  # Timeout de 1 segundo para las operaciones de lectura
    )
    print(f"Conectado al puerto {miarduino.name}")
except serial.SerialException as e:
    print(f"Error al abrir el puerto serial: {str(e)}")
    sys.exit(1)

def connected(client):
    print('\nConectado a Adafruit IO')
    for motor, feeds in MOTOR_FEEDS.items():
        print(f'Suscribiendo a {feeds["TX"]}')
        client.subscribe(feeds["TX"])
    print('Esperando comandos...')

def disconnected(client):
    print("Desconectado de Adafruit IO")
    sys.exit(1)

def message(client, feed_id, payload):
    print(f'Feed {feed_id} recibió el valor: {payload}')
    motor = None

    # Identifica el motor por el feed recibido
    for m, feeds in MOTOR_FEEDS.items():
        if feed_id == feeds["TX"]:
            motor = m
            break

    if motor is None:
        print(f"Feed desconocido: {feed_id}")
        return

    try:
        angle = int(payload)
        angle = max(0, min(180, angle))  # Lo limita entre 0 y 180
        to_send = f"{motor}:{angle}\r\n"
        miarduino.write(to_send.encode('utf-8'))
        print(f"Enviando al Arduino: {to_send.strip()}")

        # Esperar confirmación con timeout
        start_time = time.time()
        response_received = False

        while time.time() - start_time < 1:  # Timeout de 1 segundo
            if miarduino.in_waiting:
                try:
                    response = miarduino.readline().decode('utf-8', errors='ignore').strip()
                    if response.startswith("OK"):
                        print(f"Arduino confirmó: {response}")
                        client.publish(MOTOR_FEEDS[motor]["RX"], str(angle))
                        response_received = True
                        break
                except Exception as e:
                    print(f"Error leyendo respuesta: {str(e)}")
                    break

        if not response_received:
            print("No se recibió confirmación del Arduino")

    except ValueError:
        print(f"Valor inválido recibido: {payload}")
    except Exception as e:
        print(f"Error enviando comando: {str(e)}")

# Inicializar cliente MQTT
try:
    client = MQTTClient(ADAFRUIT_IO_USERNAME, ADAFRUIT_IO_KEY)
    client.on_connect = connected
    client.on_disconnect = disconnected
    client.on_message = message

    client.connect()
    client.loop_background()

    print("Sistema listo. Esperando comandos...")

    # Bucle principal
    while True:
        try:
            # Leer respuestas del Arduino si las hay
            if miarduino.in_waiting:
                try:
                    response = miarduino.readline().decode('utf-8', errors='ignore').strip()
                    if response and not response.startswith("OK"):  # Solo mostrar si no es una confirmación
                        print(f"Recibido del Arduino: {response}")

                        # Si es una posición de servo, actualizar el feed correspondiente
                        if response.startswith("POS:"):
                            parts = response[4:].split(',')
                            for part in parts:
                                if ':' in part:
                                    motor_letter, angle_str = part.split(':')
                                    motor = motor_letter[0]  # Tomar solo la primera letra (A, B, C, D)
                                    if motor in MOTOR_FEEDS:
                                        try:
                                            angle = int(angle_str)
                                            client.publish(MOTOR_FEEDS[motor]["RX"], str(angle))
                                            print(f"Actualizado feed {MOTOR_FEEDS[motor]['RX']} con valor {angle}")
                                        except ValueError:
                                            print(f"Valor inválido en respuesta: {angle_str}")
                except Exception as e:
                    print(f"Error leyendo datos seriales: {str(e)}")

            time.sleep(0.1)  # Pequeña pausa para no saturar la CPU

        except KeyboardInterrupt:
            print("\nCerrando conexiones...")
            miarduino.close()
            client.disconnect()
            sys.exit(0)

        except Exception as e:
            print(f"Error en bucle principal: {str(e)}")
            time.sleep(1)  # Esperar antes de reintentar

except Exception as e:
    print(f"Error de inicialización: {str(e)}")
    if 'miarduino' in locals() and miarduino.is_open:
        miarduino.close()
    sys.exit(1)