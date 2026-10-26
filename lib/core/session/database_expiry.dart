import 'package:shared_preferences/shared_preferences.dart';

import '../../LoginPage/services/auth_service.dart';
import '../../NavBars/Pickings/PickingFormPage/services/hive_service.dart';
import '../company/session/company_session_manager.dart';
import '../navigation/global_keys.dart';
import '../../shared/utils/odoo_version.dart';
import '../../shared/widgets/snackbar.dart';

/// Raised when the Odoo database behind a session has passed its expiry date.
class DatabaseExpiredException implements Exception {
  const DatabaseExpiredException();

  static const String message =
      'This database has expired. Please contact your administrator or '
      'Odoo to renew the subscription.';

  /// Returns the user-facing wording.
  ///
  /// Account switching and re-authentication surface failures by stringifying
  /// whatever was thrown, so this has to read correctly on its own rather
  /// than as a developer label.
  @override
  String toString() => message;
}

/// Keeps an expired Odoo database out of the app.
///
/// A subscription that has lapsed still answers requests, so a stored session
/// keeps working and the user carries on as if nothing happened. The date is
/// read from the server and checked at the points where it matters: signing
/// in, cold start, and each time the app comes back to the foreground.
class DatabaseExpiry {
  DatabaseExpiry._();

  /// How long a check is trusted before the server is asked again.
  ///
  /// Without this the app pays a round-trip every time it is resumed, which
  /// on a patchy field connection is a visible delay for a value that moves
  /// once a year.
  static const Duration _recheckInterval = Duration(minutes: 30);

  static DateTime? _lastCheck;
  static bool _enforcing = false;

  /// Whether the database behind this session has expired.
  ///
  /// Answers false whenever the date cannot be established — an unreachable
  /// server, a user without rights to read the parameter, or an on-premise
  /// database with no expiry at all. Locking someone out because a check
  /// failed would be far worse than letting an expired database through.
  static Future<bool> isExpired({
    required String serverUrl,
    required String sessionId,
  }) async {
    if (serverUrl.isEmpty || sessionId.isEmpty) return false;

    final raw = await _expirationDate(serverUrl, sessionId);
    return isExpiredDate(raw);
  }

  /// Whether [raw], an Odoo `database.expiration_date`, is in the past.
  ///
  /// Pure and separated from the network so the decision itself can be
  /// tested. Odoo reports the value as a naive UTC timestamp, for example
  /// `2026-10-04 08:39:25`.
  static bool isExpiredDate(String? raw, {DateTime? now}) {
    if (raw == null || raw.trim().isEmpty) return false;

    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}):(\d{2}))?',
    ).firstMatch(raw.trim());
    if (match == null) return false;

    final parts = [
      for (var i = 1; i <= 6; i++) int.tryParse(match.group(i) ?? '') ?? 0,
    ];
    final expiry = DateTime.utc(
      parts[0],
      parts[1],
      parts[2],
      parts[3],
      parts[4],
      parts[5],
    );

    // The same rounding the Odoo web client applies, so the app and the
    // browser agree on the last usable day.
    final reference = (now ?? DateTime.now()).toUtc();
    final daysLeft = expiry.difference(reference).inSeconds / 86400;
    return daysLeft.round() <= 0;
  }

  static Future<String?> _expirationDate(
    String serverUrl,
    String sessionId,
  ) async {
    final url = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final auth = AuthService();

    try {
      final info = await auth.getSessionInfo(url, sessionId);
      final value = info['expiration_date'];
      if (value is String && value.isNotEmpty) return value;
    } catch (_) {
      // Falls through to the parameter below.
    }

    try {
      // Read second, because an ordinary user often has no rights on
      // `ir.config_parameter` and this raises for them.
      final value = await auth.callKwWithSession(
        url: url,
        sessionId: sessionId,
        payload: {
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'model': 'ir.config_parameter',
            'method': configParamGetMethod(
              (await SharedPreferences.getInstance()).getInt('version') ?? 0,
            ),
            'args': ['database.expiration_date'],
            'kwargs': {},
          },
          'id': 1,
        },
      );
      if (value is String && value.isNotEmpty) return value;
    } catch (_) {
      // No date available: treated as not expired.
    }
    return null;
  }

  /// Signs the user out and returns them to the login screen when the stored
  /// session's database has expired. Returns whether it acted.
  ///
  /// Safe to call often: concurrent calls are ignored, and the server is only
  /// asked again once [_recheckInterval] has passed.
  static Future<bool> enforceOnStoredSession({bool force = false}) async {
    if (_enforcing) return false;

    final last = _lastCheck;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _recheckInterval) {
      return false;
    }

    _enforcing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('isLoggedIn') ?? false)) return false;

      final expired = await isExpired(
        serverUrl: prefs.getString('url') ?? '',
        sessionId: prefs.getString('sessionId') ?? '',
      );
      _lastCheck = DateTime.now();
      if (!expired) return false;

      await clearExpiredSession();

      final navigator = navigatorKey.currentState;
      navigator?.pushNamedAndRemoveUntil('/login', (route) => false);

      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        CustomSnackbar.showError(context, DatabaseExpiredException.message);
      }
      return true;
    } finally {
      _enforcing = false;
    }
  }

  /// Clears the signed-in session without any UI.
  ///
  /// Mirrors `CompanySessionManager.logout` minus its dialog and navigation,
  /// so it can be used from a splash screen or a lifecycle callback where no
  /// dialog can be shown.
  static Future<void> clearExpiredSession() async {
    await CompanySessionManager.clearSessionCache();
    try {
      final hiveService = HiveService();
      await hiveService.initialize();
      await hiveService.clearAllData();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    final urlHistory = prefs.getStringList('urlHistory') ?? [];
    final isGetStarted = prefs.getBool('hasSeenGetStarted') ?? false;
    final biometricEnabled = prefs.getBool('biometricEnabled') ?? false;

    await prefs.clear();

    await prefs.setStringList('urlHistory', urlHistory);
    await prefs.setBool('hasSeenGetStarted', isGetStarted);
    await prefs.setBool('biometricEnabled', biometricEnabled);
    await prefs.setBool('isLoggedIn', false);
  }

  /// Forgets the last check, so the next call asks the server again.
  static void reset() => _lastCheck = null;
}
