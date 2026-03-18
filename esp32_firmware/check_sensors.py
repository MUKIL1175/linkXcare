from machine import ADC, Pin, I2C
import ssd1306
import time

# ---------- OLED Setup ----------
i2c = I2C(0, scl=Pin(9), sda=Pin(8))
oled = ssd1306.SSD1306_I2C(128, 64, i2c)

# ---------- Flex Sensor ADC Pins ----------
pins = [0, 1, 2, 3, 4]
adcs = []

for p in pins:
    adc = ADC(Pin(p))
    adc.atten(ADC.ATTN_11DB)   # 0-3.3V range
    adcs.append(adc)

oled.fill(0)
oled.text("Flex Test", 20, 0)
oled.show()

time.sleep(2)

# ---------- Main Loop ----------
while True:
    
    values = []
    
    for adc in adcs:
        values.append(adc.read())
    
    print("Flex values:", values)
    
    # OLED display
    oled.fill(0)
    oled.text("Flex Sensors", 10, 0)
    
    oled.text("F1: {}".format(values[0]), 0, 15)
    oled.text("F2: {}".format(values[1]), 0, 25)
    oled.text("F3: {}".format(values[2]), 0, 35)
    oled.text("F4: {}".format(values[3]), 0, 45)
    oled.text("F5: {}".format(values[4]), 0, 55)
    
    oled.show()
    
    time.sleep(0.5)
