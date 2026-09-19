import 'package:flutter/foundation.dart';

class LogsService {
  static final List<String> _logs = [];

  static void add(String message) {
    final timestamp = DateTime.now().toString().split('.').first;
    final log = "[$timestamp] $message";
    _logs.add(log);
    if (kDebugMode) {
      print(log);
    }
    // Keep only last 1000 logs
    if (_logs.length > 1000) {
      _logs.removeAt(0);
    }
  }

  static List<String> get logs => List.unmodifiable(_logs);

  static void clear() {
    _logs.clear();
  }
}
