from machine import Pin, I2C
import ssd1306
import time

# ---------- OLED SETUP ----------
i2c = I2C(0, scl=Pin(9), sda=Pin(8))
oled = ssd1306.SSD1306_I2C(128, 64, i2c)

# ---------- BUTTON SETUP ----------
pins = [0, 1, 2, 3, 4]
buttons = [Pin(p, Pin.IN, Pin.PULL_UP) for p in pins]

# Store previous states
prev_states = [btn.value() for btn in buttons]

# ---------- FUNCTION TO DISPLAY ----------
def update_display(states):
    oled.fill(0)
    oled.text("Finger Status", 10, 0)
    
    for i, state in enumerate(states):
        status = "BENT" if state == 0 else "STRAIGHT"
        oled.text("F{}: {}".format(i+1, status), 0, 12 + i*10)
    
    oled.show()

# Initial display
update_display(prev_states)

# ---------- MAIN LOOP ----------
while True:
    current_states = [btn.value() for btn in buttons]
    
    # Check for change
    if current_states != prev_states:
        print("Changed:", current_states)
        
        update_display(current_states)
        
        prev_states = current_states  # update memory
    
    time.sleep(0.05)  # small delay for stability