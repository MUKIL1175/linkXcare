# import machine
# import time
# 
# try:
#     import ujson as json
# except:
#     import json
# 
# # -----------------------------
# # CONFIG
# # -----------------------------
# adc_pins = [0, 1, 2, 3, 4]
# CAL_FILE = "calib.json"
# 
# # -----------------------------
# # ADC SETUP
# # -----------------------------
# sensors = [machine.ADC(machine.Pin(p)) for p in adc_pins]
# 
# for s in sensors:
#     try:
#         s.atten(machine.ADC.ATTN_11DB)
#     except:
#         pass
# 
# # -----------------------------
# # HELPERS
# # -----------------------------
# def read_all(samples=20, delay_ms=5):
#     vals = [0]*5
#     for _ in range(samples):
#         for i, s in enumerate(sensors):
#             vals[i] += s.read()
#         time.sleep_ms(delay_ms)
#     return [v // samples for v in vals]
# 
# def save_cal(min_vals, max_vals):
#     try:
#         with open(CAL_FILE, "w") as f:
#             json.dump({"min": min_vals, "max": max_vals}, f)
#         print("Saved calibration")
#     except Exception as e:
#         print("Save error:", e)
# 
# # -----------------------------
# # CALIBRATION ONLY
# # -----------------------------
# print("\n=== AUTO CALIBRATION START ===")
# 
# print(" Keep your hand STRAIGHT")
# for i in range(3, 0, -1):
#     print("Capturing in", i, "...")
#     time.sleep(1)
# 
# min_vals = read_all()
# print("Min (straight):", min_vals)
# 
# print("\n Now BEND all fingers")
# for i in range(3, 0, -1):
#     print("Capturing in", i, "...")
#     time.sleep(1)
# 
# max_vals = read_all()
# print("Max (bent):", max_vals)
# 
# save_cal(min_vals, max_vals)
# 
# print("\n--- COPY THIS ---")
# print("min =", min_vals)
# print("max =", max_vals)
# 
# print("\n Calibration complete. Program stopped.")


import machine
import time
import network

try:
    import ujson as json
except:
    import json

try:
    import urequests as requests
except:
    import requests

# -----------------------------
# WIFI CONFIG
# -----------------------------
SSID = "glove"
PASSWORD = "12345678"

# -----------------------------
# FIREBASE URLS
# -----------------------------
URL_MIN = "https://finalyear-1df2d-default-rtdb.firebaseio.com/devices/glove_01/calibration/min.json"
URL_MAX = "https://finalyear-1df2d-default-rtdb.firebaseio.com/devices/glove_01/calibration/max.json"

# -----------------------------
# ADC CONFIG
# -----------------------------
adc_pins = [0, 1, 2, 3, 4]
CAL_FILE = "calib.json"

# -----------------------------
# WIFI CONNECT
# -----------------------------
def connect_wifi():
    wifi = network.WLAN(network.STA_IF)
    wifi.active(True)

    if not wifi.isconnected():
        print("Connecting to WiFi...")
        wifi.connect(SSID, PASSWORD)

        while not wifi.isconnected():
            time.sleep(1)
            print("...")

    print(" WiFi Connected:", wifi.ifconfig())

# -----------------------------
# ADC SETUP
# -----------------------------
sensors = [machine.ADC(machine.Pin(p)) for p in adc_pins]

for s in sensors:
    try:
        s.atten(machine.ADC.ATTN_11DB)
    except:
        pass

# -----------------------------
# HELPERS
# -----------------------------
def read_all(samples=20, delay_ms=5):
    vals = [0]*5
    for _ in range(samples):
        for i, s in enumerate(sensors):
            vals[i] += s.read()
        time.sleep_ms(delay_ms)
    return [v // samples for v in vals]

def save_cal(min_vals, max_vals):
    try:
        with open(CAL_FILE, "w") as f:
            json.dump({"min": min_vals, "max": max_vals}, f)
        print("💾 Saved locally")
    except Exception as e:
        print("Save error:", e)

def send_to_firebase(min_vals, max_vals):
    try:
        print("Uploading to Firebase...")

        r1 = requests.put(URL_MIN, json=min_vals)
        r1.close()

        r2 = requests.put(URL_MAX, json=max_vals)
        r2.close()

        print(" Uploaded to Firebase")

    except Exception as e:
        print(" Firebase Error:", e)

# -----------------------------
# START
# -----------------------------
connect_wifi()

print("\n=== AUTO CALIBRATION START ===")

print(" Keep your hand STRAIGHT")
for i in range(3, 0, -1):
    print("Capturing in", i, "...")
    time.sleep(1)

min_vals = read_all()
print("Min (straight):", min_vals)

print("\n Now BEND all fingers")
for i in range(3, 0, -1):
    print("Capturing in", i, "...")
    time.sleep(1)

max_vals = read_all()
print("Max (bent):", max_vals)

# -----------------------------
# SAVE + UPLOAD
# -----------------------------
save_cal(min_vals, max_vals)

print("\n--- COPY THIS ---")
print("min =", min_vals)
print("max =", max_vals)

send_to_firebase(min_vals, max_vals)

print("\n Calibration complete. Program stopped.")