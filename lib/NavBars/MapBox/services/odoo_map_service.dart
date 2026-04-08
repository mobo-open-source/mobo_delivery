import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/company/session/company_session_manager.dart';

/// Service layer responsible for all Odoo-related operations needed by the map/route visualization feature.
///
/// This class handles:
///   - Odoo client/session initialization
///   - Network connectivity checks (with Odoo server ping)
///   - Secure decryption of Google Maps API key stored in Odoo
///   - Fetching stock pickings enriched with readable start/destination addresses
///
/// All RPC calls go through `CompanySessionManager`. Sensitive data (API keys) are stored encrypted
/// in `res.company.x_map_key_encrypted` and decrypted using AES-CBC.
class OdooMapService {
  int? userId;
  int? companyId;
  String url = "";

  /// Session-level cache: avoids re-fetching from Odoo on every map action.
  String? _cachedToken;

  /// Clears the cached token — call this after admin updates the key.
  void clearTokenCache() => _cachedToken = null;

  /// Initializes the Odoo RPC client using the current authenticated session.
  ///
  /// Must be called before any other method that performs RPC calls.
  /// Throws an exception if no active session exists (user not logged in).
  Future<void> initializeOdooClient() async {
    final session = await CompanySessionManager.getCurrentSession();
    if (session == null) throw Exception("No active session");
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getInt('userId') ?? session.userId ?? 0;
    companyId = prefs.getInt('companyId') ?? session.companyId ?? 1;
  }

  /// Checks if the device has internet access **and** can reach the Odoo server.
  ///
  /// First checks general connectivity via `connectivity_plus`.
  /// Then performs a quick GET request to `$url/web` with 5-second timeout.
  /// Returns `true` only if both conditions are satisfied.
  Future<bool> checkNetworkConnectivity() async {
    final prefs = await SharedPreferences.getInstance();
    url = prefs.getString('url') ?? '';
    final connectivityResult = await Connectivity().checkConnectivity();

    if (connectivityResult.any((r) => r != ConnectivityResult.none)) {
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

  /// Decrypts AES-CBC encrypted text (used for Google Maps API key).
  ///
  /// Expects input in format: [16-byte IV] + [encrypted payload] (base64-encoded).
  /// Uses fixed 32-byte key: `"my32lengthsupersecretnooneknows!"`
  /// Applies PKCS7 padding.
  ///
  /// **Security note**: Hardcoded key is **not** production-safe. Consider using secure storage
  /// (e.g. flutter_secure_storage)  /// Must match the logic in EncryptionService.
  /// If decryption fails (e.g., if it was entered into Odoo as plain text natively), it falls back to returning the raw text.
  String decryptText(String base64Text) {
    try {
      final fullBytes = base64Decode(base64Text);

      // Check if it has at least the IV (16 bytes). If not, it's not our AES format.
      if (fullBytes.length <= 16) {
        return base64Text;
      }

      final ivBytes = fullBytes.sublist(0, 16);
      final encryptedBytes = fullBytes.sublist(16);

      final keyStr = dotenv.env['ENCRYPTION_KEY'];
      if (keyStr == null || keyStr.length != 32) {
        throw Exception('Missing or invalid ENCRYPTION_KEY in .env file (must be 32 chars).');
      }
      final key = encrypt.Key.fromUtf8(keyStr);
      final iv = encrypt.IV(ivBytes);

      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
      );

      final decrypted = encrypter.decrypt(
        encrypt.Encrypted(encryptedBytes),
        iv: iv,
      );
      return decrypted;
    } catch (e) {
      // If it fails to parse as base64 or fails to decrypt, assume it's a plain text API key
      return base64Text;
    }
  }

  /// Fetches and decrypts the Google Maps API key stored in the current company record.
  ///
  /// Looks up `res.company` for the current user's company,
  /// reads field `x_map_key_encrypted`, and decrypts it using AES-CBC.
  ///
  /// Throws descriptive exceptions on:
  ///   - No session / company
  ///   - Missing or empty encrypted key
  ///   - RPC or decryption failure
  /// Ensures `x_map_key_encrypted` field exists on `res.company`, creating it if absent.
  ///
  /// Safe to call multiple times — is a no-op when the field already exists.
  Future<void> _ensureMapKeyField() async {
    try {
      final existingField = await CompanySessionManager.callKwWithCompany({
        'model': 'ir.model.fields',
        'method': 'search_count',
        'args': [
          [
            ['model', '=', 'res.company'],
            ['name', '=', 'x_map_key_encrypted'],
          ],
        ],
        'kwargs': {},
      });

      if ((existingField ?? 0) > 0) return; // already exists

      // Get res.company model ID
      final modelResult = await CompanySessionManager.callKwWithCompany({
        'model': 'ir.model',
        'method': 'search_read',
        'args': [
          [
            ['model', '=', 'res.company'],
          ],
        ],
        'kwargs': {'fields': ['id'], 'limit': 1},
      });

      if (modelResult == null || modelResult.isEmpty) return;
      final modelId = int.parse(modelResult[0]['id'].toString());

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
            'model_id': modelId,
          },
        ],
        'kwargs': {},
      });
    } catch (_) {
      // Non-fatal — field creation failure is handled upstream
    }
  }

  /// Fetches and decrypts the Google Maps API key stored in the current company record.
  ///
  /// • Auto-creates the custom field on Odoo if it doesn't exist yet.
  /// • Result is cached for the page session. Call [clearTokenCache] to force refresh.
  /// • Falls back to locally cached token when offline.
  /// • Throws a user-friendly exception when no key is configured anywhere.
  Future<String> getMapToken() async {
    if (_cachedToken != null && _cachedToken!.isNotEmpty) return _cachedToken!;

    final prefs = await SharedPreferences.getInstance();
    final cid = companyId ?? prefs.getInt('companyId') ?? 1;

    try {
      // Ensure field exists before reading it (first-run safe)
      await _ensureMapKeyField();

      final result = await CompanySessionManager.callKwWithCompany({
        'model': 'res.company',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', cid],
          ],
        ],
        'kwargs': {
          'fields': ['x_map_key_encrypted'],
        },
      });

      if (result == null || result.isEmpty) {
        throw Exception('Company record not found (id=$cid).');
      }

      final encryptedValue = result[0]['x_map_key_encrypted'];
      if (encryptedValue == null ||
          encryptedValue == false ||
          encryptedValue.toString().trim().isEmpty) {
        throw Exception(
          'Google Maps API key is not configured.\n'
          'Go to Profile → edit the "Google Maps API Key" field and save.',
        );
      }

      final decryptedKey = decryptText(encryptedValue.toString());
      _cachedToken = decryptedKey;

      // Keep local secure storage in sync for offline use
      await const FlutterSecureStorage().write(key: 'mapToken', value: decryptedKey);

      return decryptedKey;
    } catch (e) {
      // Fallback: use locally cached token (works offline or when field missing)
      const storage = FlutterSecureStorage();
      final local = await storage.read(key: 'mapToken');
      if (local != null && local.isNotEmpty) {
        _cachedToken = local;
        return local;
      }
      rethrow;
    }
  }

  /// Fetches all stock pickings and enriches them with human-readable start/destination addresses.
  ///
  /// Steps:
  ///   1. Reads `stock.picking` records (id, name, location_id, location_dest_id, partner_id)
  ///   2. Collects unique location & partner IDs
  ///   3. Fetches company addresses for locations (via `stock.location.company_id`)
  ///   4. Fetches partner addresses directly
  ///   5. Maps addresses → picking records (starting_point, destination_point)
  ///
  /// Returns enriched list or empty list on any failure (graceful degradation).
  Future<List<Map<String, dynamic>>> fetchStockPickings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getInt('userId') ?? 0;

      final pickingItems = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'fields': ['id', 'name', 'location_id', 'location_dest_id', 'partner_id'],
        },
      });

      if (pickingItems == null || pickingItems.isEmpty) return [];

      final locationIds = <int>{};
      final partnerIds = <int>{};

      for (var p in pickingItems) {
        if (p['location_id'] is List && p['location_id'].isNotEmpty) {
          locationIds.add(p['location_id'][0]);
        }
        if (p['location_dest_id'] is List && p['location_dest_id'].isNotEmpty) {
          locationIds.add(p['location_dest_id'][0]);
        }
        if (p['partner_id'] is List && p['partner_id'].isNotEmpty) {
          partnerIds.add(p['partner_id'][0]);
        }
      }

      final locationData = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.location',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', locationIds.toList()],
          ],
        ],
        'kwargs': {'fields': ['id', 'company_id']},
      });

      final locationToCompany = <int, int>{};
      final companyIds = <int>{};

      if (locationData != null) {
        for (var loc in locationData) {
          if (loc['company_id'] is List && loc['company_id'].isNotEmpty) {
            locationToCompany[loc['id']] = loc['company_id'][0];
            companyIds.add(loc['company_id'][0]);
          }
        }
      }

      final companyData = await CompanySessionManager.callKwWithCompany({
        'model': 'res.company',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', companyIds.toList()],
          ],
        ],
        'kwargs': {
          'fields': ['street', 'city', 'zip', 'state_id', 'country_id'],
        },
      });

      final companyAddresses = _mapAddresses(companyData);

      final partnerData = await CompanySessionManager.callKwWithCompany({
        'model': 'res.partner',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', partnerIds.toList()],
          ],
        ],
        'kwargs': {
          'fields': ['street', 'city', 'zip', 'state_id', 'country_id'],
        },
      });

      final partnerAddresses = _mapAddresses(partnerData);

      List<Map<String, dynamic>> enrichedPickings = [];

      for (var picking in pickingItems) {
        Map<String, dynamic> enrichedPicking = Map.from(picking);

        int? locationId = picking['location_id'] is List && picking['location_id'].isNotEmpty
            ? picking['location_id'][0]
            : null;
        int? destLocationId = picking['location_dest_id'] is List && picking['location_dest_id'].isNotEmpty
            ? picking['location_dest_id'][0]
            : null;
        int? partnerId = picking['partner_id'] is List && picking['partner_id'].isNotEmpty
            ? picking['partner_id'][0]
            : null;

        String startingPoint = _getAddressFromMaps(locationId, partnerId, locationToCompany, companyAddresses, partnerAddresses);
        String destinationPoint = _getAddressFromMaps(destLocationId, partnerId, locationToCompany, companyAddresses, partnerAddresses);

        enrichedPicking['starting_point'] = startingPoint;
        enrichedPicking['destination_point'] = destinationPoint;

        enrichedPickings.add(enrichedPicking);
      }

      return enrichedPickings;
    } catch (e) {
      return [];
    }
  }

  /// Maps company/partner records to ID → formatted address string.
  ///
  /// Combines street, city, state, country (if available) with commas.
  /// Filters out null/empty parts.
  Map<int, String> _mapAddresses(List<dynamic>? data) {
    final map = <int, String>{};
    if (data != null) {
      for (var item in data) {
        final id = item['id'];
        final addressParts = [
          item['street'],
          item['city'],
          item['state_id'] is List && item['state_id'].length > 1 ? item['state_id'][1] : null,
          item['country_id'] is List && item['country_id'].length > 1 ? item['country_id'][1] : null,
        ].where((part) => part != null && part.toString().trim().isNotEmpty).join(', ');
        map[id] = addressParts;
      }
    }
    return map;
  }

  /// Resolves the most appropriate address for a picking's start or destination.
  ///
  /// Priority:
  ///   1. Company address (from location → company)
  ///   2. Partner (customer/supplier) address
  /// Returns empty string if no match found.
  String _getAddressFromMaps(
      int? locationId,
      int? partnerId,
      Map<int, int> locationToCompany,
      Map<int, String> companyAddresses,
      Map<int, String> partnerAddresses,
      ) {
    if (locationId != null && locationToCompany.containsKey(locationId)) {
      int companyId = locationToCompany[locationId]!;
      if (companyAddresses.containsKey(companyId)) {
        return companyAddresses[companyId]!;
      }
    }
    if (partnerId != null && partnerAddresses.containsKey(partnerId)) {
      return partnerAddresses[partnerId]!;
    }
    return '';
  }
}