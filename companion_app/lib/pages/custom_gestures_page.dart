import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

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
    _ref = FirebaseDatabase.instance.ref('custom_gestures');
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final snapshot = await _ref.get().timeout(const Duration(seconds: 2));
      if (mounted) {
        setState(() {
          if (snapshot.value is Map) {
            _gestures = Map<String, dynamic>.from(snapshot.value as Map);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      print("DEBUG: CustomGestures Error: $e");
    }

    _subscription = _ref.onValue.listen((event) {
      final data = event.snapshot.value;
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
    });

    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _isLoading) setState(() => _isLoading = false);
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
                
                final String nodeKey = key ?? _ref.push().key!;
                
                if (key == null) {
                  _ref.child(nodeKey).set(data);
                } else {
                  _ref.child(nodeKey).update(data);
                }
                Navigator.pop(context);
              },
              child: Text(key == null ? "Save" : "Update"),
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
      appBar: AppBar(title: const Text("Custom Gestures")),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showGestureDialog(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            itemCount: sortedEntries.length,
            itemBuilder: (context, index) {
              final entry = sortedEntries[index];
              final gestureData = entry.value as Map;
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
                        onPressed: () => _showGestureDialog(key: entry.key, initialMsg: msg, initialTicks: ticks),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _ref.child(entry.key).remove(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }
}
