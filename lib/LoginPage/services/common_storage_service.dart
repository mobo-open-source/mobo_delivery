import 'dart:convert';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/session_model.dart';

/// Service class to handle persistent storage of user session,
/// login state, profiles, accounts, and app-specific tokens using SharedPreferences.
class CommonStorageService {
  /// Saves the current user session details to local storage.
  ///
  /// Includes user info, company, session ID, language, timezone, and system flag.
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
    await prefs.setInt('version', session.version ?? 0);
  }

  /// Saves the login state and associated database/url info.
  ///
  /// [isLoggedIn] indicates whether the user is logged in.
  /// [database] and [url] are the last used connection info.
  Future<void> saveLoginState({
    required bool isLoggedIn,
    required String database,
    required String url,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', isLoggedIn);
    await prefs.setString('database', database);
    await prefs.setString('url', url);
  }

  /// Retrieves all session data as a map from SharedPreferences.
  ///
  /// Returns default values if certain keys are missing.
  Future<Map<String, dynamic>> getSessionData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'userId': prefs.getInt('userId') ?? 0,
      'url': prefs.getString('url') ?? '',
      'db': prefs.getString('database') ?? '',
      'sessionId': prefs.getString('sessionId') ?? '',
      'serverVersion': prefs.getString('serverVersion') ?? '',
      'userLang': prefs.getString('userLang') ?? '',
      'companyId': prefs.getInt('companyId') ?? 1,
      'isSystem': prefs.getBool('isSystem') ?? false,
      'partnerId': prefs.getInt('partnerId') ?? 0,
      'userLogin': prefs.getString('userLogin') ?? '',
      'userName': prefs.getString('userName') ?? '',
      'allowedCompanies': prefs.getStringList('allowedCompanies') ?? [],
      'mapToken': prefs.getString('mapToken') ?? '',
    };
  }

  /// Clears all session and app data from SharedPreferences.
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /// Saves a map token string to local storage.
  Future<void> saveMapToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mapToken', token);
  }

  /// Parses a list of JSON strings representing companies into [Company] objects.
  List<Company> parseCompanies(List<String> companies) {
    return companies
        .map((jsonString) => Company.fromJson(jsonDecode(jsonString)))
        .toList();
  }

  /// Saves a user profile as JSON to local storage.
  Future<void> saveUserProfile(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('user_profile', jsonEncode(user));
  }

  /// Retrieves the saved user profile from local storage.
  ///
  /// Returns `null` if no profile is saved.
  Future<Map<String, dynamic>?> getSavedUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('user_profile');
    if (data != null) {
      return Map<String, dynamic>.from(jsonDecode(data));
    }
    return null;
  }

  static const _accountsKey = 'loggedInAccounts';

  /// Saves a single account to the list of logged-in accounts.
  ///
  /// Ensures uniqueness by `userLogin` and sets a default empty image if missing.
  Future<void> saveAccount(Map<String, dynamic> account) async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = await getAccounts();
    accounts.removeWhere((a) => a['userLogin'] == account['userLogin']);
    if (!account.containsKey('image')) {
      account['image'] = '';
    }

    accounts.add(account);

    await prefs.setString(_accountsKey, jsonEncode(accounts));
  }

  /// Retrieves all saved accounts as a list of maps.
  Future<List<Map<String, dynamic>>> getAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final accountsJson = prefs.getString(_accountsKey);
    if (accountsJson == null) return [];
    final decoded = jsonDecode(accountsJson) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }

  /// Clears all stored data while preserving `urlHistory` and `hasSeenGetStarted` flags.
  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> urlHistory = prefs.getStringList('urlHistory') ?? [];
    bool hasSeenGetStarted = prefs.getBool('hasSeenGetStarted') ?? false;

    await prefs.clear();
    await prefs.setStringList('urlHistory', urlHistory);
    await prefs.setBool('hasSeenGetStarted', hasSeenGetStarted);
  }
}
