// lib/services/preferences_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_preferences.dart';

class PreferencesService extends ChangeNotifier {
  static const String _prefsKey = 'user_preferences';

  static PreferencesService? _instance;
  static PreferencesService get instance => _instance ??= PreferencesService._();

  PreferencesService._();

  UserPreferences _currentPrefs = const UserPreferences();

  UserPreferences get currentPreferences => _currentPrefs;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_prefsKey);
    if (jsonString != null) {
      try {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        _currentPrefs = UserPreferences.fromJson(json);
      } catch (_) {
        // Si erreur de parsing, utiliser les préférences par défaut
        _currentPrefs = const UserPreferences();
      }
    }
  }

  Future<void> updatePreferences(UserPreferences newPrefs) async {
    _currentPrefs = newPrefs;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(newPrefs.toJson()));
    notifyListeners(); // Notifier les listeners du changement
  }

  Future<void> updateListCardStyle(ListCardStyle style) async {
    final newPrefs = _currentPrefs.copyWith(listCardStyle: style);
    await updatePreferences(newPrefs);
  }
}
