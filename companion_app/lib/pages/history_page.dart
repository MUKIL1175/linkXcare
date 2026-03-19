import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Gesture History"),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.code), text: "Developer"),
              Tab(icon: Icon(Icons.history), text: "Real Time"),
            ],
            indicatorColor: Color(0xFF2979FF),
            labelColor: Color(0xFF2979FF),
            unselectedLabelColor: Colors.white70,
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F172A), Color(0xFF1A237E)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: const TabBarView(
            children: [
              HistoryList(path: 'logs/dev_history/glove_01'),
              HistoryList(path: 'logs/real_history/glove_01'),
            ],
          ),
        ),
      ),
    );
  }
}

class HistoryList extends StatelessWidget {
  final String path;
  const HistoryList({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref(path).orderByChild('time').limitToLast(50);

    return StreamBuilder(
      stream: ref.onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history_toggle_off, size: 64, color: Colors.white24),
                SizedBox(height: 16),
                Text("No logs yet.", style: TextStyle(color: Colors.white54, fontSize: 16)),
              ],
            ),
          );
        }

        final Map data = snapshot.data!.snapshot.value as Map;
        final logs = data.values.toList().whereType<Map>().toList();
        logs.sort((a, b) {
          final aTime = a['time'] ?? 0;
          final bTime = b['time'] ?? 0;
          return bTime.compareTo(aTime);
        });

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index];
            final rawTime = log['time'];
            final date = (rawTime is int) ? DateTime.fromMillisecondsSinceEpoch(rawTime) : DateTime.now();
            final timeStr = DateFormat('h:mma').format(date).toLowerCase();
            final dateStr = DateFormat('dd-MMMM-yyyy').format(date);
            final displayStr = (log['timestamp'] is String && log['time'] == null) ? log['timestamp'] : "$dateStr [$timeStr]";
            final isSos = log['msg'] == "EMERGENCY" || log['msg'] == "Emergency";
            final source = log['source'] ?? "Unknown";

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSos ? const Color(0xFFD50000).withOpacity(0.2) : Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
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
                      title: Row(
                        children: [
                          Expanded(child: Text(log['msg'], style: TextStyle(fontWeight: FontWeight.bold, color: isSos ? const Color(0xFFD50000) : Colors.white, fontSize: 16))),
                          if (source != "Unknown")
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(source, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                            ),
                        ],
                      ),
                      subtitle: Text(displayStr, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
