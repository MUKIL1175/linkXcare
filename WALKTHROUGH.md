# LinkXcare Companion App Walkthrough

The LinkXcare Companion app has been upgraded with the new "Anti-Gravity" technical specification and visual aesthetic. 

## Key Achievements

- **Anti-Gravity UI Redesign**: 
    - Implemented a deep indigo dark theme (`#0F172A`).
    - Integrated Glassmorphic containers with 15px `BackdropFilter` blurs and 20% opacity.
    - Created 5 animated "liquid-style" vertical progress bars for real-time FSR telemetry.
- **Technical Overhaul**:
    - Updated project to use **Gradle 8.10.2**, matching the modern AGP 8.5.0 and Kotlin 2.1.0 requirements.
    - Enabled **Core Library Desugaring** (version 2.1.4) to support `flutter_local_notifications` and Java 8+ features on older Android versions.
- **Server Timestamp Heartbeat**:
    - Switched to **Firebase Server Timestamps** (`{".sv": "timestamp"}`) for heartbeats.
    - This eliminates dependencies on the ESP32's internal clock or NTP sync.
    - The App now monitors the 15-second window with millisecond precision against the server's time.
- **Firebase Alignment**:
    - Verified connectivity to the updated Firebase structure (`realtime/glove_01`, `logs/glove_01`).
    - Implemented high-priority SOS overlay with glassmorphism and looping alarm triggers.
    - Standardized timestamps across the app to `dd-MMMM-yyyy [h:mma]`.

---

## Technical Details

### Gradle & Build Configuration
The project was updated to resolve compilation errors related to `FlutterPlugin.kt` and `flutter_local_notifications`.

#### `android/gradle/wrapper/gradle-wrapper.properties`
Updated to Gradle 8.10.2 for compatibility with AGP 8.5.0.

#### `android/app/build.gradle.kts`
```kotlin
compileOptions {
    isCoreLibraryDesugaringEnabled = true
}
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

---

---

## 🏗️ Technical Refactor & Repository Organization

### 1. Modular Architecture (lib/)
- **`core/app_state_manager.dart`**: Centralized logic for Firebase syncing, SOS, and Heartbeat.
- **`theme/anti_gravity_theme.dart`**: Isolated "Anti-Gravity" Glassmorphic theme data.
- **`pages/`**: Modularized screens (Dashboard, Default/Custom Gestures, History, About).
- **`main.dart`**: Clean, lightweight entry point and splash screen logic.

### 2. Unified Repository (`linkXcare/`)
The project is now a professional-grade repository containing:
- **`companion_app/`**: The refactored Flutter codebase.
- **`esp32_firmware/`**: MicroPython scripts for the Glove hardware.
- **`firebase_rules.json`**: Production-ready security rules for your Firebase console.
- **`README.md`**: Master technical specification and setup guide.

### 3. Advanced Credits & Refined Dev UI
- **Conditional Credits**: The About page dynamically switches between "Nisha Priyadharshini J" (Standard) and "Monamukil SS" (Developer Mode) to provide proper researcher and creator attribution.
- **Developer Aesthetic**: Upgraded the Developer Mode panel to a polished Indigo/Cyan theme, removing redundant buttons for a cleaner, technical workflow.

## ⚖️ Licensing
- **MIT License**: Included a `LICENSE` file to ensure the project meets open-source distribution standards.
