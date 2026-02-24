import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/company/session/company_session_manager.dart';

/// Service that handles all Odoo RPC calls specific to the dashboard/profile/settings flow.
///
/// Responsibilities:
///   • Network connectivity check with server ping
///   • Fetch/update user profile (res.users)
///   • Fetch/update company details (res.company) — especially custom map key field
///   • Fetch dynamic selection lists: languages (res.lang), currencies (res.currency), timezones
///   • Update user language/timezone preferences
///
/// Uses [CompanySessionManager] for company-aware RPC calls (handles multi-company context).
class OdooDashboardService {
  OdooClient? client;
  String url;
  final OdooSession session;

  OdooDashboardService(this.url, this.session) {
    client = OdooClient(url, sessionId: session);
  }

  /// Checks if the device is online **and** the Odoo server is reachable.
  ///
  /// Returns `true` only if:
  ///   1. Device has network connectivity (Wi-Fi/mobile)
  ///   2. HTTP GET to `$url/web` returns 200 within 5 seconds
  ///
  /// Used before making any RPC calls that require internet.
  Future<bool> checkNetworkConnectivity() async {
    final prefs = await SharedPreferences.getInstance();
    url = prefs.getString('url') ?? '';
    final connectivityResult = await Connectivity().checkConnectivity();

    if (connectivityResult != ConnectivityResult.none) {
      try {
        final response = await http
            .get(Uri.parse('$url/web'))
            .timeout(const Duration(seconds: 5));

        return response.statusCode == 200;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  /// Fetches current user profile fields from `res.users`.
  ///
  /// Returns null on any failure (network, permission, no record).
  /// Dynamically chooses 'mobile' or 'mobile_phone' based on Odoo version.
  Future<Map<String, dynamic>?> getUserProfile(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int version = prefs.getInt('version') ?? 0;
      String mobile;
      if (version < 18) {
        mobile = 'mobile';
      } else {
        mobile = 'mobile_phone';
      }
      final details = [
        'image_1920',
        'name',
        'email',
        'phone',
        'company_id',
        mobile,
      ];
      final userDetails = await CompanySessionManager.callKwWithCompany({
        'model': 'res.users',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', userId],
          ],
        ],
        'kwargs': {'fields': details},
      });
      return userDetails?.isNotEmpty == true ? userDetails[0] : null;
    } catch (e) {
      return null;
    }
  }

  /// Fetches single company record (mainly for custom fields like x_map_key_encrypted).
  Future<Map<String, dynamic>?> getCompanyDetails(int companyId) async {
    try {
      final companyItems = await CompanySessionManager.callKwWithCompany({
        'model': 'res.company',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', companyId],
          ],
        ],
        'kwargs': {},
      });
      return companyItems?.isNotEmpty == true ? companyItems[0] : null;
    } catch (e) {
      return null;
    }
  }

  /// Updates fields on `res.users` record.
  ///
  /// Returns `true` if write succeeded, `false` otherwise.
  Future<bool> updateUserProfile(int userId, Map<String, dynamic> data) async {
    try {
      final result = await CompanySessionManager.callKwWithCompany({
        'model': 'res.users',
        'method': 'write',
        'args': [
          [userId],
          data,
        ],
        'kwargs': {},
      });
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// Creates custom field `x_map_key_encrypted` on `res.company` if missing,
  /// then writes the encrypted map token value.
  Future<void> createMapKeyField(int companyId, String encryptedToken) async {
    try {
      // 1. Get model ID for res.company
      final modelResult = await CompanySessionManager.callKwWithCompany({
        'model': 'ir.model',
        'method': 'search_read',
        'args': [
          [
            ['model', '=', 'res.company'],
          ],
        ],
        'kwargs': {},
      });

      if (modelResult != null && modelResult.isNotEmpty) {
        final int modelIdInt = int.parse(modelResult[0]['id'].toString());

        // 2. Check if custom field already exists
        final existingField = await CompanySessionManager.callKwWithCompany({
          'model': 'ir.model.fields',
          'method': 'search_read',
          'args': [
            [
              ['model', '=', 'res.company'],
              ['name', '=', 'x_map_key_encrypted'],
            ],
          ],
          'kwargs': {},
        });

        // 3. Create field if missing
        if (existingField == null || existingField.isEmpty) {
          await CompanySessionManager.callKwWithCompany({
            'model': 'ir.model.fields',
            'method': 'create',
            'args': [
              {
                'name': 'x_map_key_encrypted',
                'field_description': 'Google Map API Key',
                'ttype': 'char',
                'copied': false,
                'model': 'res.company',
                'model_id': modelIdInt,
              },
            ],
            'kwargs': {},
          });
        }
      }

      // 4. Write encrypted value to company
      await CompanySessionManager.callKwWithCompany({
        'model': 'res.company',
        'method': 'write',
        'args': [
          [companyId],
          {'x_map_key_encrypted': encryptedToken},
        ],
        'kwargs': {},
      });
    } catch (e) {
    }
  }

  /// Fetches active languages from `res.lang`.
  Future<List<dynamic>?> fetchLanguage() async {
    try {
      final languageDetails = await CompanySessionManager.callKwWithCompany({
        'model': 'res.lang',
        'method': 'search_read',
        'args': [
          [
            ['active', '=', true],
          ],
        ],
        'kwargs': {
          'fields': ['code', 'name', 'iso_code', 'direction'],
          'order': 'name',
        },
      });
      return languageDetails?.isNotEmpty == true ? languageDetails : null;
    } catch (e) {
      return null;
    }
  }

  /// Fetches active currencies from `res.currency`.
  Future<List<dynamic>?> fetchCurrency() async {
    try {
      final languageDetails = await CompanySessionManager.callKwWithCompany({
        'model': 'res.currency',
        'method': 'search_read',
        'args': [
          [
            ['active', '=', true],
          ],
          ['name', 'full_name', 'symbol', 'position', 'rounding'],
        ],
        'kwargs': {'order': 'name'},
      });
      return languageDetails?.isNotEmpty == true ? languageDetails : null;
    } catch (e) {
      return null;
    }
  }

  List<Map<String, dynamic>> _availableTimezones = [];

  /// Fetches available timezone options from the `tz` selection field on `res.users`.
  ///
  /// Falls back to a hardcoded list if RPC fails or field has no selection.
  Future<List<Map<String, dynamic>>> fetchTimezones() async {
    try {
      final result = await CompanySessionManager.callKwWithCompany({
        'model': 'res.users',
        'method': 'fields_get',
        'args': [
          ['tz'],
        ],
        'kwargs': {
          'attributes': ['selection', 'string'],
        },
      });

      final tzField = (result != null)
          ? result['tz'] as Map<String, dynamic>?
          : null;
      final selection = tzField != null
          ? tzField['selection'] as List<dynamic>?
          : null;

      List<Map<String, dynamic>> timezones = [];

      if (selection != null && selection.isNotEmpty) {
        timezones = selection.map<Map<String, dynamic>>((item) {
          if (item is List && item.length >= 2) {
            return {'code': item[0].toString(), 'name': item[1].toString()};
          }
          return {'code': item.toString(), 'name': item.toString()};
        }).toList();
      }

      if (timezones.isEmpty) {
        timezones = [
          {'code': 'UTC', 'name': 'UTC'},
          {'code': 'Europe/Brussels', 'name': 'Europe/Brussels'},
          {'code': 'Asia/Kolkata', 'name': 'Asia/Kolkata'},
          {'code': 'America/New_York', 'name': 'America/New_York'},
        ];
      }

      _availableTimezones = timezones;

      return timezones;
    } catch (e) {
      _availableTimezones = [
        {'code': 'UTC', 'name': 'UTC'},
        {'code': 'America/New_York', 'name': 'Eastern Time (US & Canada)'},
        {'code': 'America/Chicago', 'name': 'Central Time (US & Canada)'},
        {'code': 'America/Denver', 'name': 'Mountain Time (US & Canada)'},
        {'code': 'America/Los_Angeles', 'name': 'Pacific Time (US & Canada)'},
        {'code': 'Europe/London', 'name': 'London'},
        {'code': 'Europe/Paris', 'name': 'Paris'},
        {'code': 'Europe/Berlin', 'name': 'Berlin'},
        {'code': 'Asia/Tokyo', 'name': 'Tokyo'},
        {'code': 'Asia/Shanghai', 'name': 'Shanghai'},
        {'code': 'Asia/Kolkata', 'name': 'Mumbai, Kolkata, New Delhi'},
        {'code': 'Asia/Dubai', 'name': 'Dubai'},
        {'code': 'Australia/Sydney', 'name': 'Sydney'},
      ];
      return _availableTimezones;
    } finally {}
  }

  /// Updates language and/or timezone on the user record.
  Future<void> updateLanguage(int id, updatedValue) async {
    try {
      await CompanySessionManager.callKwWithCompany({
        'model': 'res.users',
        'method': 'write',
        'args': [id, updatedValue],
        'kwargs': {},
      });
    } catch (e) {
      return null;
    }
  }
}
