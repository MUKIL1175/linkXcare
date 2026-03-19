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
  final DatabaseReference _statusRef = FirebaseDatabase.instance.ref('devices/glove_01/status');
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  bool isSosActive = false;
  bool isDeveloperMode = false;
  String currentGesture = "None";
  List<int> fsrValues = [0, 0, 0, 0, 0];
  int lastHeartbeat = 0;
  bool isGloveConnected = false;
  
  StreamSubscription<DatabaseEvent>? _gloveSubscription;
  StreamSubscription<DatabaseEvent>? _statusSubscription;
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
    _startStatusStream();
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
      
      final newGesture = data['active_gesture'] ?? "None";
      fsrValues = List<int>.from(data['fsr'] ?? [0, 0, 0, 0, 0]);
      lastHeartbeat = data['heartbeat'] ?? 0;
      
      _updateConnectionStatus();
      
      if (currentGesture != newGesture && newGesture != "None") {
        _showNotification(title: "Live Gesture Detected", body: "Message: $newGesture");
        logGesture(newGesture);
      }
      
      currentGesture = newGesture;
      
      if (currentGesture.toUpperCase() == "EMERGENCY" && !isSosActive) {
        triggerSOS(source: "Glove");
      }

      if (fsrValues.length == 5 && fsrValues.every((v) => v >= 90) && !isSosActive) {
        triggerSOS(source: "Closed Fingers");
      }
      
      notifyListeners();
    });
  }

  void _startStatusStream() {
    _statusSubscription?.cancel();
    _statusSubscription = _statusRef.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data == null) return;

      final bool online = data['is_online'] ?? false;
      final dynamic hb = data['heartbeat'];
      if (hb != null) {
        // Use local arrival time to avoid clock desync issues
        lastHeartbeat = DateTime.now().millisecondsSinceEpoch;
      }
      
      if (isGloveConnected != online) {
        isGloveConnected = online;
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
    // If no heartbeat received for 10sec, turn is_online: false locally
    final now = DateTime.now().millisecondsSinceEpoch;
    final bool heartbeatPulse = (now - lastHeartbeat) < 10000;
    
    if (!heartbeatPulse && isGloveConnected) {
       isGloveConnected = false;
       notifyListeners();
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

  void dispose() {
    _gloveSubscription?.cancel();
    _statusSubscription?.cancel();
    _heartbeatTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}
