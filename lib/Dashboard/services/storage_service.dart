import 'dart:convert';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../LoginPage/models/session_model.dart';
import '../../NavBars/Pickings/PickingFormPage/services/hive_service.dart';

/// Central storage service for dashboard/session-related persistent data.
///
/// Uses **SharedPreferences** for lightweight key-value storage and delegates
/// Hive operations to [HiveService] for larger/complex data (e.g. offline pickings).
///
/// Key responsibilities:
///   • Save/load Odoo session data after successful login
///   • Manage login state (isLoggedIn, url, database, password)
///   • Store/retrieve user profile cache
///   • Handle multi-account support (saveAccount/getAccounts)
///   • Store map token
///   • Parse allowed companies
///   • Full data clear (logout / reset) while preserving some onboarding flags
class DashboardStorageService {
  final HiveService _hiveService = HiveService();

  /// Saves essential session data after successful Odoo authentication.
  ///
  /// Stores user info, session ID, server version, language, company, etc.
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

  /// Saves login state flags and credentials (used for auto-login / remember me).
  Future<void> saveLoginState({
    required bool isLoggedIn,
    required String database,
    required String url,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', isLoggedIn);
    await prefs.setString('selectedDatabase', database);
    await prefs.setString('url', url);
    await prefs.setString('pass', password);
  }

  /// Retrieves all session-related data as a map.
  ///
  /// Used throughout the app (DashboardBloc, ProfileBloc, etc.) to reconstruct
  /// OdooSession or check login state.
  Future<Map<String, dynamic>> getSessionData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'userId': prefs.getInt('userId') ?? 0,
      'url': prefs.getString('url') ?? '',
      'db': prefs.getString('selectedDatabase') ?? '',
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

  /// Clears **all** SharedPreferences keys (full session/logout).
  ///
  /// Does **not** preserve onboarding flags — use [clearAllData] for that.
  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /// Saves the encrypted map token (Google Maps / Mapbox / etc.).
  Future<void> saveMapToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mapToken', token);
  }

  /// Parses JSON-encoded company list into [Company] objects.
  ///
  /// Used when restoring allowed companies from session data.
  List<Company> parseCompanies(List<String> companies) {
    return companies
        .map((jsonString) => Company.fromJson(jsonDecode(jsonString)))
        .toList();
  }

  /// Saves the latest user profile map (from Odoo) as JSON.
  Future<void> saveUserProfile(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('user_profile', jsonEncode(user));
  }

  /// Retrieves the last cached user profile (offline fallback).
  Future<Map<String, dynamic>?> getSavedUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('user_profile');
    if (data != null) {
      return Map<String, dynamic>.from(jsonDecode(data));
    }
    return null;
  }

  static const _accountsKey = 'loggedInAccounts';

  /// Saves or updates an account entry (used for account switcher).
  ///
  /// Removes any existing entry with the same `userLogin` before adding.
  /// Ensures 'image' key exists (even if empty).
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

  /// Retrieves list of saved accounts for quick switching.
  Future<List<Map<String, dynamic>>> getAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final accountsJson = prefs.getString(_accountsKey);
    if (accountsJson == null) return [];
    final decoded = jsonDecode(accountsJson) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }

  /// Clears **all** app data (SharedPreferences + Hive) while preserving:
  ///   • URL history
  ///   • hasSeenGetStarted flag
  ///
  /// Used for full logout, account switch with data reset, or app reset.
  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> urlHistory = prefs.getStringList('urlHistory') ?? [];
    bool hasSeenGetStarted = prefs.getBool('hasSeenGetStarted') ?? false;

    await prefs.clear();
    await prefs.setStringList('urlHistory', urlHistory);
    await prefs.setBool('hasSeenGetStarted', hasSeenGetStarted);

    await _hiveService.clearAllData();
  }
}
