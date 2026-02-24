import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

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

  /// Initializes the Odoo RPC client using the current authenticated session.
  ///
  /// Must be called before any other method that performs RPC calls.
  /// Throws an exception if no active session exists (user not logged in).
  Future<void> initializeOdooClient() async {
    final session = await CompanySessionManager.getCurrentSession();
    if (session == null) throw Exception("No active session");
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

  /// Decrypts AES-CBC encrypted text (used for Google Maps API key).
  ///
  /// Expects input in format: [16-byte IV] + [encrypted payload] (base64-encoded).
  /// Uses fixed 32-byte key: `"my32lengthsupersecretnooneknows!"`
  /// Applies PKCS7 padding.
  ///
  /// **Security note**: Hardcoded key is **not** production-safe. Consider using secure storage
  /// (e.g. flutter_secure_storage) or server-side key management.
  String decryptText(String base64Text) {
    final fullBytes = base64.decode(base64Text);

    final ivBytes = fullBytes.sublist(0, 16);
    final encryptedBytes = fullBytes.sublist(16);

    final key = encrypt.Key.fromUtf8("my32lengthsupersecretnooneknows!");
    final iv = encrypt.IV(ivBytes);

    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: "PKCS7"),
    );

    final decrypted = encrypter.decrypt(
      encrypt.Encrypted(encryptedBytes),
      iv: iv,
    );

    return decrypted;
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
  Future<String> getMapToken() async {
    try {
      final result = await CompanySessionManager.callKwWithCompany({
        'model': 'res.company',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', companyId],
          ],
        ],
        'kwargs': {
          'fields': ['x_map_key_encrypted'],
        },
      });

      if (result != null && result.toString().isNotEmpty) {
        final encryptedValue = result[0]['x_map_key_encrypted'];

        if (encryptedValue != null && encryptedValue.isNotEmpty) {
          final decryptedKey = decryptText(encryptedValue);
          return decryptedKey;
        } else {
          throw Exception('Encrypted Google Maps API key is empty.');
        }
      } else {
        throw Exception(
          'Google Maps API key not found in Odoo for company $companyId',
        );
      }
    } catch (e) {
      throw Exception('Failed to fetch Google Maps API key: $e');
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