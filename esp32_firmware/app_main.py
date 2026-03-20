import machine
import time
import network
import urequests
import gc

try:
    import ujson as json
except:
    import json

# -----------------------------
# CONFIG
# -----------------------------
WIFI_SSID = "glove"
WIFI_PASS = "12345678"

BASE_URL = "https://finalyear-1df2d-default-rtdb.firebaseio.com"

DEVICE = "glove_01"

CAL_MIN_URL = BASE_URL + "/devices/{}/calibration/min.json".format(DEVICE)
CAL_MAX_URL = BASE_URL + "/devices/{}/calibration/max.json".format(DEVICE)
CAL_TIME_URL = BASE_URL + "/devices/{}/calibration/updated_at.json".format(DEVICE)

FSR_URL = BASE_URL + "/realtime/{}/fsr.json".format(DEVICE)
ONLINE_URL = BASE_URL + "/realtime/{}/is_online.json".format(DEVICE)

GESTURE_URL = BASE_URL + "/default_gestures.json"

LOCAL_FILE = "local_data.json"

adc_pins = [0,1,2,3,4]

# -----------------------------
# OLED
# -----------------------------
import ssd1306
i2c = machine.I2C(0, sda=machine.Pin(8), scl=machine.Pin(9))
oled = ssd1306.SSD1306_I2C(128, 64, i2c)

def show(text):
    oled.fill(0)
    oled.text(text[:16], 0, 20)
    oled.show()

# -----------------------------
# BUTTON (for calibration)
# -----------------------------
button = machine.Pin(10, machine.Pin.IN, machine.Pin.PULL_UP)

# -----------------------------
# ADC
# -----------------------------
sensors = [machine.ADC(machine.Pin(p)) for p in adc_pins]
for s in sensors:
    try:
        s.atten(machine.ADC.ATTN_11DB)
    except:
        pass

# -----------------------------
# TIME FORMAT
# -----------------------------
months = ["jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec"]

def get_time_str():
    t = time.localtime()
    h = t[3]
    m = t[4]

    suffix = "am"
    if h >= 12:
        suffix = "pm"
    if h > 12:
        h -= 12

    m_str = "0"+str(m) if m < 10 else str(m)

    return "{}-{}-{}/{}:{}{}".format(
        t[2], months[t[1]-1], str(t[0])[2:], h, m_str, suffix
    )

# -----------------------------
# WIFI CONNECT
# -----------------------------
def connect_wifi():
    wlan = network.WLAN(network.STA_IF)
    wlan.active(True)
    wlan.connect(WIFI_SSID, WIFI_PASS)

    show("Connecting WiFi")

    for _ in range(10):
        if wlan.isconnected():
            print("WiFi Connected")
            show("WiFi OK")
            return True
        time.sleep(1)

    print("WiFi Failed")
    show("Offline Mode")
    return False

# -----------------------------
# READ SENSORS
# -----------------------------
def read_all():
    vals = [0]*5
    for _ in range(10):
        for i,s in enumerate(sensors):
            vals[i] += s.read()
        time.sleep_ms(5)
    return [v//10 for v in vals]

def get_percent(raw, min_v, max_v):
    if max_v == min_v:
        return 0
    if max_v > min_v:
        p = (raw - min_v)*100/(max_v-min_v)
    else:
        p = (min_v - raw)*100/(min_v-max_v)

    if p < 0: p = 0
    if p > 100: p = 100
    return int(p)

# -----------------------------
# LOCAL STORAGE
# -----------------------------
def save_local(data):
    with open(LOCAL_FILE, "w") as f:
        json.dump(data, f)

def load_local():
    try:
        with open(LOCAL_FILE) as f:
            return json.load(f)
    except:
        return None

# -----------------------------
# FIREBASE FUNCTIONS
# -----------------------------
def get_json(url):
    try:
        return urequests.get(url).json()
    except:
        return None

def put_json(url, data):
    try:
        urequests.put(url, json=data)
    except:
        pass

# -----------------------------
# LOAD DATA
# -----------------------------
def load_data(online):
    if online:
        min_vals = get_json(CAL_MIN_URL)
        max_vals = get_json(CAL_MAX_URL)
        gestures = get_json(GESTURE_URL)

        if min_vals and max_vals and gestures:
            save_local({
                "min": min_vals,
                "max": max_vals,
                "gestures": gestures
            })
            return min_vals, max_vals, gestures

    # fallback
    data = load_local()
    return data["min"], data["max"], data["gestures"]

# -----------------------------
# CHECK CALIB BUTTON
# -----------------------------
def check_calibration():
    if button.value() == 0:
        show("Calibrating...")
        time.sleep(1)
        import calibration   # your calibration.py
        machine.reset()

# -----------------------------
# MAIN
# -----------------------------
online = connect_wifi()

min_vals, max_vals, gestures = load_data(online)

last_online_update = 0

while True:
    gc.collect()

    check_calibration()

    raw = read_all()
    perc = []

    for i in range(5):
        perc.append(get_percent(raw[i], min_vals[i], max_vals[i]))

    # -------------------------
    # SEND TO FIREBASE
    # -------------------------
    if online:
        try:
            import ntptime
            print("Syncing time...")
            ntptime.settime()
            print("Time synced")
        except:
            print("NTP Failed")

        put_json(FSR_URL, {str(i): perc[i] for i in range(5)})

        if time.time() - last_online_update > 5:
            # Send UNIX Timestamp (integer) as the heartbeat
            put_json(ONLINE_URL, time.time())
            last_online_update = time.time()

        # refresh gestures dynamically
        new_gestures = get_json(GESTURE_URL)
        if new_gestures:
            gestures = new_gestures
            save_local({
                "min": min_vals,
                "max": max_vals,
                "gestures": gestures
            })

    # -------------------------
    # GESTURE DETECTION
    # -------------------------
    detected = "None"

    for name, pattern in gestures.items():
        match = True
        for i in range(5):
            if pattern[i] == 1 and perc[i] < 75:
                match = False
        if match:
            detected = name
            break

    # -------------------------
    # OLED DISPLAY
    # -------------------------
    oled.fill(0)
    oled.text("Gesture:", 0, 0)
    oled.text(detected[:12], 0, 15)

    for i in range(5):
        oled.text(str(perc[i]), 0, 30+i*8)

    oled.show()

    time.sleep(0.2)