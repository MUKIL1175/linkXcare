import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

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
              final date = (rawTime is int) ? DateTime.fromMillisecondsSinceEpoch(rawTime) : DateTime.now();
              final timeStr = DateFormat('h:mma').format(date).toLowerCase();
              final dateStr = DateFormat('dd-MMMM-yyyy').format(date);
              final displayStr = (log['timestamp'] is String && log['time'] == null) ? log['timestamp'] : "$dateStr [$timeStr]";
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
