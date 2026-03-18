from machine import ADC, Pin, I2C
import ssd1306
import time

# ---------- OLED Setup ----------
i2c = I2C(0, scl=Pin(9), sda=Pin(8))
oled = ssd1306.SSD1306_I2C(128, 64, i2c)

# ---------- Flex Sensor ADC Pins ----------
pins = [3,2,0,1,4]
adcs = []

for p in pins:
    adc = ADC(Pin(p))
    adc.atten(ADC.ATTN_11DB)
    adcs.append(adc)

min_vals = [0]*5
max_vals = [0]*5


#---------- STEP 1 : STRAIGHT ----------
oled.fill(0)
oled.text("Keep Fingers", 10, 20)
oled.text("STRAIGHT", 30, 35)
oled.show()

print("Keep fingers straight")
time.sleep(5)

for i in range(5):
    min_vals[i] = adcs[i].read()

print("Min values:", min_vals)


# ---------- STEP 2 : BEND ----------
oled.fill(0)
oled.text("Bend Fingers", 10, 20)
oled.text("FULLY", 40, 35)
oled.show()

print("Bend fingers fully")
time.sleep(5)

for i in range(5):
    max_vals[i] = adcs[i].read()

print("Max values:", max_vals)

oled.fill(0)
oled.text("Calibration", 20, 25)
oled.text("Done!", 40, 40)
oled.show()

time.sleep(2)


# ---------- MAIN LOOP ----------
while True:

    values = []
    percent = []

    for i in range(5):

        val = adcs[i].read()
        values.append(val)

        # map value to percentage
        bend = (val - min_vals[i]) / (max_vals[i] - min_vals[i]) * 100
        bend = max(0, min(100, bend))

        percent.append(int(bend))


    print("Raw:", values)
    print("Bend %:", percent)

    # OLED Display
    oled.fill(0)
    oled.text("Flex %", 40, 0)

    oled.text("F1: {}".format(percent[0]), 0, 15)
    oled.text("F2: {}".format(percent[1]), 0, 25)
    oled.text("F3: {}".format(percent[2]), 0, 35)
    oled.text("F4: {}".format(percent[3]), 0, 45)
    oled.text("F5: {}".format(percent[4]), 0, 55)

    oled.show()

    time.sleep(0.5)