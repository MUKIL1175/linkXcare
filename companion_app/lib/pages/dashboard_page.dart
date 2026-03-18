import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../core/app_state_manager.dart';

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
                                                : [const Color(0xFF475569), const Color(0xFF334155)], 
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
