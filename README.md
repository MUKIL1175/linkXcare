# LinkXcare: Non-Verbal IoT Communication Glove

<p align="center">
  <a href="https://github.com/MUKIL1175/linkXcare">
    <img src="https://img.shields.io/badge/Repository-Link-blue?style=for-the-badge&logo=github&logoColor=white" alt="Repo Link">
  </a>
  <a href="https://raw.githubusercontent.com/MUKIL1175/linkXcare/main/app-release.apk">
    <img src="https://img.shields.io/badge/Download-APK-2E7D32?style=for-the-badge&logo=android&logoColor=white" alt="Download APK">
  </a>
</p>


**LinkXcare** is a mission-critical IoT medical companion system designed to provide non-verbal communication for patients with speech or motor impairments. It bridges the gap between patients and caregivers by translating finger gestures into real-time notifications, local OLED status, and high-priority emergency alerts.

---

## 🚀 Key Features

- **Real-Time Telemetry**: 5-channel button status visualized in a fluid, glassmorphic Dashboard.
- **Gesture Recognition**: Translates finger button presses into human-readable messages (e.g., "Need Water", "Restroom").
- **SOS Watchdog**: Dedicated emergency mode that triggers a full-screen red alert and audible alarm on the companion app.
- **Heartbeat Monitoring**: Real-time connectivity watchdog to ensure the device is online and data is valid.

---

## 🛠️ Hardware Stack & Components

### 1. Main Controller
- **MCU**: **ESP32-C3** (MicroPython Firmware)
  - Ultra-low power consumption for wearable use.
  - Onboard WiFi for real-time Firebase syncing.

### 2. Sensors & Input
- **Input Buttons**: 5x Tactile Buttons (one for each finger).
- **Setup**: Configured with internal pull-ups (Active LOW).

### 3. Output & Display
- **OLED Display**: 0.96" SSD1306 (128x64 pixels).
- **Audio/Vibe**: Managed via the Smartphone Companion App.

### 4. Wire Mapping (ESP32-C3)
| Component | Pin | Function |
|-----------|-----|----------|
| **Button 1 (Thumb)** | Pin 0 | Digital In (Pull-up) |
| **Button 2 (Index)** | Pin 1 | Digital In (Pull-up) |
| **Button 3 (Middle)**| Pin 2 | Digital In (Pull-up) |
| **Button 4 (Ring)**  | Pin 3 | Digital In (Pull-up) |
| **Button 5 (Pinky)** | Pin 4 | Digital In (Pull-up) |
| **OLED SCL**      | Pin 9 | I2C Clock |
| **OLED SDA**      | Pin 8 | I2C Data |

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
├── /companion_app          # Premium Modular Flutter App
│   ├── /lib/core/          # Global State & App Manager
│   ├── /lib/pages/         # UI Screens (Dashboard, History, etc.)
│   ├── /lib/theme/         # Anti-Gravity Theme Configuration
│   └── main.dart           # Clean Application Entry Point
├── /esp32_firmware         # MicroPython Firmware for Glove
├── firebase_rules.json     # Recommended Security Rules
├── alert.mp3               # SOS Alarm Audio
└── intro.mp3               # System Boot Audio
```

---

## 🛡️ Operation
- **Gesture Input**: Press the corresponding finger buttons to trigger gestures. The system detects "BENT" (Pressed) and "STRAIGHT" (Released) states.

---

---

### Creator & Lead Architect
**Monamukil SS**
*Visionary behind the LinkXcare platform.*
"Myself Monamukil, creator of this app, built to bridge the communication gap for the non-verbal."

### Designer (Research)
**Nisha Priyadharshini J**


---

## ⚖️ Licensing
This project is licensed under the **MIT License**. See the `LICENSE` file for details.
