import network
import urequests
import ujson
import time
from machine import Pin, I2C
import ssd1306

# ---------- CONFIG ----------
WIFI_SSID = "glove"
WIFI_PASS = "12345678"

BASE_URL = "https://finalyear-1df2d-default-rtdb.firebaseio.com"
GLOVE_ID = "glove_01"

# ---------- OLED ----------
i2c = I2C(0, scl=Pin(9), sda=Pin(8))
oled = ssd1306.SSD1306_I2C(128, 64, i2c)

def show_oled(text):
    oled.fill(0)
    oled.text("Gesture:", 0, 10)
    oled.text(text[:16], 0, 30)
    oled.show()

# ---------- BUTTONS ----------
pins = [0, 1, 2, 3, 4]
buttons = [Pin(p, Pin.IN, Pin.PULL_UP) for p in pins]

# 0 = straight, 1 = bent
def read_fingers():
    vals1 = [btn.value() for btn in buttons]
    time.sleep_ms(5)  # fast debounce
    vals2 = [btn.value() for btn in buttons]

    return [1 if (v1 == 0 and v2 == 0) else 0 for v1, v2 in zip(vals1, vals2)]

# ---------- WIFI ----------
def connect_wifi():
    wlan = network.WLAN(network.STA_IF)
    wlan.active(True)

    if not wlan.isconnected():
        wlan.connect(WIFI_SSID, WIFI_PASS)
        timeout = 10
        while not wlan.isconnected() and timeout > 0:
            time.sleep(1)
            timeout -= 1

    print("WiFi:", wlan.isconnected())
    return wlan.isconnected()

# ---------- FIREBASE ----------
def firebase_put(path, data):
    try:
        url = BASE_URL + path + ".json"
        r = urequests.put(url, data=ujson.dumps(data))
        r.close()
    except:
        print("PUT failed")

def firebase_get(path):
    try:
        url = BASE_URL + path + ".json"
        r = urequests.get(url)
        data = r.json()
        r.close()
        return data
    except:
        print("GET failed")
        return None

# ---------- DEFAULT GESTURES ----------
default_gestures = {}

def load_default():
    global default_gestures
    data = firebase_get("/default_gestures")

    if data:
        default_gestures = data
        print("Default updated")

        # SAVE LOCALLY
        try:
            with open("default_gestures.json", "w") as f:
                f.write(ujson.dumps(default_gestures))
        except:
            print("Save default failed")

def load_default_offline():
    global default_gestures
    try:
        with open("default_gestures.json") as f:
            default_gestures = ujson.loads(f.read())
            print("Loaded default offline")
    except:
        print("No default file")
        default_gestures = {}

# ---------- CUSTOM GESTURES ----------
custom_gestures = []

def load_custom():
    global custom_gestures
    data = firebase_get("/custom_gestures")

    if data:
        custom_gestures = []
        for key in data:
            g = data[key]
            custom_gestures.append({
                "pattern": g["tickBoxes"],
                "message": g["message"]
            })

        # SAVE LOCALLY
        try:
            with open("gestures.json", "w") as f:
                f.write(ujson.dumps(custom_gestures))
        except:
            print("Save custom failed")

        print("Custom gestures updated")

def load_custom_offline():
    global custom_gestures
    try:
        with open("gestures.json") as f:
            custom_gestures = ujson.loads(f.read())
            print("Loaded custom offline")
    except:
        custom_gestures = []

# ---------- DETECTION ----------
def detect_custom(states):
    for g in custom_gestures:
        if states == g["pattern"]:
            return g["message"]
    return None

def detect_default(states):
    mapping = {
        (1,1,1,1,1): "closed_fingers",
        (1,0,0,0,0): "thumb_finger",
        (0,1,0,0,0): "index_finger",
        (0,0,1,0,0): "middle_finger",
        (0,0,0,1,0): "ring_finger",
        (0,0,0,0,1): "pinky_finger"
    }

    key = tuple(states)

    if key in mapping:
        return default_gestures.get(mapping[key], "Unknown")

    return "None"

# ---------- HEARTBEAT ----------
def send_heartbeat():
    ts = int(time.time())
    firebase_put(f"/realtime/{GLOVE_ID}/heartbeat", ts)

# ---------- INIT ----------
wifi_ok = connect_wifi()

if wifi_ok:
    load_default()
    load_custom()
else:
    load_default_offline()
    load_custom_offline()

last_states = [0,0,0,0,0]
last_gesture = ""
last_fetch = 0
last_heartbeat = 0

# ---------- MAIN LOOP ----------
while True:

    states = read_fingers()

    # 1️⃣ Finger update
    if states != last_states:
        print("Finger:", states)

        if wifi_ok:
            firebase_put(f"/realtime/{GLOVE_ID}/finger_state", states)

        last_states = states

    # 2️⃣ Gesture detection
    msg = detect_custom(states)
    gesture = msg if msg else detect_default(states)

    # 3️⃣ Gesture update
    if gesture != last_gesture:
        print("Gesture:", gesture)

        if wifi_ok:
            firebase_put(f"/realtime/{GLOVE_ID}/active_gesture", gesture)

        show_oled(gesture)
        last_gesture = gesture

    # 4️⃣ Heartbeat (2 sec)
    if time.time() - last_heartbeat > 2:
        if wifi_ok:
            send_heartbeat()
        last_heartbeat = time.time()

    # 5️⃣ Auto refresh Firebase (5 sec)
    if time.time() - last_fetch > 5:
        if wifi_ok:
            load_default()
            load_custom()
        last_fetch = time.time()

    time.sleep(0.02)  # ⚡ FAST LOOP