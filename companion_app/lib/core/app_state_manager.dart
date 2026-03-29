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
  String currentGesture = "None";
  List<int> fingerState = [0, 0, 0, 0, 0];
  int lastHeartbeat = 0; // Unix seconds
  bool isGloveConnected = false;
  bool _isFirstGloveEvent = true;
  Map<String, dynamic> _customGestures = {};
  Map<String, String> _defaultGestures = {};
  int _lastHeartbeatValue = 0;

  StreamSubscription<DatabaseEvent>? _gloveSubscription;
  StreamSubscription<DatabaseEvent>? _customSubscription;
  StreamSubscription<DatabaseEvent>? _defaultGesturesSubscription;
  Timer? _heartbeatTimer;

  Future<void> initialize() async {
    FirebaseDatabase.instance.setLoggingEnabled(true);
    try {
      FirebaseDatabase.instance.setPersistenceEnabled(true);
    } catch (e) {
      print("DEBUG: Persistence Error: $e");
    }

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
    _startDefaultGesturesStream();
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

      fingerState = List<int>.from(data['finger_state'] ?? [0, 0, 0, 0, 0]);

      // Resolve gesture exactly like ESP32
      String resolvedGesture = data['active_gesture']?.toString() ?? "None";
      if (resolvedGesture == "None" || resolvedGesture == "Unknown Pattern") {
        bool foundCustom = false;
        _customGestures.forEach((key, value) {
          if (foundCustom) return;
          if (value is Map) {
            final ticks = List<int>.from(value['tickBoxes'] ?? []);
            if (listEquals(ticks, fingerState) && ticks.contains(1)) {
              resolvedGesture = value['message'] ?? "None";
              foundCustom = true;
            }
          }
        });

        if (!foundCustom) {
          int activeCount = fingerState.where((s) => s == 1).length;
          if (activeCount == 1) {
            for (int i = 0; i < fingerState.length; i++) {
              if (fingerState[i] == 1) {
                resolvedGesture = _getGestureForFinger(index: i);
                break;
              }
            }
          } else if (activeCount == 5) {
            resolvedGesture = _defaultGestures['closed_fingers'] ?? "Emergency";
          }
        }
      }

      // 3. Update Heartbeat & Internal Receipt Time
      // We treat ANY data coming from the glove as a valid 'pulse' of life.
      if (!_isFirstGloveEvent) {
        lastHeartbeat = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        
        // Update is_online in Firebase only when the heartbeat value actually changes
        final int hb = data['heartbeat'] ?? 0;
        if (hb > 0 && hb != _lastHeartbeatValue) {
          _lastHeartbeatValue = hb;
          _updateLastOnlineTime();
        }
      }
      _isFirstGloveEvent = false;

      // Reactive Events
      if (currentGesture != resolvedGesture && resolvedGesture != "None") {
        _showNotification(title: "Live Gesture Detected", body: resolvedGesture);
        logGesture(resolvedGesture);
        _gloveRef.update({'active_gesture_online': resolvedGesture});
      }

      currentGesture = resolvedGesture;

      if (currentGesture.toLowerCase() == "emergency" && !isSosActive) {
        triggerSOS(source: "Glove");
      }

      if (fingerState.every((s) => s == 1) && !isSosActive) {
        triggerSOS(source: "Closed Fingers");
      }

      notifyListeners();
    });
  }

  void _updateLastOnlineTime() {
    final now = DateTime.now();
    final months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
    final formattedTime = "${now.day.toString().padLeft(2, '0')}-${months[now.month - 1]}-${now.year.toString().substring(2)}/${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    _gloveRef.update({'is_online': formattedTime});
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

  void _startDefaultGesturesStream() {
    _defaultGesturesSubscription?.cancel();
    _defaultGesturesSubscription = FirebaseDatabase.instance.ref('default_gestures').onValue.listen((event) {
      final data = event.snapshot.value;
      if (data is Map) {
        _defaultGestures = data.map((key, value) => MapEntry(key.toString(), value.toString()));
        notifyListeners();
      }
    });
  }

  void _startHeartbeatWatchdog() {
    _heartbeatTimer?.cancel();
    // High-performance 1-second interval for near-instant UI updates
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
       // Optional: Actively check heartbeat value if stream feels stagnant
      final snapshot = await _gloveRef.child('heartbeat').get();
      final hb = snapshot.value as int?;
      if (hb != null && hb != _lastHeartbeatValue) {
        _lastHeartbeatValue = hb;
        lastHeartbeat = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        _updateLastOnlineTime();
      }
      _updateConnectionStatus();
    });
  }

  void _updateConnectionStatus() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Stable 10-second threshold.
    final bool pulse = lastHeartbeat > 0 && (now - lastHeartbeat) < 10;
    if (isGloveConnected != pulse) {
      print("DEBUG: Connection Status Updated: $pulse (Diff: ${now - lastHeartbeat}s)");
      isGloveConnected = pulse;
      notifyListeners();
    }
  }

  String _getGestureForFinger({required int index}) {
    final keys = ['thumb_finger', 'index_finger', 'middle_finger', 'ring_finger', 'pinky_finger'];
    if (index < 0 || index >= keys.length) return "Unknown";
    final key = keys[index];
    if (_defaultGestures.containsKey(key)) return _defaultGestures[key]!;
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
        notificationDetails: details,
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
        'pinky_finger': 'Need assistance',
        'closed_fingers': 'Emergency',
      }).timeout(const Duration(seconds: 2));
      await prefs.setBool('did_seed_v3', true);
    } catch (_) {
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
    _gloveRef.update({'active_gesture': 'None', 'active_gesture_online': 'None'});
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
    final ref = FirebaseDatabase.instance.ref('logs/real_history/glove_01').push();
    final now = DateTime.now().millisecondsSinceEpoch;
    await ref.set({'msg': message, 'time': now, 'source': 'Physical Glove'});
  }

  @override
  void dispose() {
    _gloveSubscription?.cancel();
    _customSubscription?.cancel();
    _defaultGesturesSubscription?.cancel();
    _heartbeatTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}
