import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class AppStateManager {
  static final AppStateManager _instance = AppStateManager._internal();
  factory AppStateManager() => _instance;
  AppStateManager._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final DatabaseReference _gloveRef = FirebaseDatabase.instance.ref('realtime/glove_01');
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  bool isSosActive = false;
  bool isDeveloperMode = false;
  String currentGesture = "None";
  List<int> fsrValues = [0, 0, 0, 0, 0];
  int lastHeartbeat = 0;
  bool isGloveConnected = false;
  
  StreamSubscription<DatabaseEvent>? _gloveSubscription;
  Timer? _heartbeatTimer;
  Function()? onStateChanged;

  Future<void> initialize() async {
    FirebaseDatabase.instance.setLoggingEnabled(true);
    try {
      FirebaseDatabase.instance.setPersistenceEnabled(true);
    } catch (e) {
      print("DEBUG: Persistence Error: $e");
    }

    final prefs = await SharedPreferences.getInstance();
    isDeveloperMode = prefs.getBool('dev_mode') ?? false;

    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: null,
    );
    
    _glovePluginPermission();
    _startGloveStream();
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
      
      onStateChanged?.call();
    });
  }

  void _startHeartbeatWatchdog() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _updateConnectionStatus();
    });
  }

  void _updateConnectionStatus() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final bool currentlyConnected = (now - lastHeartbeat) < 12000;
    
    if (isGloveConnected != currentlyConnected) {
      isGloveConnected = currentlyConnected;
      onStateChanged?.call();
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
    onStateChanged?.call();

    try {
      _showNotification(title: "SOS EMERGENCY", body: "Patient triggered SOS from $source!", isHighPriority: true);
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('alert.mp3'));
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
    onStateChanged?.call();
    
    await _audioPlayer.stop();
    Vibration.cancel();
    
    if (!isDeveloperMode) {
       _gloveRef.update({'active_gesture': 'None'});
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
    _heartbeatTimer?.cancel();
    _audioPlayer.dispose();
  }
}
