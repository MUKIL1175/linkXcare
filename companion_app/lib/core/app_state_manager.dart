import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class AppStateManager extends ChangeNotifier {
  static final AppStateManager _instance = AppStateManager._internal();
  factory AppStateManager() => _instance;
  AppStateManager._internal();

  final ap.AudioPlayer _audioPlayer = ap.AudioPlayer();
  final DatabaseReference _gloveRef = FirebaseDatabase.instance.ref('realtime/glove_01');
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  bool isSosActive = false;
  bool isDeveloperMode = false;
  String currentGesture = "None";
  List<int> fsrValues = [0, 0, 0, 0, 0];
  int lastHeartbeat = 0;
  bool isGloveConnected = false;
  Map<String, dynamic> _customGestures = {};
  
  StreamSubscription<DatabaseEvent>? _gloveSubscription;
  StreamSubscription<DatabaseEvent>? _customSubscription;
  Timer? _heartbeatTimer;

  Future<void> initialize() async {
    FirebaseDatabase.instance.setLoggingEnabled(true);
    try {
      FirebaseDatabase.instance.setPersistenceEnabled(true);
    } catch (e) {
      print("DEBUG: Persistence Error: $e");
    }

    final prefs = await SharedPreferences.getInstance();
    isDeveloperMode = prefs.getBool('dev_mode') ?? false;

    // Set default volume to 70%
    await _audioPlayer.setVolume(0.7);

    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: null,
    );
    
      _glovePluginPermission();
    _startGloveStream();
    _startCustomGesturesStream();
    _startHeartbeatWatchdog();

    try {
      await seedDefaultsIfEmpty().timeout(const Duration(seconds: 4));
    } catch (e) {
      print("DEBUG: Seed Defaults Timeout/Error: $e");
    }
  }

  void _startGloveStream() {
    _gloveSubscription?.cancel();
    _gloveSubscription = _gloveRef.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data == null) return;
      
      // 1. Update Core Data
      String resolvedGesture = (data['active_gesture'] ?? data['gesture']) ?? "None";
      fsrValues = List<int>.from(data['fsr'] ?? [0, 0, 0, 0, 0]);

      // 2. Custom & Default Gesture Resolution
      if (resolvedGesture == "None" || resolvedGesture == "Ready") {
        final currentFingerStates = fsrValues.map((v) => v > 75 ? 1 : 0).toList();
        
        // Check Custom Gestures First
        bool foundCustom = false;
        _customGestures.forEach((key, value) {
          if (foundCustom) return;
          if (value is Map) {
            final ticks = List<int>.from(value['tickBoxes'] ?? []);
            if (listEquals(ticks, currentFingerStates) && ticks.contains(1)) {
              resolvedGesture = value['message'] ?? resolvedGesture;
              foundCustom = true;
            }
          }
        });

        // Fallback to Single-Finger Defaults if no custom match
        if (!foundCustom) {
          for (int i = 0; i < fsrValues.length; i++) {
            if (fsrValues[i] > 75) {
              resolvedGesture = _getGestureForFinger(index: i);
              break; 
            }
          }
        }
      }
      
      // 3. Update Heartbeat
      final int hb = data['heartbeat'] ?? 0;
      if (hb > 0) {
        lastHeartbeat = hb;
      }
      
      // 4. Update Connection Status (Support both Boolean, Timestamp, and String Heartbeats)
      final dynamic onlineRaw = data['is_online'];
      if (onlineRaw is num) {
        // MicroPython time.time() starts from year 2000.
        // Dart DateTime starts from year 1970.
        // Offset = 946684800 seconds (or 946684800000 milliseconds).
        lastHeartbeat = (onlineRaw.toDouble() * 1000).toInt() + 946684800000;
      } else if (onlineRaw is String) {
        final parsed = _parseCustomTime(onlineRaw);
        if (parsed != null) {
          lastHeartbeat = parsed.millisecondsSinceEpoch;
        }
      }
      
      final now = DateTime.now().millisecondsSinceEpoch;
      final bool pulse = (now - lastHeartbeat).abs() < 15000; // Use .abs() to handle slight clock drift

      if (isGloveConnected != pulse) {
        isGloveConnected = pulse;
      }
      
      // 5. Reactive Events (Notifications, Logic)
      if (currentGesture != resolvedGesture && resolvedGesture != "None" && resolvedGesture != "Ready") {
        _showNotification(title: "Live Gesture Detected", body: "Message: $resolvedGesture");
        logGesture(resolvedGesture);
      }
      
      currentGesture = resolvedGesture;
      
      if (currentGesture.toUpperCase() == "EMERGENCY" && !isSosActive) {
        triggerSOS(source: "Glove");
      }

      if (fsrValues.length == 5 && fsrValues.every((v) => v >= 90) && !isSosActive) {
        triggerSOS(source: "Closed Fingers");
      }
      
      // 6. Watchdog Correction (Sync back to Firebase if dead)
      _updateConnectionStatus();

      notifyListeners();
    });
  }

   void _startCustomGesturesStream() {
    _customSubscription?.cancel();
    _customSubscription = FirebaseDatabase.instance.ref('custom_gestures').onValue.listen((event) {
      final data = event.snapshot.value;
      if (data is Map) {
        _customGestures = Map<String, dynamic>.from(data);
        notifyListeners();
      }
    });
  }

  void _startHeartbeatWatchdog() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _updateConnectionStatus();
    });
  }

  void _updateConnectionStatus() {
    // Universal Server Timestamp Strategy: compare milliseconds
    final now = DateTime.now().millisecondsSinceEpoch;
    final bool heartbeatPulse = (now - lastHeartbeat).abs() < 15000; // 15s buffer for server/local delta
    
    // Watchdog: If heartbeat is dead, force Firebase to false
    if (!heartbeatPulse && isGloveConnected) {
       _gloveRef.update({'is_online': false}).catchError((e) => null);
    }
  }

  String _getGestureForFinger({required int index}) {
    switch (index) {
      case 0: return "Need water";
      case 1: return "Restroom";
      case 2: return "Need food";
      case 3: return "Need medicines";
      case 4: return "Need assistance";
      default: return "Unknown";
    }
  }

  void _glovePluginPermission() {
    _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> _showNotification({required String title, required String body, bool isHighPriority = false}) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      isHighPriority ? 'sos_channel_id' : 'gesture_channel_id',
      isHighPriority ? 'SOS Alerts' : 'Live Gestures',
      importance: isHighPriority ? Importance.max : Importance.defaultImportance,
      priority: isHighPriority ? Priority.high : Priority.defaultPriority,
      ticker: 'ticker',
    );
    final NotificationDetails details = NotificationDetails(android: androidDetails);
    try {
      await _flutterLocalNotificationsPlugin.show(
        id: isHighPriority ? 1 : 0, 
        title: title, 
        body: body, 
        notificationDetails: details
      );
    } catch (e) {
      print("DEBUG: Notification Error: $e");
    }
  }

  Future<void> seedDefaultsIfEmpty() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('did_seed_v3') ?? false) return;

    final ref = FirebaseDatabase.instance.ref('default_gestures');
    try {
      await ref.set({
        'thumb_finger': 'Need water',
        'index_finger': 'Restroom',
        'middle_finger': 'Need food',
        'ring_finger': 'Need medicines',
        'pinky_finger': 'restroom',
        'closed_fingers': 'Emergency',
      }).timeout(const Duration(seconds: 2));
      await prefs.setBool('did_seed_v3', true);
    } catch (e) {
      await prefs.setBool('did_seed_v3', true);
    }
  }

  Future<void> triggerSOS({required String source}) async {
    if (isSosActive) return;
    isSosActive = true;
    notifyListeners();

    try {
      _showNotification(title: "SOS EMERGENCY", body: "Patient triggered SOS from $source!", isHighPriority: true);
      await _audioPlayer.setVolume(0.7);
      await _audioPlayer.setReleaseMode(ap.ReleaseMode.loop);
      await _audioPlayer.play(ap.AssetSource('alert.mp3'));
      if (await Vibration.hasVibrator() == true) {
        Vibration.vibrate(pattern: [500, 1000, 500, 1000], repeat: 0);
      }
    } catch (e) {
      print("DEBUG: SOS Error: $e");
    }
  }

  Future<void> stopSOS() async {
    if (!isSosActive) return;
    isSosActive = false;
    notifyListeners();
    
    await _audioPlayer.stop();
    await _audioPlayer.setReleaseMode(ap.ReleaseMode.release);
    Vibration.cancel();
    
    if (!isDeveloperMode) {
       _gloveRef.update({'active_gesture': 'None'});
    }
  }

  Future<void> playIntro() async {
    try {
      await _audioPlayer.setVolume(0.7);
      await _audioPlayer.play(ap.AssetSource('intro.mp3'));
    } catch (e) {
      print("DEBUG: Intro Audio Error: $e");
    }
  }

  Future<void> logGesture(String message) async {
    final String path = isDeveloperMode ? 'logs/dev_history/glove_01' : 'logs/real_history/glove_01';
    final ref = FirebaseDatabase.instance.ref(path).push();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    await ref.set({
      'msg': message,
      'time': now,
      'source': isDeveloperMode ? 'Developer Simulation' : 'Physical Glove'
    });
  }

  DateTime? _parseCustomTime(String value) {
    try {
      // Format: 20-mar-26/5:57pm
      final parts = value.split('/');
      if (parts.length != 2) return null;
      
      final dateParts = parts[0].split('-');
      if (dateParts.length != 3) return null;
      
      final day = int.parse(dateParts[0]);
      final monthStr = dateParts[1].toLowerCase();
      final year = int.parse("20${dateParts[2]}");
      
      final months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
      final month = months.indexOf(monthStr) + 1;
      
      final timePart = parts[1];
      final isPm = timePart.toLowerCase().endsWith('pm');
      final cleanTime = timePart.replaceAll('am', '').replaceAll('pm', '');
      final timeParts = cleanTime.split(':');
      int hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);
      
      if (isPm && hour < 12) hour += 12;
      if (!isPm && hour == 12) hour = 0;
      
      return DateTime(year, month, day, hour, minute);
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    _gloveSubscription?.cancel();
    _customSubscription?.cancel();
    _heartbeatTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}
