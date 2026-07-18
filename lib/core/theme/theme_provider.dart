import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class _SettingsStore {
  static Future<String?> get(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
    final box = Hive.box('settings');
    return box.get(key) as String?;
  }

  static Future<void> set(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } else {
      final box = Hive.box('settings');
      await box.put(key, value);
    }
  }
}

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _init();
  }

  Future<void> _init() async {
    final val = await _SettingsStore.get('themeMode') ?? 'dark';
    switch (val) {
      case 'light': state = ThemeMode.light; break;
      case 'dark': state = ThemeMode.dark; break;
      default: state = ThemeMode.system; break;
    }
  }

  void set(ThemeMode mode) {
    state = mode;
    String val;
    switch (mode) {
      case ThemeMode.light: val = 'light'; break;
      case ThemeMode.dark: val = 'dark'; break;
      default: val = 'system'; break;
    }
    _SettingsStore.set('themeMode', val);
  }
}
