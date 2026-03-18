import machine, ssd1306, time, network, urequests, json, os, ntptime

# --- 1. CONFIGURATION ---
WIFI_SSID = "linkglove"
WIFI_PASS = "12345678"
DB_URL = "https://finalyear-1df2d-default-rtdb.firebaseio.com/"
GLOVE_ID = "glove_01"  # Change to "glove_02" for second unit

# --- 2. HARDWARE SETUP ---
i2c = machine.I2C(0, scl=machine.Pin(9), sda=machine.Pin(8))
oled = ssd1306.SSD1306_I2C(128, 64, i2c)
btn = machine.Pin(5, machine.Pin.IN, machine.Pin.PULL_UP) # Calibration Button
sensors = [machine.ADC(machine.Pin(p)) for p in [3,2,0,1,4]]
for s in sensors: s.atten(machine.ADC.ATTN_11DB)

# --- 3. PERSISTENT STORAGE ---
CAL_FILE = "calibration.json"
MSG_FILE = "gestures.json"

# Default placeholders (Will be overwritten by calibration/sync)
min_v = [2000] * 5
max_v = [3500] * 5
local_msgs = {
    "thumb": "Water", "index": "Help", "middle": "Food", 
    "ring": "Meds", "pinky": "Restroom", "closed": "Emergency"
}

def save_json(filename, data):
    with open(filename, "w") as f:
        json.dump(data, f)

def load_json(filename):
    try:
        if filename in os.listdir():
            with open(filename, "r") as f:
                return json.load(f)
    except: return None
    return None

# --- 4. OLED & TIME HELPERS ---
def update_oled(t1, t2="", status="OFF"):
    oled.fill(0)
    oled.text("LinkXcare", 28, 0)
    oled.hline(0, 12, 128, 1)
    oled.text(status[0], 118, 2)
    # Centering logic for neat alignment
    oled.text(t1, int((128 - (len(t1)*8))/2), 30)
    oled.text(t2, int((128 - (len(t2)*8))/2), 48)
    oled.show()

def get_formatted_time():
    t = time.localtime()
    months = ["Jan", "Feb", "March", "April", "May", "June", "July", "Aug", "Sept", "Oct", "Nov", "Dec"]
    h = t[3] if t[3] <= 12 else t[3] - 12
    ap = "am" if t[3] < 12 else "pm"
    return "{}-{}-{} [{}:{:02d}{}]".format(t[2], months[t[1]-1], t[0], h, t[4], ap)

# --- 5. CORE FUNCTIONS ---
def run_calibration():
    global min_v, max_v
    # Step 1: Flat/Min
    update_oled("CALIBRATE", "Keep Flat...")
    time.sleep(3)
    min_v = [sensors[i].read() for i in range(5)]
    # Step 2: Bend/Max
    update_oled("CALIBRATE", "Clench Fist...")
    time.sleep(4)
    max_v = [sensors[i].read() for i in range(5)]
    
    save_json(CAL_FILE, {"min": min_v, "max": max_v})
    update_oled("SUCCESS", "Glove Ready")
    
    # Sync to Firebase if online
    if wlan.isconnected():
        try:
            cal_payload = {"min": min_v, "max": max_v, "updated_at": get_formatted_time()}
            urequests.patch(f"{DB_URL}/devices/{GLOVE_ID}/calibration.json", data=json.dumps(cal_payload)).close()
        except: pass

def sync_defaults():
    global local_msgs
    try:
        r = urequests.get(f"{DB_URL}/default_gestures.json")
        if r.status_code == 200:
            data = r.json()
            if data:
                save_json(MSG_FILE, data)
                local_msgs = data
        r.close()
    except: pass

# --- 6. INITIALIZE ---
cal_data = load_json(CAL_FILE)
if cal_data:
    min_v, max_v = cal_data['min'], cal_data['max']

msg_data = load_json(MSG_FILE)
if msg_data:
    local_msgs = msg_data

update_oled("Booting...", GLOVE_ID)
wlan = network.WLAN(network.STA_IF); wlan.active(True); wlan.connect(WIFI_SSID, WIFI_PASS)

# Connect & Sync
online = False
for _ in range(10):
    if wlan.isconnected():
        online = True
        try: ntptime.settime() # Sync RTC
        except: pass
        sync_defaults()
        break
    time.sleep(0.5)

last_heartbeat = 0
sos_locked = False

# --- 7. MAIN LOOP ---
while True:
    # 1. Check for Long Press (Calibration Trigger)
    if btn.value() == 0:
        start_hold = time.ticks_ms()
        while btn.value() == 0:
            if time.ticks_diff(time.ticks_ms(), start_hold) > 5000:
                run_calibration()
                break
            time.sleep(0.1)

    # 2. Read Sensors (Individual Calibration Applied)
    states = []
    percents = []
    for i in range(5):
        raw = sensors[i].read()
        # Individual Mapping
        p = int(max(0, min(100, (raw - min_v[i]) / (max_v[i] - min_v[i]) * 100)))
        percents.append(p)
        states.append(1 if p > 75 else 0)

    # 3. Local Gesture Engine
    current_key = "None"
    if sum(states) == 5:
        current_key = "closed"
    elif sum(states) == 1:
        keys = ["thumb", "index", "middle", "ring", "pinky"]
        current_key = keys[states.index(1)]
    
    msg = local_msgs.get(current_key, "Ready")
    mode_label = "Online" if wlan.isconnected() else "Offline"
    update_oled(msg, "", mode_label)

    # 4. WiFi Bridge
    if wlan.isconnected():
        if time.ticks_diff(time.ticks_ms(), last_heartbeat) > 5000:
            try:
                # Build Heartbeat & Live Data
                ts = get_formatted_time()
                payload = {
                    "fsr": percents,
                    "active_gesture": msg,
                    "heartbeat": time.time(),
                    "last_sync": ts
                }
                
                # SOS Flag Logic
                if current_key == "closed" and not sos_locked:
                    payload["sos_active"] = True
                    sos_locked = True
                
                # Check for App Handshake
                if sos_locked:
                    r = urequests.get(f"{DB_URL}/realtime/{GLOVE_ID}/sos_active.json")
                    if r.json() == False:
                        sos_locked = False
                    r.close()

                # Patch to Firebase
                urequests.patch(f"{DB_URL}/realtime/{GLOVE_ID}.json", data=json.dumps(payload)).close()
                last_heartbeat = time.ticks_ms()
            except: pass

    time.sleep(0.1)