import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<void> _launchUpdateUrl(BuildContext context) async {
    final Uri url = Uri.parse('https://raw.githubusercontent.com/MUKIL1175/linkXcare/main/app-release.apk');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
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
            const SizedBox(height: 20),
            const Icon(Icons.accessibility_new, size: 80, color: Color(0xFF2979FF)),
            const SizedBox(height: 16),
            const Text("LinkXcare version:X", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            const Text(
              "Designer & Developer: Nisha Priyadharshini J",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white70),
            ),
            const SizedBox(height: 40),
            
            // Premium Update Button
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF2979FF), Color(0xFF1565C0)]),
                borderRadius: BorderRadius.circular(15),
                boxShadow: [BoxShadow(color: const Color(0xFF2979FF).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: ElevatedButton.icon(
                onPressed: () => _launchUpdateUrl(context),
                icon: const Icon(Icons.system_update_alt_rounded, color: Colors.white),
                label: const Text("GET LATEST UPDATE", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
              ),
            ),
            
            const SizedBox(height: 40),
            const Divider(color: Colors.white24),
            const SizedBox(height: 20),
            const Text(
              "Empowering communication through assistive technology.",
              textAlign: TextAlign.center,
              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}
