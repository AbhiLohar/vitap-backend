import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeManager {
  static final ThemeManager instance = ThemeManager._internal();
  ThemeManager._internal();

  final ValueNotifier<String> currentTheme = ValueNotifier('dark');

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final String? mode = prefs.getString('themeMode');
    if (mode != null) {
      currentTheme.value = mode;
    } else {
      currentTheme.value = 'dark';
    }
  }

  Future<void> setTheme(String themeName) async {
    currentTheme.value = themeName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', themeName);
  }
}
