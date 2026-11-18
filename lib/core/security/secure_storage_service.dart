import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../shared/utils/server_url_utils.dart';

/// Provides secure storage operations for saving and retrieving user passwords.
///
/// Uses platform secure storage:
/// - Android: EncryptedSharedPreferences
/// - iOS: Keychain (first unlock of device)
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// Generates a unique key for storing password based on
  /// server URL, database name, and username.
  /// The URL is normalised here rather than trusted from callers. The one
  /// writer passes a normalised URL, but session refresh read it back with the
  /// raw `url` preference, which the sign-in screens store un-normalised — a
  /// trailing slash or a capital in the host was enough for refresh never to
  /// find the password, and every expired session then ended in a logout.
  static String _passwordKey(String url, String database, String username) {
    return 'odoo_pass_${normalizeServerUrl(url)}_${database}_${username}';
  }

  /// Saves password securely for given server, database and user.
  Future<void> savePassword({
    required String url,
    required String database,
    required String username,
    required String password,
  }) async {
    final key = _passwordKey(url, database, username);
    await _storage.write(key: key, value: password);
  }

  /// Retrieves stored password if available, otherwise returns null.
  Future<String?> getPassword({
    required String url,
    required String database,
    required String username,
  }) async {
    final key = _passwordKey(url, database, username);
    return await _storage.read(key: key);
  }

  /// Deletes stored password for specific server, database and user.
  Future<void> deletePassword({
    required String url,
    required String database,
    required String username,
  }) async {
    final key = _passwordKey(url, database, username);
    await _storage.delete(key: key);
  }

  /// Deletes all stored passwords from secure storage.
  Future<void> deleteAllPasswords() async {
    await _storage.deleteAll();
  }
}
