from machine import ADC, Pin, I2C
import ssd1306
import time

# ---------- OLED ----------
i2c = I2C(0, scl=Pin(9), sda=Pin(8))
oled = ssd1306.SSD1306_I2C(128, 64, i2c)

# ---------- FLEX SENSORS ----------
pins = [3,2,0,1,4]
adcs = []

for p in pins:
    adc = ADC(Pin(p))
    adc.atten(ADC.ATTN_11DB)
    adcs.append(adc)

# ---------- CALIBRATION ----------
min_vals = [2970, 3578, 3385, 3197, 2955]
max_vals = [2959, 3679, 3416, 3223, 2958]

threshold = 60


def bend_percent(val, minv, maxv):
    percent = (val - minv) / (maxv - minv) * 100
    percent = max(0, min(100, percent))
    return percent


while True:

    percent = []

    for i in range(5):
        val = adcs[i].read()
        percent.append(bend_percent(val, min_vals[i], max_vals[i]))

    thumb  = percent[0] > threshold
    index  = percent[1] > threshold
    middle = percent[2] > threshold
    ring   = percent[3] > threshold
    pinky  = percent[4] > threshold

    message = "I'm okay"

    # ---------- GESTURE DETECTION ----------

    # FIST (all fingers)
    if thumb and index and middle and ring and pinky:
        message = "EMERGENCY!"

    # INDEX + MIDDLE
    elif index and middle and not(thumb or ring or pinky):
        message = "I need food"

    # THUMB
    elif thumb and not(index or middle or ring or pinky):
        message = "I need water"

    # INDEX
    elif index and not(thumb or middle or ring or pinky):
        message = "Use restroom"

    # RING
    elif ring and not(thumb or index or middle or pinky):
        message = "Need medicine"

    # PINKY
    elif pinky and not(thumb or index or middle or ring):
        message = "I need help"

    # NONE BENT
    elif not(thumb or index or middle or ring or pinky):
        message = "I'm okay"

    print(percent, message)

    # ---------- OLED DISPLAY ----------
    oled.fill(0)
    oled.text("Gesture:", 0, 10)
    oled.text(message, 0, 30)
    oled.show()

    time.sleep(0.3)