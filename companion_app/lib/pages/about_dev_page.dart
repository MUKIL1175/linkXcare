import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_state_manager.dart';

class AboutDevPage extends StatefulWidget {
  const AboutDevPage({super.key});
  @override
  State<AboutDevPage> createState() => _AboutDevPageState();
}

class _AboutDevPageState extends State<AboutDevPage> {
  final state = AppStateManager();
  bool _showDevOptions = false;

  void _handleDevModeToggle(bool value) {
    if (value) _promptPasscode();
    else _disableDevMode();
  }

  void _promptPasscode() {
    final TextEditingController pinController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Enter Developer Passcode"),
        content: TextField(controller: pinController, keyboardType: TextInputType.number, obscureText: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(onPressed: () {
            if (pinController.text == "1711") {
              _enableDevMode();
              Navigator.pop(context);
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

  Future<void> _launchUpdateUrl() async {
    final Uri url = Uri.parse('https://github.com/MUKIL1175/linkXcare/raw/main/app-release.apk');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not launch update URL")),
        );
      }
    }
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
            const Text("LinkXcare v2.1", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), // Updated version
            const SizedBox(height: 8),
            Text(
              state.isDeveloperMode
                  ? "Designer & Developer: Monamukil SS"
                  : "Designer & Developer: Nisha Priyadharshini J",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 24),
            
            // Premium Update Button
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF2979FF), Color(0xFF1565C0)]),
                borderRadius: BorderRadius.circular(15),
                boxShadow: [BoxShadow(color: const Color(0xFF2979FF).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: ElevatedButton.icon(
                onPressed: _launchUpdateUrl,
                icon: const Icon(Icons.system_update_alt_rounded, color: Colors.white),
                label: const Text("GET LATEST UPDATE", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangle_border_radius_circular_15(),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            const Divider(),
            SwitchListTile(
              title: const Text("Developer Mode"),
              value: state.isDeveloperMode,
              onChanged: _handleDevModeToggle,
            ),
            if (_showDevOptions) _buildDevModePanel(),
          ],
        ),
      ),
    );
  }

  // Helper for cleaner style
  RoundedRectangleBorder RoundedRectangle_border_radius_circular_15() => RoundedRectangleBorder(borderRadius: BorderRadius.circular(15));

  Widget _buildDevModePanel() {
    return Container(
      padding: const EdgeInsets.all(15),
      margin: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF2979FF), width: 2),
      ),
      child: Column(
        children: [
          const Text("🛠️ DEVELOPER TOOLS", style: TextStyle(color: Color(0xFF2979FF), fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2979FF), foregroundColor: Colors.white),
            onPressed: () => state.triggerSOS(source: "Manual Test"),
            child: const Text("TEST SOS UNIT"),
          ),
          const Divider(color: Colors.white24, height: 30),
          const Text("MANUAL FINGER TESTING", style: TextStyle(color: Colors.white70, fontSize: 12)),
          ...List.generate(5, (index) => Slider(
            value: state.fsrValues[index].toDouble(),
            activeColor: const Color(0xFF2979FF),
            inactiveColor: Colors.white10,
            min: 0,
            max: 100,
            onChanged: (val) {
              setState(() => state.fsrValues[index] = val.toInt());
              FirebaseDatabase.instance.ref('realtime/glove_01/fsr').child(index.toString()).set(val.toInt());
            },
            onChangeEnd: (val) => _simulateGestureRecognition(),
          )),
        ],
      ),
    );
  }

  Future<void> _simulateGestureRecognition() async {
    final fsr = state.fsrValues;
    final ticks = fsr.map((v) => v > 75 ? 1 : 0).toList();
    
    try {
      final defaultSnap = await FirebaseDatabase.instance.ref('default_gestures').get();
      final customSnap = await FirebaseDatabase.instance.ref('custom_gestures').get();
      
      String matchedMsg = "None";
      
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
      
      if (matchedMsg == "None" && defaultSnap.value is Map) {
         final defMap = defaultSnap.value as Map;
         if (_listEquals(ticks, [1,1,1,1,1])) matchedMsg = defMap['closed_fingers'] ?? "Emergency";
         else if (_listEquals(ticks, [1,0,0,0,0])) matchedMsg = defMap['thumb_finger'] ?? "Need water";
         else if (_listEquals(ticks, [0,1,0,0,0])) matchedMsg = defMap['index_finger'] ?? "Restroom";
         else if (_listEquals(ticks, [0,0,1,0,0])) matchedMsg = defMap['middle_finger'] ?? "Need food";
         else if (_listEquals(ticks, [0,0,0,1,0])) matchedMsg = defMap['ring_finger'] ?? "Need medicines";
         else if (_listEquals(ticks, [0,0,0,0,1])) matchedMsg = defMap['pinky_finger'] ?? "restroom";
      }
      
      FirebaseDatabase.instance.ref('realtime/glove_01/active_gesture').set(matchedMsg);
    } catch (e) {
      print("DEBUG: Simulate Error: $e");
    }
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) if (a[i] != b[i]) return false;
    return true;
  }
}
