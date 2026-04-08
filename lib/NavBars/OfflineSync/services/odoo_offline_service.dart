import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:intl/intl.dart';

import '../../../core/company/session/company_session_manager.dart';

/// Service responsible for performing **online** RPC operations to synchronize offline-pending actions
/// back to Odoo when internet becomes available.
///
/// This class contains the actual Odoo method calls (validate, cancel, write, create) that were
/// deferred during offline mode. All calls are made through `CompanySessionManager` using the
/// authenticated session.
///
/// Key responsibilities:
///   - Validate, cancel, or update existing stock pickings
///   - Update individual stock moves (products/lines)
///   - Create entirely new stock pickings with move lines
///   - Ensure date fields are in Odoo's expected format (`YYYY-MM-DD HH:MM:SS`)
class OdooOfflineSyncService {
  OdooClient? client;

  /// Initializes the Odoo RPC client using the current authenticated session.
  ///
  /// Must be called before any RPC operations.
  /// Throws an exception if no active session exists (user not logged in).
  Future<void> initClient() async {
    final session = await CompanySessionManager.getCurrentSession();
    if (session == null) throw Exception("No active session");
  }

  /// Calls Odoo's `stock.picking.button_validate()` to validate/confirm a picking.
  ///
  /// Typically used to sync offline-validated deliveries.
  /// Returns the RPC result (usually `true` on success).
  /// Throws on network/auth failure.
  Future<dynamic> validatePicking(int pickingId) async {
    return await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'button_validate',
      'args': [
        [pickingId],
      ],
      'kwargs': {},
    });
  }

  /// Calls Odoo's `stock.picking.action_cancel()` to cancel a picking.
  ///
  /// Used to sync offline-cancelled deliveries.
  /// Returns the RPC result (usually `true` on success).
  /// Throws on network/auth failure.
  Future<dynamic> cancelPicking(int pickingId) async {
    return await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'action_cancel',
      'args': [
        [pickingId],
      ],
      'kwargs': {},
    });
  }

  /// Updates fields on an existing `stock.picking` record using `write()`.
  ///
  /// Supported fields (from `updates` map):
  ///   - partner_id
  ///   - scheduled_date (auto-formatted)
  ///   - origin
  ///   - date_done
  ///   - move_type
  ///   - user_id
  ///
  /// Returns `true` on success, throws on failure.
  Future<bool> saveChanges(int pickingId, Map<String, dynamic> updates) async {
    return await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'write',
      'args': [
        [pickingId],
        {
          'partner_id': updates['updates']['partner_id'],
          'scheduled_date': ensureOdooDateFormat(
            updates['updates']['scheduled_date'],
          ),
          'origin': updates['updates']['origin'],
          'date_done': updates['updates']['date_done'],
          'move_type': updates['updates']['move_type'],
          'user_id': updates['updates']['user_id'],
        },
      ],
      'kwargs': {},
    });
  }

  /// Updates a single `stock.move` (picking line/product) using `write()`.
  ///
  /// Used to sync changes to product quantity, location, etc.
  /// Returns `true` on success, throws on failure.
  Future<bool> productUpdates(
    int pickingId,
    Map<String, dynamic> updates,
    int location_id_int,
    int location_dest_id_int,
  ) async {
    return await CompanySessionManager.callKwWithCompany({
      'model': 'stock.move',
      'method': 'write',
      'args': [
        [updates['id']],
        {
          'product_id': updates['product_id'][0],
          'quantity': updates['quantity'],
          'location_id': location_id_int,
          'location_dest_id': location_dest_id_int,
        },
      ],
      'kwargs': {},
    });
  }

  /// Ensures a date string is in Odoo's expected server format: `YYYY-MM-DD HH:MM:SS`.
  ///
  /// If input already matches the pattern, returns it unchanged.
  /// Otherwise attempts to parse and reformat.
  /// Falls back to original string on parse failure (safe but may cause server error).
  String ensureOdooDateFormat(String value) {
    final odooFormat = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$');

    if (odooFormat.hasMatch(value)) {
      return value;
    }

    try {
      final parsed = DateTime.parse(value);
      return DateFormat("yyyy-MM-dd HH:mm:ss").format(parsed);
    } catch (e) {
      return value;
    }
  }

  /// Creates a new `stock.picking` record in Odoo with its move lines (products).
  ///
  /// Expects a map with:
  ///   - partnerId
  ///   - operationTypeId
  ///   - scheduledDate
  ///   - origin
  ///   - moveType
  ///   - userId
  ///   - note
  ///   - products: list of {productName, productId, productUomQty, defaultLocationSrcId?, defaultLocationDestId?}
  ///
  /// Returns the new picking ID on success.
  /// Throws on failure (network, auth, validation error, etc.).
  Future<int> createPicking({required Map<String, dynamic> creates}) async {
    final pickingData = {
      'partner_id': creates['partnerId'],
      'picking_type_id': creates['operationTypeId'],
      'scheduled_date': ensureOdooDateFormat(creates['scheduledDate']),
      'origin': creates['origin'],
      'move_type': creates['moveType'],
      'user_id': creates['userId'],
      'note': creates['note'],
      'move_ids': creates['products'].map((p) {
        return [
          0,
          0,
          {
            'name': p['productName'],
            'product_id': p['productId'],
            'product_uom_qty': p['productUomQty'],
            'location_id': p['defaultLocationSrcId'] ?? 1,
            'location_dest_id': p['defaultLocationDestId'] ?? 1,
          },
        ];
      }).toList(),
    };

    final pickingId = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'create',
      'args': [pickingData],
      'kwargs': {},
    });
    return pickingId as int;
  }
}
