import machine, ssd1306, time, network, urequests, json, os, gc, esp

esp.osdebug(None)

# --- CONFIG ---
WIFI_SSID = "abc123"
WIFI_PASS = "12345678"
DB_URL = "https://finalyear-1df2d-default-rtdb.firebaseio.com"
GLOVE_ID = "glove_01"

# --- HARDWARE ---
i2c = machine.I2C(0, scl=machine.Pin(9), sda=machine.Pin(8))
oled = ssd1306.SSD1306_I2C(128, 64, i2c)
btn = machine.Pin(5, machine.Pin.IN, machine.Pin.PULL_UP)

sensors = [machine.ADC(machine.Pin(p)) for p in [3, 2, 0, 1, 4]]
for s in sensors:
    s.atten(machine.ADC.ATTN_11DB)

# --- STORAGE ---
CAL_FILE = "calibration.json"
MSG_FILE = "gestures.json"

min_v = [2000]*5
max_v = [3500]*5

local_msgs = {
    "thumb": "Water", "index": "Help", "middle": "Food",
    "ring": "Meds", "pinky": "Restroom", "closed": "Emergency"
}

# --- WIFI ---
wlan = network.WLAN(network.STA_IF)
wlan.active(True)

last_wifi_attempt = 0
wifi_fail_count = 0

# --- OLED ---
def update_oled(t1, t2="", status="OFF"):
    try:
        oled.fill(0)
        oled.text("LinkXcare", 20, 0)
        oled.hline(0, 12, 128, 1)
        oled.text(status[0], 118, 2)
        oled.text(t1[:16], 0, 28)
        oled.text(t2[:16], 0, 48)
        oled.show()
    except:
        pass

# --- SAFE WIFI MANAGER ---
def handle_wifi():
    global last_wifi_attempt, wifi_fail_count

    if wlan.isconnected():
        wifi_fail_count = 0
        return True

    now = time.ticks_ms()

    # wait 10 seconds between attempts
    if time.ticks_diff(now, last_wifi_attempt) < 10000:
        return False

    last_wifi_attempt = now

    try:
        print("WiFi retry...")

        # HARD RESET ONLY AFTER MULTIPLE FAILS
        if wifi_fail_count >= 3:
            print("Resetting WiFi module...")
            wlan.active(False)
            time.sleep(2)
            wlan.active(True)
            time.sleep(2)
            wifi_fail_count = 0

        wlan.connect(WIFI_SSID, WIFI_PASS)
        wifi_fail_count += 1

    except Exception as e:
        print("WiFi crash:", e)
        wifi_fail_count += 1

    return False

# --- LOAD FILES ---
def load_json(f):
    try:
        if f in os.listdir():
            with open(f) as file:
                return json.load(file)
    except:
        pass
    return None

cal = load_json(CAL_FILE)
if cal:
    min_v, max_v = cal["min"], cal["max"]

msg = load_json(MSG_FILE)
if msg:
    local_msgs = msg

# --- START ---
update_oled("Booting...", GLOVE_ID)
time.sleep(1)
update_oled("READY", GLOVE_ID)

# --- LOOP ---
last_sync = 0

while True:
    gc.collect()

    # --- WIFI ---
    handle_wifi()

    # --- SENSOR ---
    states = []
    percents = []

    for i in range(5):
        raw = sensors[i].read()
        denom = max(1, max_v[i] - min_v[i])
        p = int((raw - min_v[i]) * 100 / denom)
        p = max(0, min(100, p))

        percents.append(p)
        states.append(1 if p > 75 else 0)

    total = sum(states)

    key = "None"
    if total == 5:
        key = "closed"
    elif total == 1:
        try:
            key = ["thumb","index","middle","ring","pinky"][states.index(1)]
        except:
            pass

    msg = local_msgs.get(key, "Ready")

    update_oled(msg, "", "ON" if wlan.isconnected() else "OFF")

    # --- SEND DATA ---
    if wlan.isconnected() and time.ticks_ms() - last_sync > 5000:
        try:
            print("Sending...")

            payload = {
                "fsr": percents,
                "gesture": msg
            }

            r = urequests.patch(DB_URL + "/realtime/" + GLOVE_ID + ".json",
                                data=json.dumps(payload))
            r.close()
            del r

            last_sync = time.ticks_ms()

        except Exception as e:
            print("HTTP error:", e)
            last_sync = time.ticks_ms()

    time.sleep(0.2)