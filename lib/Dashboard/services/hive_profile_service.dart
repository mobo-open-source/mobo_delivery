import 'package:hive/hive.dart';
import '../models/profile.dart';

/// Service responsible for persisting and retrieving the user's [Profile]
/// using **Hive** (lightweight NoSQL key-value store for Flutter/Dart).
///
/// This class provides a clean, type-safe interface for:
///   • Saving the current profile
///   • Retrieving the cached profile
///   • Clearing profile data (e.g. on logout)
///
/// Uses a single-key box named `"profile_box"` with key `'profile'`.
class HiveProfileService {
  static const String _profileBoxName = "profile_box";

  /// Opens (or reuses) the Hive box for storing Profile objects.
  ///
  /// Hive boxes are cached after first open, so repeated calls are efficient.
  Future<Box<Profile>> _openBox() async {
    return await Hive.openBox<Profile>(_profileBoxName);
  }

  /// Saves the given [profile] to Hive.
  ///
  /// Overwrites any existing profile (single-user assumption).
  /// The profile is stored under the fixed key `'profile'`.
  ///
  /// Throws Hive-specific exceptions if write fails (disk full, etc.).
  Future<void> saveProfile(Profile profile) async {
    final box = await _openBox();
    await box.put('profile', profile);
  }

  /// Retrieves the currently cached [Profile] from Hive.
  ///
  /// Returns `null` if:
  ///   • No profile was ever saved
  ///   • The box is empty
  ///   • The stored object could not be deserialized (schema change, corruption)
  Future<Profile?> getProfile() async {
    final box = await _openBox();
    return box.get('profile');
  }

  /// Removes the stored profile from Hive.
  ///
  /// Useful for:
  ///   • Logout / sign out
  ///   • Switching user accounts
  ///   • Clearing sensitive data
  Future<void> clearProfile() async {
    final box = await _openBox();
    await box.delete('profile');
  }
}
