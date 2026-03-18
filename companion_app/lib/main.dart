import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:ui' as ui;
import 'core/app_state_manager.dart';
import 'theme/anti_gravity_theme.dart';
import 'pages/dashboard_page.dart';
import 'pages/default_gestures_page.dart';
import 'pages/custom_gestures_page.dart';
import 'pages/history_page.dart';
import 'pages/about_dev_page.dart';

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
      theme: AntiGravityTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}

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
    state.initialize(); // Init state

    await Future.delayed(const Duration(milliseconds: 3000));
    
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
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFF2979FF).withOpacity(0.5), blurRadius: 40, spreadRadius: 10)]),
                child: const Icon(Icons.accessibility_new, size: 100, color: Colors.white),
              ),
              const SizedBox(height: 32),
              const Text("LinkXcare", style: TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold, letterSpacing: 3)),
              const SizedBox(height: 60),
              const CircularProgressIndicator(color: Color(0xFF2979FF)),
            ],
          ),
        ),
      ),
    );
  }
}

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
    state.onStateChanged = () { if (mounted) setState(() {}); };
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          body: _pages[_selectedIndex],
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _selectedIndex,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: const Color(0xFF2979FF),
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
        if (state.isSosActive) _buildSosOverlay(),
      ],
    );
  }

  Widget _buildSosOverlay() {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
            child: Container(color: const Color(0xFFD50000).withOpacity(0.85)),
          ),
          Center(
            child: Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white.withOpacity(0.4))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 80),
                  const Text("SOS EMERGENCY", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 30),
                  ElevatedButton(onPressed: () => state.stopSOS(), child: const Text("TREATED")),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
