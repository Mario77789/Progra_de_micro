/*
 * EEPROM.c
 *
 * Created: 25/04/2025 
 * Author : Mario
 * Description: Comunicador serial
 */  
//  
// Encabezado (Libraries)  

//Function Prototypes

void writeEEPROM(uint8_t dato, uint16_t direccion);
uint8_t readEEPROM (uint16_t eeprom_address);

uint16_t
// Main Function  
int main(void)  
{  

	uint8_t temporal = readEEPROM(0x00);
	writeChar(temporal);
	
	
    while (temporal != 0xFF)  
    {
		  writeChar(temporal);
		  eeprom_address++;
		  temporal = readEEPROM(eeprom_address);
	}
	
	while (1)
	{
	}
}  

//  
// NON-Interrupt subroutines  
void writeEEPROM(uint8_t dato, uint16_t direccion)
{
	
	//ESPERANDO A TERMINAR DE "ESCRIBIR"
	uint8_t temporal = EECR & (1<<EEPE);
	while ((EECR & (1<<EEPE)));
	
	//ESTABLECER DIRECCIÓN
	
	EEAR = direccion
	
	
	//ESTABLECER DATO
	
	EEDR = dato;
	
	//MASTER WRITE
	
	EECR |= (1<<EEPE)
	
	//WRITE ENABLE
	
	EECR |= (1<<EEPE);

}

uint8_t readEEPROM (uint16_t eeprom_address)
{
	//ESPERANDO A TERMINAR DE "ESCRIBIR"
	uint8_t temporal = EECR & (1<<EEPE);
	while ((EECR & (1<<EEPE)));
		
	//ESTABLECER DIRECCIÓN
		
	EEAR = eeprom_address
	
	//Empezar a leer
	
	EECR |= (1<<EERE);
	
	//RETORNAR EL VALOR LEIODO
	return EEDR;
}

//  
// Interrupt routines  
