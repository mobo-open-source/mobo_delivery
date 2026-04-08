import 'package:shared_preferences/shared_preferences.dart';

/// A simple, type-safe wrapper around [SharedPreferences] for storing
/// app settings and user preferences.
///
/// This service centralizes all key-value persistence operations used in
/// the settings screen (dark mode, reduce motion, language, currency, timezone, etc.).
///
/// Features:
///   • Lazy initialization via [initialize()]
///   • Type-safe getters and setters for common types (bool, String, int, double)
///   • Removal and full clear methods
///
/// Usage recommendation:
///   Call [initialize()] once early in the app lifecycle (e.g. in main() or bloc creation)
///   before any read/write operations.
class SettingsStorageService {
  late SharedPreferences _prefs;

  /// Initializes the SharedPreferences instance.
  ///
  /// Must be called before any get/set operations.
  /// Safe to call multiple times (idempotent).
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Stores a boolean value under the given [key].
  Future<void> setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }

  /// Stores a string value under the given [key].
  Future<void> setString(String key, String value) async => await _prefs.setString(key, value);

  /// Retrieves the string value for [key], or `null` if not set.
  String? getString(String key) => _prefs.getString(key);

  /// Stores an integer value under the given [key].
  Future<void> setInt(String key, int value) async => await _prefs.setInt(key, value);

  /// Retrieves the integer value for [key], or `null` if not set.
  int? getInt(String key) => _prefs.getInt(key);

  /// Stores a double value under the given [key].
  Future<void> setDouble(String key, double value) async => await _prefs.setDouble(key, value);

  /// Retrieves the double value for [key], or `null` if not set.
  double? getDouble(String key) => _prefs.getDouble(key);

  /// Retrieves the boolean value for [key], or `null` if not set.
  bool? getBool(String key) {
    return _prefs.getBool(key);
  }

  /// Removes the value associated with [key].
  Future<void> remove(String key) async {
    await _prefs.remove(key);
  }

  /// Clears **all** keys stored in SharedPreferences.
  ///
  /// Use with caution — this will remove **all** app preferences,
  /// including potentially unrelated ones (login tokens, etc.).
  Future<void> clearAll() async {
    await _prefs.clear();
  }
}
