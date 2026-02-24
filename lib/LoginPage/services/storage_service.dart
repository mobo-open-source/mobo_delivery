import 'package:shared_preferences/shared_preferences.dart';
import '../models/session_model.dart';

/// Service class responsible for handling local storage operations
/// using SharedPreferences.
///
/// This includes:
/// - Saving and retrieving user session details
/// - Managing login state (logged in status, database, URL)
/// - Storing and retrieving multiple logged-in account details
/// - Managing saved locale preferences
///
/// All data is persisted locally on the device.
class StorageService {
  /// Saves the current user session details to local storage.
  ///
  /// Stores user-related information such as:
  /// - Username and login
  /// - User ID and session ID
  /// - Server version and language
  /// - Partner ID and company details
  /// - Timezone and system flags
  /// - Allowed company IDs list
  ///
  /// [session] - SessionModel object containing session data.
  Future<void> saveSession(SessionModel session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userName', session.userName ?? '');
    await prefs.setString('userLogin', session.userLogin ?? '');
    await prefs.setInt('userId', session.userId ?? 0);
    await prefs.setString('sessionId', session.sessionId);
    await prefs.setString('serverVersion', session.serverVersion ?? '');
    await prefs.setString('userLang', session.userLang ?? '');
    await prefs.setInt('partnerId', session.partnerId ?? 0);
    await prefs.setString('userTimezone', session.userTimezone ?? '');
    await prefs.setInt('companyId', session.companyId ?? 1);
    await prefs.setString('company_name', session.companyName ?? '');
    await prefs.setBool('isSystem', session.isSystem);
    await prefs.setInt('version', session.version??0);
  }

  /// Saves login state information to local storage.
  ///
  /// Stores:
  /// - Whether user is logged in
  /// - Selected database name
  /// - Server URL
  ///
  /// [isLoggedIn] - Indicates login status.
  /// [database] - Selected database name.
  /// [url] - Server URL.
  Future<void> saveLoginState({
    required bool isLoggedIn,
    required String database,
    required String url,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', isLoggedIn);
    await prefs.setString('selectedDatabase', database);
    await prefs.setString('url', url);
  }

  /// Retrieves login state information from local storage.
  ///
  /// Returns a map containing:
  /// - isLoggedIn → bool
  /// - useLocalAuth → bool
  /// - database → String
  /// - url → String
  ///
  /// Provides default values if nothing is stored.
  Future<Map<String, dynamic>> getLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'isLoggedIn': prefs.getBool('isLoggedIn') ?? false,
      'useLocalAuth': prefs.getBool('useLocalAuth') ?? false,
      'selectedDatabase': prefs.getString('selectedDatabase') ?? '',
      'url': prefs.getString('url') ?? '',
      'password': prefs.getString('pass') ?? '',
    };
  }
}