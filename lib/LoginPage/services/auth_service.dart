import 'dart:convert';

import 'package:local_auth/local_auth.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import '../../core/security/self_signed.dart';
import '../models/auth_model.dart';
import '../models/session_model.dart';

/// Handles all authentication-related operations:
/// - Biometric authentication (Local device security)
/// - Odoo session authentication (Server-side login)
/// - Session-based RPC calls
/// - Session metadata extraction (company, permissions, version info)
class AuthService {
  /// Local device biometric authentication handler
  final LocalAuthentication _auth = LocalAuthentication();

  /// Performs biometric authentication using device security.
  ///
  /// Flow:
  /// 1. Check if biometrics hardware is available
  /// 2. Check if biometric credentials are enrolled
  /// 3. Prompt user authentication
  ///
  /// Returns:
  /// - success → Authenticated
  /// - failure → User cancelled / failed authentication
  /// - unavailable → Biometrics not available on device
  /// - error → Unexpected runtime error
  Future<AuthenticationResult> authenticateWithBiometrics() async {
    try {
      bool canCheckBiometrics = await _auth.canCheckBiometrics;
      List<BiometricType> availableBiometrics = await _auth
          .getAvailableBiometrics();

      if (canCheckBiometrics && availableBiometrics.isNotEmpty) {
        try {
          final bool authenticate = await _auth.authenticate(
            localizedReason: 'Authenticate to access the app',
            options: const AuthenticationOptions(
              stickyAuth: true,
              biometricOnly: true,
            ),
          );
          return authenticate
              ? AuthenticationResult.success
              : AuthenticationResult.failure;
        } catch (_) {
          return AuthenticationResult.error;
        }
      } else {
        return AuthenticationResult.unavailable;
      }
    } catch (_) {
      return AuthenticationResult.error;
    } finally {
      /// Ensures biometric session is properly closed
      await _auth.stopAuthentication();
    }
  }

  /// Extracts major version number from Odoo server version string.
  ///
  /// Example:
  /// - "17.0+e" → 17
  /// - "16.3" → 16
  int parseMajorVersion(String serverVersion) {
    final match = RegExp(r'\d+').firstMatch(serverVersion);
    if (match != null) {
      return int.tryParse(match.group(0)!) ?? 0;
    }
    return 0;
  }

  /// Retrieves session info directly using existing session cookie.
  ///
  /// Used for:
  /// - Restoring existing session
  /// - Validating session without re-login
  Future<Map<String, dynamic>> getSessionInfo(
    String url,
    String sessionId,
  ) async {
    final response = await ioClient.post(
      Uri.parse('$url/web/session/get_session_info'),
      headers: {
        'Content-Type': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        'Origin': url,
        'Cookie': 'session_id=$sessionId',
      },
      body: jsonEncode({
        "jsonrpc": "2.0",
        "method": "call",
        "params": {},
        "id": 1,
      }),
    );

    final data = jsonDecode(response.body);
    return Map<String, dynamic>.from(data['result']);
  }

  /// Generic RPC call using existing session cookie.
  ///
  /// Allows calling any Odoo model method using raw JSON-RPC.
  Future<dynamic> callKwWithSession({
    required String url,
    required String sessionId,
    required Map<String, dynamic> payload,
  }) async {
    final res = await ioClient.post(
      Uri.parse('$url/web/dataset/call_kw'),
      headers: {
        'Content-Type': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        'Cookie': 'session_id=$sessionId',
      },
      body: jsonEncode(payload),
    );

    final data = jsonDecode(res.body);
    if (data['error'] != null) throw data['error'];
    return data['result'];
  }

  /// Parses company field from Odoo responses.
  ///
  /// Handles both formats:
  /// - [id, name]
  /// - { id, name/display_name }
  Map<String, dynamic>? _parseCompany(dynamic value) {
    if (value == null) return null;

    if (value is List && value.length >= 2) {
      return {'id': value[0], 'name': value[1]};
    }

    if (value is Map) {
      return {
        'id': value['id'],
        'name': value['display_name'] ?? value['name'],
      };
    }
    return null;
  }

  /// Main Odoo authentication method.
  ///
  /// Supports two flows:
  /// 1. Session-based authentication (Existing session cookie)
  /// 2. Username/password authentication
  ///
  /// Returns SessionModel containing:
  /// - User details
  /// - Company info
  /// - Permissions (System user check)
  /// - Allowed companies
  /// - Server version metadata
  Future<SessionModel?> authenticateOdoo({
    required String url,
    required String database,
    required String username,
    required String password,
    sessionId,
  }) async {
    try {
      final client = OdooClient(url);
      final session;
      int userId = 0;

      /// -------------------------
      /// SESSION COOKIE LOGIN FLOW
      /// -------------------------
      if (sessionId != null) {
        final sessionInfo = await getSessionInfo(url, sessionId);

        final int userId = sessionInfo['uid'];
        final String serverVersion = sessionInfo['server_version'];
        final int majorVersion = parseMajorVersion(serverVersion);

        /// Fetch company info
        final userData = await callKwWithSession(
          url: url,
          sessionId: sessionId,
          payload: {
            "jsonrpc": "2.0",
            "method": "call",
            "params": {
              "model": "res.users",
              "method": "read",
              "args": [
                [userId],
                ["company_id"],
              ],
              "kwargs": {},
            },
            "id": 1,
          },
        );

        final company = _parseCompany(userData[0]['company_id']);

        /// System user permission check (version dependent)
        bool isSystem = false;
        if (majorVersion >= 18) {
          isSystem =
              await callKwWithSession(
                url: url,
                sessionId: sessionId,
                payload: {
                  "jsonrpc": "2.0",
                  "method": "call",
                  "params": {
                    "model": "res.users",
                    "method": "has_group",
                    "args": [userId, "base.group_system"],
                    "kwargs": {},
                  },
                  "id": 1,
                },
              ) ==
              true;
        } else {
          isSystem =
              await callKwWithSession(
                url: url,
                sessionId: sessionId,
                payload: {
                  "jsonrpc": "2.0",
                  "method": "call",
                  "params": {
                    "model": "res.users",
                    "method": "has_group",
                    "args": ["base.group_system"],
                    "kwargs": {},
                  },
                  "id": 1,
                },
              ) ==
              true;
        }

        /// Fetch allowed companies
        List<int> allowedCompanyIds = [];
        if (majorVersion >= 13) {
          final companiesRes = await callKwWithSession(
            url: url,
            sessionId: sessionId,
            payload: {
              "jsonrpc": "2.0",
              "method": "call",
              "params": {
                "model": "res.users",
                "method": "read",
                "args": [
                  [userId],
                  ["company_ids"],
                ],
                "kwargs": {},
              },
              "id": 1,
            },
          );

          if (companiesRes is List && companiesRes.isNotEmpty) {
            allowedCompanyIds =
                (companiesRes[0]['company_ids'] as List?)?.cast<int>() ?? [];
          }
        }

        return SessionModel(
          sessionId: sessionId,
          userId: userId,
          userLogin: sessionInfo['username'],
          userName: sessionInfo['name'],
          serverVersion: serverVersion,
          version: majorVersion,
          userLang: sessionInfo['lang'],
          userTimezone: sessionInfo['tz'],
          partnerId: sessionInfo['partner_id'],
          companyId: company?['id'],
          companyName: company?['name'],
          isSystem: isSystem,
          allowedCompanyIds: allowedCompanyIds,
        );
      } else {
        /// -------------------------
        /// USERNAME PASSWORD LOGIN
        /// -------------------------
        session = await client.authenticate(database, username, password);
        userId = session.userId;

        if (session != null) {
          final userData = await client.callKw({
            'model': 'res.users',
            'method': 'read',
            'args': [
              [userId],
              ['company_id'],
            ],
            'kwargs': {},
          });
          final int majorVersion = parseMajorVersion(session.serverVersion);

          bool isSystem = false;

          if (majorVersion >= 18) {
            isSystem = await client.callKw({
              'model': 'res.users',
              'method': 'has_group',
              'args': [session.userId, 'base.group_system'],
              'kwargs': {},
            });
          } else {
            isSystem = await client.callKw({
              'model': 'res.users',
              'method': 'has_group',
              'args': ['base.group_system'],
              'kwargs': {},
            });
          }

          List<int> allowedCompanyIds = [];
          if (majorVersion >= 13) {
            final companiesRes = await client.callKw({
              'model': 'res.users',
              'method': 'read',
              'args': [
                [session.userId],
                ['company_ids'],
              ],
              'kwargs': {},
            });
            if (companiesRes is List && companiesRes.isNotEmpty) {
              allowedCompanyIds =
                  (companiesRes[0]['company_ids'] as List?)?.cast<int>() ?? [];
            }
          }
          return SessionModel(
            sessionId: session.id,
            userName: session.userName,
            userLogin: session.userLogin?.toString(),
            userId: session.userId,
            serverVersion: session.serverVersion,
            userLang: session.userLang,
            partnerId: session.partnerId,
            userTimezone: session.userTz,
            companyId: userData.isNotEmpty
                ? userData[0]['company_id'][0]
                : null,
            companyName: userData.isNotEmpty
                ? userData[0]['company_id'][1]
                : null,
            isSystem: isSystem,
            version: majorVersion,
            allowedCompanyIds: allowedCompanyIds,
          );
        }
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }
}
