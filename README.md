# LinkXcare: Non-Verbal IoT Communication Glove

**LinkXcare** is a mission-critical IoT medical companion system designed to provide non-verbal communication for patients with speech or motor impairments. It bridges the gap between patients and caregivers by translating finger gestures into real-time notifications, local OLED status, and high-priority emergency alerts.

---

## 🚀 Key Features

- **Real-Time Telemetry**: 5-channel FSR data visualized in a fluid, glassmorphic Dashboard.
- **Gesture Recognition**: Translates complex finger positions into human-readable messages (e.g., "Need Water", "Restroom").
- **SOS Watchdog**: Dedicated emergency mode that triggers a full-screen red alert and audible alarm on the companion app.
- **Heartbeat Monitoring**: Real-time connectivity watchdog to ensure the device is online and data is valid.
- **Developer Mode**: Secure gate (Passcode: 1711) for calibration and manual sensor testing.

---

## 🛠️ Hardware Stack & Components

### 1. Main Controller
- **MCU**: **ESP32-C3** (MicroPython Firmware)
  - Ultra-low power consumption for wearable use.
  - Onboard WiFi for real-time Firebase syncing.

### 2. Sensors & Input
- **Flex Sensors**: 5x Force Sensitive Resistors (FSR) or Flex Slit Sensors.
- **Calibration Button**: Momentary tactile switch (used for zeroing the glove).

### 3. Output & Display
- **OLED Display**: 0.96" SSD1306 (128x64 pixels).
- **Audio/Vibe**: Managed via the Smartphone Companion App.

### 4. Wire Mapping (ESP32-C3)
| Component | Pin | Function |
|-----------|-----|----------|
| **FSR 1 (Thumb)** | Pin 3 | Analog In |
| **FSR 2 (Index)** | Pin 2 | Analog In |
| **FSR 3 (Middle)**| Pin 0 | Analog In |
| **FSR 4 (Ring)**  | Pin 1 | Analog In |
| **FSR 5 (Pinky)** | Pin 4 | Analog In |
| **OLED SCL**      | Pin 9 | I2C Clock |
| **OLED SDA**      | Pin 8 | I2C Data |
| **CAL Button**    | Pin 5 | Pulled Up |

---

## 💻 Software Setup

### Companion App (Flutter)
1. **Requirements**: Flutter SDK 3.x, Android Studio/Xcode.
2. **Setup**:
   - `cd companion_app`
   - `flutter pub get`
   - `flutter run`
3. **Firebase**: Ensure `google-services.json` is correctly placed in `android/app/`.

### Firmware (ESP32)
1. **Flash Tools**: Use Thonny IDE or `esptool.py`.
2. **Firmware**: Flash the latest MicroPython binary to the ESP32-C3.
3. **Files**: Upload all contents of the `/esp32_firmware` folder to the MCU.
4. **Configuration**: Update `app_main.py` with your WiFi Credentials and Firebase URL.

---

## 🖇️ Project Structure
```text
/linkXcare
├── /companion_app      # Flutter source code (Android/iOS)
├── /esp32_firmware     # MicroPython source code for the glove
├── alert.mp3           # Alarm resource
└── intro.mp3           # System boot audio
```

---

## 🛡️ Security & Calibration
- **Developer Access**: Enter `1711` in the About page to access raw sensor data.
- **Hardware Calibration**: Hold the physical button (Pin 5) for 5 seconds to trigger the "Min/Max" calibration routine. Keep fingers flat, then clench a fist when prompted.

---

### Developed by: **Nisha Priyadharshini J**
*Part of the EDP Medical IoT Research Initiative.*
