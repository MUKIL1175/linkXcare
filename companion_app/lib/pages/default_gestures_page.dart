import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../core/app_state_manager.dart';

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
      print("DEBUG: DefaultGestures Error: $e");
    }

    _subscription = _ref.onValue.listen((event) {
      final data = event.snapshot.value;
      if (mounted) {
        setState(() {
          if (data is Map) {
            _gestures = Map<String, dynamic>.from(data);
          }
          _isLoading = false;
        });
      }
    });

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _editAction(String key, String currentAction) {
    if (key == "Closed" && !AppStateManager().isDeveloperMode) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Developer Mode Required!")));
      return;
    }

    final TextEditingController controller = TextEditingController(text: currentAction);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Edit $key Action"),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: "Action Title")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _ref.child(key).set(controller.text);
                Navigator.pop(context);
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
        : ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final e = entries[index];
              return ListTile(
                title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(e.value.toString()),
                trailing: IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _editAction(e.key, e.value.toString())),
              );
            },
          ),
    );
  }
}
