// main.dart / lib/core/linkxcare_app.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:ui' as ui;

// --- GLOBAL VARIABLES & STATE (The Bridge) ---
// This class manages the connection, SOS logic, and app state to prevent leaks.
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
  Function()? onStateChanged; // UI callback

  Future<void> initialize() async {
    print("DEBUG: Initializing State...");
    FirebaseDatabase.instance.setLoggingEnabled(true);
    // 1. Enable Persistence (Critical for emulator sync issues)
    try {
      FirebaseDatabase.instance.setPersistenceEnabled(true);
      // persistenceEnabled handles local caching. 
      // keepSynced can sometimes cause delays in emitting local data if the server is unreachable.
      // We'll rely on active listeners to trigger sync.
    } catch (e) {
      print("DEBUG: Persistence Error: $e");
    }

    final prefs = await SharedPreferences.getInstance();
    isDeveloperMode = prefs.getBool('dev_mode') ?? false;

    // Initialize Local Notifications
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: null,
    );
    
    _glovePluginPermission();
    
    // 2. Start Glove Stream
    _startGloveStream();

    // 3. Start Heartbeat Watchdog
    _startHeartbeatWatchdog();

    // 4. Seed Defaults with Timeout
    try {
      await seedDefaultsIfEmpty().timeout(const Duration(seconds: 4));
      print("DEBUG: Seed Defaults operation finished.");
    } catch (e) {
      print("DEBUG: Seed Defaults Timeout/Error: $e (Continuing...)");
    }
  }

  void _startGloveStream() {
    print("DEBUG: _startGloveStream listener started.");
    _gloveSubscription?.cancel(); // Safety check
    _gloveSubscription = _gloveRef.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data == null) return;
      
      final newGesture = data['active_gesture'] ?? "None";
      fsrValues = List<int>.from(data['fsr'] ?? [0, 0, 0, 0, 0]);
      lastHeartbeat = data['heartbeat'] ?? 0;
      
      // Connection logic: If we just got data, it's likely connected
      _updateConnectionStatus();
      
      if (currentGesture != newGesture && newGesture != "None") {
        _showNotification(title: "Live Gesture Detected", body: "Message: $newGesture");
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

  // --- SEEDING LOGIC ---
  Future<void> seedDefaultsIfEmpty() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('did_seed_v3') ?? false) return;

    print("DEBUG: Seeding Defaults (New Method)...");
    final ref = FirebaseDatabase.instance.ref('default_gestures');
    
    // We try to set it. With persistence enabled, this works locally immediately.
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
      print("DEBUG: Finished Seeding Defaults.");
    } catch (e) {
      // Even if it timeouts, persistence will keep the 'set' operation in queue
      // But we mark it as seeded so we don't spam the queue every restart
      await prefs.setBool('did_seed_v3', true);
      print("DEBUG: Seed Error: $e");
    }
  }

  Future<void> triggerSOS({required String source}) async {
    print("DEBUG: triggerSOS called from source: $source");
    if (isSosActive) {
      print("DEBUG: SOS already active, ignoring.");
      return; 
    }
    isSosActive = true;
    print("DEBUG: isSosActive set to true. Notifying listeners.");
    onStateChanged?.call();

    try {
      _showNotification(title: "SOS EMERGENCY", body: "Patient triggered SOS from $source!", isHighPriority: true);
      
      // Loop the alert.mp3 correctly for v6.0.0
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(AssetSource('alert.mp3'));
      print("DEBUG: Alert audio started.");
      
      // Add Vibrate for caregiver awareness
      if (await Vibration.hasVibrator() == true) {
        Vibration.vibrate(pattern: [500, 1000, 500, 1000], repeat: 0);
        print("DEBUG: Vibration started.");
      }
    } catch (e) {
      print("DEBUG: SOS Error: $e");
    }
  }

  Future<void> stopSOS() async {
    print("DEBUG: stopSOS called.");
    if (!isSosActive) return;
    isSosActive = false;
    print("DEBUG: isSosActive set to false. Notifying listeners.");
    onStateChanged?.call();
    
    await _audioPlayer.stop();
    Vibration.cancel();
    print("DEBUG: SOS Stopped.");
    
    // Reset state in Firebase so the ESP knows it was handled
    if (!isDeveloperMode) {
       _gloveRef.update({'active_gesture': 'None'});
    }
  }

  void dispose() {
    _gloveSubscription?.cancel();
    _heartbeatTimer?.cancel();
    _audioPlayer.dispose();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const LinkXcareApp());
}

class LinkXcareApp extends StatelessWidget {
  const LinkXcareApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LinkXcare Caregiver',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF2979FF),
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Deep Slate/Indigo
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1E293B),
          selectedItemColor: Color(0xFF2979FF),
          unselectedItemColor: Colors.white54,
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}

// --- INTRO / SPLASH SCREEN ---
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    _controller.forward();
    _startApp();
  }

  Future<void> _startApp() async {
    final state = AppStateManager();
    print("DEBUG: Starting App...");
    
    // 1. Play Intro Sound
    state._audioPlayer.play(AssetSource('intro.mp3'), mode: PlayerMode.lowLatency).catchError((e) => print("Sound Error: $e"));
    
    // 2. Initialize State with Timeout
    try {
      print("DEBUG: Initializing State...");
      await state.initialize().timeout(const Duration(seconds: 4));
      print("DEBUG: Seeding Defaults...");
      await state.seedDefaultsIfEmpty().timeout(const Duration(seconds: 4));
    } catch (e) {
      print("DEBUG: Init/Seed Warning or Timeout: $e");
    }

    // 3. Ensure minimum splash time
    await Future.delayed(const Duration(milliseconds: 2000));
    
    print("DEBUG: Navigating to Main Screen...");
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainNavigationScreen())
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF2979FF).withOpacity(0.5), blurRadius: 40, spreadRadius: 10),
                  ],
                ),
                child: const Icon(Icons.accessibility_new, size: 100, color: Colors.white),
              ),
              const SizedBox(height: 32),
              const Text(
                "LinkXcare",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Companion App",
                style: TextStyle(
                  color: Color(0xFF2979FF),
                  fontSize: 18,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 60),
              const CircularProgressIndicator(color: Color(0xFF2979FF)),
            ],
          ),
        ),
      ),
    );
  }
}

// --- MAIN UI (Zero-Bug) ---

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});
  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;
  final state = AppStateManager();

  final List<Widget> _pages = [
    const DashboardPage(),
    const DefaultGesturesPage(),
    const CustomGesturesPage(),
    const HistoryPage(),
    const AboutDevPage(),
  ];

  @override
  void initState() {
    super.initState();
    // Bind UI rebuild to state manager changes
    state.onStateChanged = () {
      if (mounted) setState(() {});
    };
  }

  @override
  Widget build(BuildContext context) {
    // Zero-Bug: This Stack keeps the SOS OVERLAY always on top.
    return Stack(
      children: [
        Scaffold(
          body: _pages[_selectedIndex],
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: Colors.indigo,
            unselectedItemColor: Colors.grey,
            onTap: (index) => setState(() => _selectedIndex = index),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Status'),
              BottomNavigationBarItem(icon: Icon(Icons.fingerprint), label: 'Default'),
              BottomNavigationBarItem(icon: Icon(Icons.gesture_outlined), label: 'Custom'),
              BottomNavigationBarItem(icon: Icon(Icons.history_outlined), label: 'History'),
              BottomNavigationBarItem(icon: Icon(Icons.info_outline), label: 'About'),
            ],
          ),
        ),
        
        // --- SOS FULLSCREEN OVERLAY (Zero-Bug) ---
        if (state.isSosActive) _buildSosOverlay(),
      ],
    );
  }

  Widget _buildSosOverlay() {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Glassmorphism Blur
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
            child: Container(
              color: const Color(0xFFD50000).withOpacity(0.85),
            ),
          ),
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.1),
              duration: const Duration(seconds: 1),
              curve: Curves.elasticOut,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 50),
                    margin: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.20),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFFD50000).withOpacity(0.6), blurRadius: 40, spreadRadius: 10)
                      ]
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 100),
                        const SizedBox(height: 20),
                        const Text("SOS EMERGENCY", 
                          style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 2)
                        ),
                        const SizedBox(height: 15),
                        const Text("Glove user requires immediate attention!", 
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500)
                        ),
                        const SizedBox(height: 50),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white, 
                            foregroundColor: const Color(0xFFD50000), 
                            elevation: 10, 
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                          ),
                          onPressed: () => state.stopSOS(),
                          child: const Text("PATIENT IS TREATED", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        )
                      ],
                    ),
                  ),
                );
              }
            ),
          ),
        ],
      ),
    );
  }
}

// --- SUB PAGES ---

// 1. Dashboard
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppStateManager();
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Glove Monitor"), 
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1A237E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Glassmorphic Status Card
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                            children: [
                              const Text("Live Gesture", style: TextStyle(fontSize: 16, color: Colors.white70)), 
                              Text(
                                (!state.isGloveConnected && !state.isDeveloperMode) ? "Offline" : state.currentGesture, 
                                key: ValueKey<String>(state.currentGesture),
                                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: (!state.isGloveConnected && !state.isDeveloperMode) ? Colors.white24 : const Color(0xFF2979FF))
                              )
                            ]
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                            children: [
                              const Text("System Status", style: TextStyle(fontSize: 16, color: Colors.white70)), 
                              Row(
                                children: [
                                  Container(
                                    width: 12, height: 12, 
                                    decoration: BoxDecoration(
                                      color: (state.isGloveConnected || state.isDeveloperMode) ? Colors.greenAccent : Colors.white24, 
                                      shape: BoxShape.circle, 
                                      boxShadow: (state.isGloveConnected || state.isDeveloperMode) 
                                        ? [BoxShadow(color: Colors.greenAccent.withOpacity(0.5), blurRadius: 8)]
                                        : []
                                    )
                                  ), 
                                  const SizedBox(width: 8), 
                                  Text(
                                    (state.isGloveConnected || state.isDeveloperMode) ? "Online" : "Offline", 
                                    style: TextStyle(
                                      color: (state.isGloveConnected || state.isDeveloperMode) ? Colors.greenAccent : Colors.white24, 
                                      fontWeight: FontWeight.bold
                                    )
                                  )
                                ]
                              )
                            ]
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (!state.isGloveConnected && !state.isDeveloperMode)
                  _buildConnectionWarning(),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text("Real-Time Telemetry", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.2)),
                ),
                const SizedBox(height: 15),
                // Liquid Finger Monitor
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                    child: Container(
                      height: 280,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 25),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05), 
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(5, (index) {
                          double fillPercent = state.fsrValues[index] / 100.0;
                          return Column(
                            children: [
                              Text("${state.fsrValues[index]}%", style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),
                              Expanded(
                                child: Container(
                                  width: 24, 
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.2), 
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5)]
                                  ), 
                                  child: Stack(
                                    alignment: Alignment.bottomCenter,
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeOutExpo,
                                        height: 200 * fillPercent, 
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: (state.isGloveConnected || state.isDeveloperMode)
                                                ? [const Color(0xFF00E5FF), const Color(0xFF2979FF)]
                                                : [const Color(0xFF475569), const Color(0xFF334155)], // Graphite colors for offline
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: (state.isGloveConnected || state.isDeveloperMode)
                                              ? [BoxShadow(color: const Color(0xFF2979FF).withOpacity(0.6), blurRadius: 10)]
                                              : []
                                        )
                                      ),
                                    ],
                                  )
                                )
                              ), 
                              const SizedBox(height: 15), 
                              Text(["Thumb", "Index", "Middle", "Ring", "Pinky"][index], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))
                            ]
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionWarning() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFD50000).withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD50000).withOpacity(0.5)),
      ),
      child: const Row(
        children: [
          Icon(Icons.wifi_off_rounded, color: Color(0xFFFF5252), size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              "Glove Not Connected. Showing last known state.",
              style: TextStyle(color: Color(0xFFFF8A80), fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// 2. Default Gestures Page (Now Editable)
class DefaultGesturesPage extends StatefulWidget {
  const DefaultGesturesPage({super.key});
  @override
  State<DefaultGesturesPage> createState() => _DefaultGesturesPageState();
}

class _DefaultGesturesPageState extends State<DefaultGesturesPage> {
  final _ref = FirebaseDatabase.instance.ref('default_gestures');
  Map<String, dynamic> _gestures = {};
  bool _isLoading = true;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    print("DEBUG: DefaultGestures _loadInitialData started");
    try {
      final snapshot = await _ref.get().timeout(const Duration(seconds: 2));
      print("DEBUG: DefaultGestures Initial GET Success: ${snapshot.exists}");
      if (mounted) {
        setState(() {
          if (snapshot.value is Map) {
            _gestures = Map<String, dynamic>.from(snapshot.value as Map);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      print("DEBUG: DefaultGestures Initial GET Timeout/Error: $e");
    }

    _subscription = _ref.onValue.listen((event) {
      final data = event.snapshot.value;
      print("DEBUG: DEFAULT_GESTURES_LISTENER: data=$data");
      if (mounted) {
        setState(() {
          if (data is Map) {
            _gestures = Map<String, dynamic>.from(data);
          }
          _isLoading = false;
        });
      }
    }, onError: (e) {
      print("DEBUG: DEFAULT_GESTURES_ERROR: $e");
      if (mounted) setState(() => _isLoading = false);
    });

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _isLoading) {
        print("DEBUG: DefaultGestures Timeout - Forcing Loader Off");
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _editAction(String key, String currentAction) {
    if (key == "Closed" && !AppStateManager().isDeveloperMode) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Developer Mode Required to edit Closed Fingers!")));
      return;
    }

    final TextEditingController controller = TextEditingController(text: currentAction);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Edit $key Action"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "Action Title"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                // Offline-First: Persistence handles sync, close immediately
                _ref.child(key).set(controller.text);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Action updated (syncing in background)")));
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _gestures.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));

    return Scaffold(
      appBar: AppBar(title: const Text("Default Gestures")),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : entries.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("No data found or still syncing..."),
                  const SizedBox(height: 10),
                  ElevatedButton(onPressed: () => setState(() {}), child: const Text("Retry"))
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(15),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final String finger = entry.key;
                final String action = entry.value.toString();

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: finger == "Closed" ? Colors.red[100] : Colors.indigo[100],
                      child: Icon(finger == "Closed" ? Icons.front_hand : Icons.fingerprint, 
                        color: finger == "Closed" ? Colors.red : Colors.indigo),
                    ),
                    title: Text(finger, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("Action: $action"),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _editAction(finger, action),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// 3. Custom Gestures Page (List + Create + Edit)
class CustomGesturesPage extends StatefulWidget {
  const CustomGesturesPage({super.key});
  @override
  State<CustomGesturesPage> createState() => _CustomGesturesPageState();
}

class _CustomGesturesPageState extends State<CustomGesturesPage> {
  late DatabaseReference _ref;
  Map<String, dynamic> _gestures = {};
  bool _isLoading = true;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    // Initialize ref here to ensure Firebase persistence is already set up
    _ref = FirebaseDatabase.instance.ref('custom_gestures');
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    print("DEBUG: _loadInitialData started");
    try {
      // 1. Try to get cached/online data with timeout
      final snapshot = await _ref.get().timeout(const Duration(seconds: 2));
      print("DEBUG: Initial GET Success: ${snapshot.exists}");
      if (mounted) {
        setState(() {
          if (snapshot.value is Map) {
            _gestures = Map<String, dynamic>.from(snapshot.value as Map);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      print("DEBUG: Initial GET Timeout/Error: $e");
    }

    // 2. Start persistent listener for updates
    _subscription = _ref.onValue.listen((event) {
      final data = event.snapshot.value;
      print("DEBUG: CUSTOM_GESTURES_LISTENER: data=$data");
      if (mounted) {
        setState(() {
          if (data is Map) {
            _gestures = Map<String, dynamic>.from(data);
          } else {
            _gestures = {};
          }
          _isLoading = false;
        });
      }
    }, onError: (error) {
      print("DEBUG: CUSTOM_GESTURES_ERROR: $error");
      if (mounted) setState(() => _isLoading = false);
    });

    // 3. Safety timeout: If still loading after 5s, turn off loader
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _isLoading) {
        print("DEBUG: CustomGestures Timeout - Forcing Loader Off");
        setState(() => _isLoading = false);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _showGestureDialog({String? key, String? initialMsg, List<int>? initialTicks}) {
    final TextEditingController msgController = TextEditingController(text: initialMsg);
    final List<bool> fingerStates = initialTicks != null
        ? initialTicks.map((t) => t == 1).toList()
        : [false, false, false, false, false];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(key == null ? "Create New Gesture" : "Edit Gesture"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: msgController,
                  decoration: const InputDecoration(labelText: "Meaning", hintText: "e.g. I am Cold"),
                ),
                const SizedBox(height: 20),
                const Text("Finger States (Checked = Bent)", style: TextStyle(fontWeight: FontWeight.bold)),
                ...List.generate(5, (index) => CheckboxListTile(
                  title: Text(["Thumb", "Index", "Middle", "Ring", "Pinky"][index]),
                  value: fingerStates[index],
                  onChanged: (v) => setDialogState(() => fingerStates[index] = v!),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                if (msgController.text.isEmpty) return;
                final data = {
                  'message': msgController.text,
                  'tickBoxes': fingerStates.map((b) => b ? 1 : 0).toList(),
                  'timestamp': ServerValue.timestamp,
                };
                print("DEBUG: Saving Gesture: $data");
                
                final String nodeKey = key ?? _ref.push().key!;
                
                // Optimistic UI update (shows instantly even if Firebase listener hangs)
                setState(() {
                  _gestures[nodeKey] = {
                    'message': msgController.text,
                    'tickBoxes': fingerStates.map((b) => b ? 1 : 0).toList(),
                    'timestamp': DateTime.now().millisecondsSinceEpoch, // Local time sorting
                  };
                  _isLoading = false;
                });

                if (key == null) {
                  _ref.child(nodeKey).set(data).then((_) => print("DEBUG: Save Success"));
                } else {
                  _ref.child(nodeKey).update(data).then((_) => print("DEBUG: Update Success"));
                }
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gesture saved locally (syncing...)")));
              },
              child: Text(key == null ? "Save" : "Update"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGestureCard(String key, Map<dynamic, dynamic> gestureData) {
    final msg = gestureData['message'] ?? 'Unknown';
    final ticks = List<int>.from(gestureData['tickBoxes'] ?? [0,0,0,0,0]);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: const CircleAvatar(backgroundColor: Colors.indigo, child: Icon(Icons.gesture, color: Colors.white, size: 20)),
        title: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("State: ${ticks.join(', ')}"),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: () => _showGestureDialog(
                key: key,
                initialMsg: msg,
                initialTicks: ticks,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                setState(() {
                  _gestures.remove(key);
                });
                _ref.child(key).remove();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gesture deleted locally")));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    int getTs(dynamic val) {
      if (val is Map && val.containsKey('timestamp')) {
        final ts = val['timestamp'];
        if (ts is int) return ts;
        if (ts is Map) return DateTime.now().millisecondsSinceEpoch; // Local placeholder
      }
      return 0;
    }

    final sortedEntries = _gestures.entries.toList()
      ..sort((a, b) {
        final aTs = getTs(a.value);
        final bTs = getTs(b.value);
        return bTs.compareTo(aTs);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text("Custom Gestures"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _loadInitialData();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showGestureDialog(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : sortedEntries.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.gesture, size: 80, color: Colors.grey[200]),
                  const SizedBox(height: 20),
                  const Text("No custom gestures yet", style: TextStyle(fontSize: 18, color: Colors.grey)),
                  const SizedBox(height: 10),
                  const Text("Tap '+' to create your first gesture", style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(top: 10, bottom: 80),
              itemCount: sortedEntries.length,
              itemBuilder: (context, index) {
                final entry = sortedEntries[index];
                return _buildGestureCard(entry.key, entry.value as Map);
              },
            ),
    );
  }
}

// 4. History
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});
  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref('logs/glove_01').orderByChild('time').limitToLast(50);
    
    return Scaffold(
      appBar: AppBar(title: const Text("Gesture History")),
      body: StreamBuilder(
        stream: ref.onValue,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) return const Center(child: Text("No logs yet."));
          
          final Map data = snapshot.data!.snapshot.value as Map;
          
          final logs = data.values.toList().whereType<Map>().toList();
          logs.sort((a,b) {
            final aTime = a['time'] ?? 0;
            final bTime = b['time'] ?? 0;
            if (aTime is int && bTime is int) return bTime.compareTo(aTime);
            return 0; 
          });
          
          return ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              final rawTime = log['time'];
              final date = (rawTime is int) 
                  ? DateTime.fromMillisecondsSinceEpoch(rawTime)
                  : DateTime.now();

              final timeStr = DateFormat('h:mma').format(date).toLowerCase();
              final dateStr = DateFormat('dd-MMMM-yyyy').format(date);
              
              // Use existing timestamp string if 'time' is missing
              final displayStr = (log['timestamp'] is String && log['time'] == null)
                  ? log['timestamp']
                  : "$dateStr [$timeStr]";
              
              final isSos = log['msg'] == "EMERGENCY" || log['msg'] == "Emergency";
              
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSos ? const Color(0xFFD50000).withOpacity(0.2) : Colors.white.withOpacity(0.1),
                        border: Border.all(color: isSos ? const Color(0xFFD50000).withOpacity(0.5) : Colors.white.withOpacity(0.2)),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSos ? const Color(0xFFD50000).withOpacity(0.3) : const Color(0xFF2979FF).withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(isSos ? Icons.warning_amber_rounded : Icons.gesture, color: isSos ? const Color(0xFFD50000) : const Color(0xFF2979FF)),
                        ),
                        title: Text(log['msg'], style: TextStyle(fontWeight: FontWeight.bold, color: isSos ? const Color(0xFFD50000) : Colors.white, fontSize: 16)),
                        subtitle: Text(displayStr, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// 5. About & Secured Developer Mode
class AboutDevPage extends StatefulWidget {
  const AboutDevPage({super.key});
  @override
  State<AboutDevPage> createState() => _AboutDevPageState();
}

class _AboutDevPageState extends State<AboutDevPage> {
  final state = AppStateManager();
  bool _showDevOptions = false;

  void _handleDevModeToggle(bool value) {
    if (value) {
      _promptPasscode();
    } else {
      _disableDevMode();
    }
  }

  void _promptPasscode() {
    final TextEditingController pinController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Enter Developer Passcode"),
        content: TextField(controller: pinController, keyboardType: TextInputType.number, obscureText: true, decoration: const InputDecoration(hintText: "1711")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(onPressed: () {
            if (pinController.text == "1711") {
              _enableDevMode();
              Navigator.pop(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Incorrect Passcode!")));
            }
          }, child: const Text("Access")),
        ],
      ),
    );
  }

  void _enableDevMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_mode', true);
    setState(() {
      state.isDeveloperMode = true;
      _showDevOptions = true;
    });
  }

  void _disableDevMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dev_mode', false);
    setState(() {
      state.isDeveloperMode = false;
      _showDevOptions = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _showDevOptions = state.isDeveloperMode;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("About LinkXcare")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.accessibility_new, size: 80, color: Colors.indigo),
            const SizedBox(height: 10),
            const Text("LinkXcare v2.0", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const Text("Developed by: Nisha Priyadharshini J"),
            const SizedBox(height: 30),
            const Divider(),
            SwitchListTile(
              title: const Text("Developer Mode"),
              subtitle: const Text("Enable SOS Testing & Manual Controls"),
              value: state.isDeveloperMode,
              onChanged: _handleDevModeToggle,
            ),
            
            if (_showDevOptions) _buildDevModePanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildDevModePanel() {
    return Container(
      padding: const EdgeInsets.all(15),
      margin: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.amber)),
      child: Column(
        children: [
          Text("🛠️ DEVELOPER TOOLS 🛠️", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber[900])),
          const SizedBox(height: 15),
          ElevatedButton.icon(onPressed: () => state.triggerSOS(source: "Manual Test"), icon: const Icon(Icons.vibration), label: const Text("Test SOS (Manual Alert)"), style: ElevatedButton.styleFrom(backgroundColor: Colors.red[100], foregroundColor: Colors.red[900])),
          const SizedBox(height: 10),
          ElevatedButton.icon(onPressed: _autoCalibrateCommand, icon: const Icon(Icons.settings_backup_restore), label: const Text("Trigger Remote Auto-Calibration")),
          const Divider(height: 30),
          Text("MANUAL FINGER TESTING (Live)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
          ...List.generate(5, (index) => Column(
            children: [
              Row(
                children: [
                  SizedBox(width: 60, child: Text(["Thumb", "Index", "Middle", "Ring", "Pinky"][index], style: const TextStyle(fontSize: 12))),
                  Expanded(
                    child: Slider(
                      value: state.fsrValues[index].toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 100,
                      label: "${state.fsrValues[index]}%",
                      onChanged: (val) {
                        setState(() {
                          state.fsrValues[index] = val.toInt();
                        });
                        // Update Firebase immediately
                        FirebaseDatabase.instance.ref('realtime/glove_01/fsr').child(index.toString()).set(val.toInt());
                      },
                      onChangeEnd: (val) {
                         _simulateGestureRecognition();
                      },
                    ),
                  ),
                  Text("${state.fsrValues[index]}%", style: const TextStyle(fontSize: 12)),
                ],
              ),
            ],
          )),
        ],
      ),
    );
  }

  void _autoCalibrateCommand() {
     // Zero-Bug: This sends a special command that the ESP32 code listens for in its main loop.
     FirebaseDatabase.instance.ref('devices/glove_01/config').update({
       'command': 'calibrate',
       'timestamp': ServerValue.timestamp
     });
     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Auto-Calibration Command Sent!")));
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _simulateGestureRecognition() async {
    final state = AppStateManager();
    final fsr = state.fsrValues;
    final ticks = fsr.map((v) => v > 75 ? 1 : 0).toList();
    
    try {
      final defaultSnap = await FirebaseDatabase.instance.ref('default_gestures').get();
      final customSnap = await FirebaseDatabase.instance.ref('custom_gestures').get();
      
      String matchedMsg = "None";
      
      // Check Custom Gestures
      if (customSnap.value is Map) {
        final customMap = customSnap.value as Map;
        for (var entry in customMap.entries) {
           final g = entry.value as Map;
           final gTicks = List<int>.from(g['tickBoxes'] ?? [0,0,0,0,0]);
           if (_listEquals(ticks, gTicks)) {
              matchedMsg = g['message'] ?? "Unknown Custom";
              break;
           }
        }
      }
      
      // Check Default Gestures
      if (matchedMsg == "None" && defaultSnap.value is Map) {
         final defMap = defaultSnap.value as Map;
         if (_listEquals(ticks, [1,1,1,1,1])) matchedMsg = defMap['closed_fingers'] ?? "Emergency";
         else if (_listEquals(ticks, [1,0,0,0,0])) matchedMsg = defMap['thumb_finger'] ?? "Need water";
         else if (_listEquals(ticks, [0,1,0,0,0])) matchedMsg = defMap['index_finger'] ?? "Restroom";
         else if (_listEquals(ticks, [0,0,1,0,0])) matchedMsg = defMap['middle_finger'] ?? "Need food";
         else if (_listEquals(ticks, [0,0,0,1,0])) matchedMsg = defMap['ring_finger'] ?? "Need medicines";
         else if (_listEquals(ticks, [0,0,0,0,1])) matchedMsg = defMap['pinky_finger'] ?? "restroom";
      }
      
      print("DEBUG: Simulated matched gesture: $matchedMsg");
      FirebaseDatabase.instance.ref('realtime/glove_01/active_gesture').set(matchedMsg);
    } catch (e) {
      print("DEBUG: Simulate Recognition Error: $e");
    }
  }
}
