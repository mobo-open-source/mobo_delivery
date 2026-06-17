import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/company/session/company_session_manager.dart';
import '../models/picking_form.dart';
import '../models/product.dart';
import '../models/partner.dart';
import '../models/user.dart';
import '../models/stock_move.dart';
import 'hive_service.dart';

/// Service responsible for all Odoo RPC interactions related to stock pickings,
/// products, partners, users, and move lines in the picking form flow.
///
/// Features:
/// • Offline-aware: caches fetched data in Hive when online
/// • Version-aware: handles Odoo 19+ changes (e.g. stock.move 'name' field removal)
/// • Connectivity check before most operations
/// • Queues actions (validate, cancel, create, update) via Hive when offline
///
/// All methods are designed to fail gracefully (return empty list/false/null)
/// and log errors internally — UI should handle empty/error states.
class OdooPickingFormService {
  String url = "";
  int? userId;
  final HiveService _hiveService = HiveService();

  /// Initializes Odoo session — must be called before any RPC call
  ///
  /// Loads current session from `CompanySessionManager`.
  /// Throws exception if no active session exists.
  Future<void> initializeOdooClient() async {
    final session = await CompanySessionManager.getCurrentSession();
    if (session == null) throw Exception("No active session");
  }

  /// Checks both device connectivity and Odoo server reachability
  ///
  /// 1. Uses `connectivity_plus` to detect any network
  /// 2. Performs quick GET to `$url/web` with 5-second timeout
  /// 3. Stores latest URL from SharedPreferences
  ///
  /// Returns `true` only if both network exists and server responds 200 OK.
  /// Returns `true` when the device has a working internet connection.
  ///
  /// Two cheap checks, no Odoo-server round trip:
  ///   1. `connectivity_plus` — does the device have any active link
  ///      (Wi-Fi / mobile / ethernet)?
  ///   2. DNS lookup of a stable host (3s timeout) — does that link
  ///      actually reach the internet (catches captive portals etc.)?
  ///
  /// Previously this method pinged `<url>/web` with a 5s timeout. That
  /// caused false-negative "offline" classifications whenever the Odoo
  /// server was momentarily slow or returned a non-200 — pushing actions
  /// like cancel/validate into the offline-queue branch even on a live
  /// connection. The actual RPC that follows still surfaces real server
  /// failures via its own error handling, so checking server-side health
  /// up front isn't needed.
  Future<bool> checkNetworkConnectivity() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (!connectivityResult.any((r) => r != ConnectivityResult.none)) {
        return false;
      }
      final result = await InternetAddress.lookup('example.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Loads a single picking by ID with all necessary fields
  ///
  /// Fetches detailed picking record from `stock.picking` model.
  /// Field list is version-aware (adds `group_id` for < v19).
  /// On success: caches the picking in Hive.
  ///
  /// Returns list with one `PickingForm` or empty list on failure/error.
  Future<List<PickingForm>> loadPickings(int pickingId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getInt('userId') ?? 0;
      int version = prefs.getInt('version') ?? 0;

      List<String> pickingFields = [
        'id',
        'name',
        'partner_id',
        'picking_type_id',
        'scheduled_date',
        'date_deadline',
        'date_done',
        'products_availability',
        'origin',
        'state',
        'note',
        'move_type',
        'user_id',
        'company_id',
        'return_count',
        'return_ids',
        'show_check_availability',
        'picking_type_code',
        'location_id',
        'location_dest_id',
      ];
      if (version < 19) {
        pickingFields.addAll(['group_id']);
      }
      final pickingsItems =
          await CompanySessionManager.callKwWithCompany({
                'model': 'stock.picking',
                'method': 'search_read',
                'args': [
                  [
                    ['id', '=', pickingId],
                  ],
                ],
                'kwargs': {'fields': pickingFields},
              })
              as List<dynamic>?;

      if (pickingsItems != null) {
        await _hiveService.savePickings(
          List<Map<String, dynamic>>.from(pickingsItems),
        );
        return pickingsItems.map((item) => PickingForm.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Loads all visible products (`product.product`) from Odoo
  ///
  /// No domain filter — fetches everything the user has access to.
  /// Caches full list in Hive on success.
  ///
  /// Returns parsed `Product` list or empty on error.
  Future<List<Product>> loadProducts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getInt('userId') ?? 0;

      final List<Map<String, dynamic>> productItems =
          (await CompanySessionManager.callKwWithCompany({
            'model': 'product.product',
            'method': 'search_read',
            'args': [[]],
            'kwargs': {
              'fields': ['id', 'display_name', 'uom_id'],
            },
          }))?.cast<Map<String, dynamic>>() ??
          [];

      if (productItems.isNotEmpty) {
        await _hiveService.saveProducts(productItems);
        return productItems.map((item) => Product.fromJson(item)).toList();
      }
      return await _hiveService.getProducts();
    } catch (e) {
      debugPrint('loadProducts error: $e');
      return await _hiveService.getProducts();
    }
  }

  /// Loads active `stock.picking.type` records (Operation Types) and
  /// caches them for offline use. Returns maps shaped for
  /// `InfoRow.dropdownItems` with `id`, `name` (display_name), and
  /// flattened default source / destination location ids.
  Future<List<Map<String, dynamic>>> loadOperationTypes() async {
    try {
      final result = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking.type',
        'method': 'search_read',
        'args': [
          [
            ['active', '=', true],
          ],
        ],
        'kwargs': {
          'fields': [
            'id',
            'display_name',
            'default_location_src_id',
            'default_location_dest_id',
          ],
        },
      });

      final rows = (result as List?)?.cast<Map<String, dynamic>>() ??
          const <Map<String, dynamic>>[];

      int? extractId(dynamic raw) {
        if (raw is List && raw.isNotEmpty && raw.first is int) {
          return raw.first as int;
        }
        return null;
      }

      final normalised = rows.map<Map<String, dynamic>>((row) {
        final raw = row['display_name'];
        final display = (raw is String && raw.isNotEmpty) ? raw : row['name'];
        return {
          'id': row['id'],
          'name': display,
          'default_location_src_id': row['default_location_src_id'],
          'default_location_dest_id': row['default_location_dest_id'],
          'default_location_src_id_int':
              extractId(row['default_location_src_id']),
          'default_location_dest_id_int':
              extractId(row['default_location_dest_id']),
        };
      }).toList();

      if (normalised.isNotEmpty) {
        await _hiveService.saveOperationTypes(normalised);
      }
      return normalised.isNotEmpty ? normalised : await loadOperationTypesFromCache();
    } catch (e) {
      debugPrint('loadOperationTypes error: $e');
      return await loadOperationTypesFromCache();
    }
  }

  /// Loads operation types from the local Hive cache, used as the
  /// offline fallback for the operation type dropdown.
  Future<List<Map<String, dynamic>>> loadOperationTypesFromCache() async {
    final cached = await _hiveService.getOperationTypes();
    return cached
        .map<Map<String, dynamic>>((o) => {
              'id': o.id,
              'name': o.name,
              'default_location_src_id_int': o.defaultLocationSrcId,
              'default_location_dest_id_int': o.defaultLocationDestId,
            })
        .toList();
  }

  /// Loads all visible partners (`res.partner`) — customers, suppliers, contacts
  ///
  /// No domain — returns everything accessible to current user.
  /// Saves to Hive for offline use.
  Future<List<Partner>> loadPartners() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getInt('userId') ?? 0;
      final partnerItems =
          await CompanySessionManager.callKwWithCompany({
                'model': 'res.partner',
                'method': 'search_read',
                'args': [[]],
                'kwargs': {
                  'fields': ['id', 'display_name'],
                },
              })
              as List<dynamic>?;

      if (partnerItems != null && partnerItems.isNotEmpty) {
        await _hiveService.savePartners(
          List<Map<String, dynamic>>.from(partnerItems),
        );
        return partnerItems.map((item) => Partner.fromJson(item)).toList();
      }
      return await _hiveService.getPartners();
    } catch (e) {
      debugPrint('loadPartners error: $e');
      return await _hiveService.getPartners();
    }
  }

  /// Loads detailed address + image for a single partner
  ///
  /// Fetches specific fields: street, city, zip, state, country, image_1920.
  /// Builds formatted address string from parts.
  ///
  /// Returns map with `address` and `image_1920` or `null` on failure.
  Future<Map<String, dynamic>?> loadPartnerDetails(id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getInt('userId') ?? 0;

      final partnerItems =
          await CompanySessionManager.callKwWithCompany({
                'model': 'res.partner',
                'method': 'search_read',
                'args': [
                  [
                    ['id', '=', id],
                  ],
                ],
                'kwargs': {
                  'fields': [
                    'id',
                    'display_name',
                    'street',
                    'street2',
                    'city',
                    'state_id',
                    'zip',
                    'country_id',
                    'image_1920',
                  ],
                  'limit': 1,
                },
              })
              as List<dynamic>?;

      if (partnerItems != null && partnerItems.isNotEmpty) {
        final partner = partnerItems.first;
        final addressParts =
            [
                  partner['street'],
                  partner['street2'],
                  partner['city'],
                  partner['zip'],
                  partner['state_id'] != null ? partner['state_id'][1] : null,
                  partner['country_id'] != null
                      ? partner['country_id'][1]
                      : null,
                ]
                .where(
                  (part) => part != null && part.toString().trim().isNotEmpty,
                )
                .toList();

        final address = addressParts.isNotEmpty ? addressParts.join(', ') : '';
        final image = partner['image_1920'];

        return {'address': address, 'image_1920': image};
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Loads all visible users (`res.users`)
  ///
  /// Used mainly for assigning responsible user to pickings.
  /// Caches full list in Hive.
  Future<List<User>> loadUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getInt('userId') ?? 0;
      final userItems =
          await CompanySessionManager.callKwWithCompany({
                'model': 'res.users',
                'method': 'search_read',
                'args': [[]],
                'kwargs': {
                  'fields': ['id', 'display_name'],
                },
              })
              as List<dynamic>?;
      if (userItems != null) {
        await _hiveService.saveUsers(
          List<Map<String, dynamic>>.from(userItems),
        );
        return userItems.map((item) => User.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Loads all stock moves belonging to a picking.
  ///
  /// Filters by `picking_id == pickingId` and caches results in Hive.
  ///
  /// Field notes:
  ///   • `product_uom`  — Many2one UoM on stock.move (NOT product_uom_id)
  ///   • `quantity`     — done/reserved qty in Odoo 16+ (quantity_done was removed)
  ///   • `lot_id` and `quantity_product_uom` live on stock.move.line, not stock.move
  ///
  /// Throws on RPC failure so the caller can surface the error to the user.
  Future<List<StockMove>> loadProductMoves(int pickingId) async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getInt('userId') ?? 0;

    try {
      final moveItems =
          await CompanySessionManager.callKwWithCompany({
                'model': 'stock.move',
                'method': 'search_read',
                'args': [
                  [
                    ['picking_id', '=', pickingId],
                  ],
                ],
                'kwargs': {
                  'fields': [
                    'id',
                    'product_id',
                    'product_uom_qty',
                    'product_uom',
                    'quantity',
                    'picking_id',
                    'location_id',
                  ],
                },
              })
              as List<dynamic>?;

      if (moveItems != null) {
        await _hiveService.saveStockMoves(
          List<Map<String, dynamic>>.from(moveItems),
        );
        return moveItems.map((item) => StockMove.fromJson(item)).toList();
      }
      return [];
    } catch (e, st) {
      debugPrint('[OdooPickingFormService.loadProductMoves] '
          'picking=$pickingId ERROR: $e\n$st');
      rethrow;
    }
  }

  /// Loads detailed move lines (`stock.move.line`) for a picking
  ///
  /// Fetches product, source location, lot/serial, done quantity.
  /// Used in detailed operations view.
  ///
  /// Returns raw list of maps or empty on error.
  Future<List<Map<String, dynamic>>> loadStockMoveLines(int pickingId) async {
    try {
      final moveLines = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.move.line',
        'method': 'search_read',
        'args': [
          [
            ['picking_id', '=', pickingId],
          ],
        ],
        'kwargs': {
          'fields': [
            'product_id',
            'location_id',
            'lot_id',
            'quantity_product_uom',
          ],
        },
      });

      return List<Map<String, dynamic>>.from(moveLines ?? []);
    } catch (e) {
      return [];
    }
  }

  /// Loads return pickings (reverse transfers) linked to this picking
  ///
  /// First reads `return_ids` from source picking, then fetches those records.
  /// Returns minimal fields: name, partner, scheduled date, origin, state.
  Future<List<Map<String, dynamic>>> loadReturnPickings(int pickingId) async {
    try {
      final returnData = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [
          [
            ['id', '=', pickingId],
          ],
        ],
        'kwargs': {
          'fields': ['return_ids'],
        },
      });

      if (returnData != null && returnData.isNotEmpty) {
        final List<dynamic> returnIds = returnData[0]['return_ids'] ?? [];
        if (returnIds.isNotEmpty) {
          final returnFilteredData =
              await CompanySessionManager.callKwWithCompany({
                'model': 'stock.picking',
                'method': 'search_read',
                'args': [
                  [
                    ['id', 'in', returnIds],
                  ],
                ],
                'kwargs': {
                  'fields': [
                    'name',
                    'partner_id',
                    'scheduled_date',
                    'origin',
                    'state',
                  ],
                },
              });
          return List<Map<String, dynamic>>.from(returnFilteredData ?? []);
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Updates an existing stock move's product and quantity. Locations
  /// are intentionally not written — the move inherits them from its
  /// picking. Throws on RPC failure.
  Future<void> updateProductMove(
    int moveId,
    int productId,
    double quantity,
  ) async {
    await CompanySessionManager.callKwWithCompany({
      'model': 'stock.move',
      'method': 'write',
      'args': [
        [moveId],
        {
          'product_id': productId,
          'quantity': quantity,
        },
      ],
      'kwargs': {},
    });
  }

  /// Deletes a stock move line from the picking
  ///
  /// Uses `unlink()` on `stock.move`.
  /// Returns `true` if operation succeeded.
  Future<bool> deleteProductMove(int moveId, int pickingId) async {
    try {
      final response = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.move',
        'method': 'unlink',
        'args': [
          [moveId],
        ],
        'kwargs': {},
      });
      return response != null;
    } catch (e) {
      return false;
    }
  }

  /// Validates (processes) the picking — equivalent to "Validate" button
  ///
  /// Calls `stock.picking.button_validate()`.
  /// May return a wizard action (Map) — backorder, immediate transfer,
  /// SMS confirmation, scrap warning, etc. — when Odoo needs user input.
  /// Returns `true` on a direct success, the action Map when a wizard is
  /// needed, and rethrows the original exception on failure so the caller
  /// can surface the actual Odoo UserError text.
  Future<dynamic> validatePicking(int pickingId) async {
    final validate = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'button_validate',
      'args': [
        [pickingId],
      ],
      'kwargs': {},
    });

    if (validate is Map &&
        (validate['type'] == 'ir.actions.act_window' ||
            validate['type'] == 'ir.actions.client')) {
      return validate;
    }

    return validate == null || validate == true || validate is! Map;
  }

  /// Triggers stock reservation / availability check
  ///
  /// Calls `action_assign()` on the picking.
  /// Updates reserved quantities if possible.
  Future<bool> checkAvailability(int pickingId) async {
    try {
      final validate = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'action_assign',
        'args': [
          [pickingId],
        ],
        'kwargs': {},
      });
      return validate != null;
    } catch (e) {
      return false;
    }
  }

  /// Confirms the picking (moves from Draft → Waiting/Ready).
  ///
  /// Calls `action_confirm()`. Odoo returns `True` on success — older builds
  /// returned `None`. We treat both as a clean confirm and also pass
  /// through wizard responses (rare for confirm but possible via custom
  /// modules). Throws on RPC failure so the caller can surface the actual
  /// UserError instead of a generic "Failed" snackbar.
  Future<dynamic> markAsTodoPicking(int pickingId) async {
    final confirm = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'action_confirm',
      'args': [
        [pickingId],
      ],
      'kwargs': {},
    });

    if (confirm is Map &&
        (confirm['type'] == 'ir.actions.act_window' ||
            confirm['type'] == 'ir.actions.client')) {
      return confirm;
    }
    return confirm == null || confirm == true || confirm is! Map;
  }

  /// Cancels the entire picking via `action_cancel()`. Throws on failure so
  /// the caller can surface the actual Odoo error (e.g. a wizard prompt
  /// requesting confirmation for cancelling done moves).
  Future<dynamic> cancelPicking(int pickingId) async {
    final cancel = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'action_cancel',
      'args': [
        [pickingId],
      ],
      'kwargs': {},
    });

    if (cancel is Map &&
        (cancel['type'] == 'ir.actions.act_window' ||
            cancel['type'] == 'ir.actions.client')) {
      return cancel;
    }
    return cancel == null || cancel == true || cancel is! Map;
  }

  /// Adds a new stock move line to the picking. Version-aware: Odoo 19
  /// dropped the `name` field on `stock.move`. Throws on RPC failure so
  /// the caller can surface the error.
  ///
  /// Bug fix: for pickings already past draft (confirmed/waiting/assigned),
  /// a bare `stock.move.create` leaves the new move in `draft` state. The
  /// picking form view in Odoo filters its operations table on confirmed
  /// moves, so the freshly-created draft move never shows up in the web
  /// backend until the picking is re-fetched and the state is recomputed.
  /// Subsequent picking-level actions (`action_confirm`, `button_validate`)
  /// also raise UserErrors because they refuse to touch an orphaned draft
  /// move attached to a non-draft picking.
  ///
  /// To match the Odoo form-view workflow we transition the new move into
  /// the same state family as the picking by calling `_action_confirm` on
  /// it. This also runs Odoo's merge logic (duplicate-product lines get
  /// summed into a single move), triggers reservations on assigned
  /// pickings, and makes the move immediately visible everywhere.
  Future<int> addProductToLine(
    int pickingId,
    int productId,
    String productName,
    int selectedPickingUom,
    double quantity,
    int locationId,
    int locationDestId, {
    String? pickingState,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final int version = prefs.getInt('version') ?? 0;

    final pickingRead = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'read',
      'args': [
        [pickingId],
        ['company_id', 'location_id', 'location_dest_id'],
      ],
      'kwargs': {},
    });

    int? freshCompanyId;
    int freshLocationId = locationId;
    int freshLocationDestId = locationDestId;
    if (pickingRead is List && pickingRead.isNotEmpty) {
      final row = pickingRead.first as Map<String, dynamic>;
      int? extractId(dynamic raw) {
        if (raw is List && raw.isNotEmpty && raw.first is int) {
          return raw.first as int;
        }
        return null;
      }
      freshCompanyId = extractId(row['company_id']);
      freshLocationId = extractId(row['location_id']) ?? locationId;
      freshLocationDestId =
          extractId(row['location_dest_id']) ?? locationDestId;
    }

    final payload = <String, dynamic>{
      if (version < 19) 'name': productName,
      'product_id': productId,
      'product_uom_qty': quantity,
      'product_uom': selectedPickingUom,
      'picking_id': pickingId,
      'location_id': freshLocationId,
      'location_dest_id': freshLocationDestId,
      if (freshCompanyId != null) 'company_id': freshCompanyId,
    };

    final createMove = await CompanySessionManager.callKwWithCompany(
      {
        'model': 'stock.move',
        'method': 'create',
        'args': [payload],
        'kwargs': {},
      },
      companyId: freshCompanyId,
    );

    int? newMoveId;
    if (createMove is int) newMoveId = createMove;
    if (createMove is List && createMove.isNotEmpty && createMove.first is int) {
      newMoveId = createMove.first as int;
    }
    if (newMoveId == null) {
      throw Exception(
        'Odoo did not return a valid stock.move id (got: $createMove)',
      );
    }

    const stateNeedsConfirm = {'confirmed', 'waiting', 'partially_available', 'assigned'};
    if (pickingState != null && stateNeedsConfirm.contains(pickingState)) {
      try {
        await CompanySessionManager.callKwWithCompany(
          {
            'model': 'stock.picking',
            'method': 'action_confirm',
            'args': [
              [pickingId],
            ],
            'kwargs': {},
          },
          companyId: freshCompanyId,
        );
      } catch (e) {
        debugPrint(
          '[addProductToLine] action_confirm failed for picking=$pickingId: $e',
        );
        rethrow;
      }
    }

    return newMoveId;
  }

  /// Fetches the source and destination location IDs for a given
  /// picking. Either may be `null` if the picking has no value set.
  Future<({int? locationId, int? locationDestId})> getPickingLocations(
    int pickingId,
  ) async {
    final result = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'read',
      'args': [
        [pickingId],
        ['location_id', 'location_dest_id'],
      ],
      'kwargs': {},
    });

    if (result is! List || result.isEmpty) {
      throw Exception('Picking $pickingId not found');
    }
    final row = result.first as Map<String, dynamic>;

    int? extractId(dynamic raw) {
      if (raw is List && raw.isNotEmpty && raw.first is int) {
        return raw.first as int;
      }
      return null;
    }

    return (
      locationId: extractId(row['location_id']),
      locationDestId: extractId(row['location_dest_id']),
    );
  }

  /// Saves changes to picking header fields
  ///
  /// Calls `stock.picking.write()` with the updates map.
  /// Returns `true` if write succeeded.
  Future<bool> saveChanges(int pickingId, Map<String, dynamic> updates) async {
    debugPrint(
      '[PickingForm.saveChanges] id=$pickingId fields=${updates.keys.toList()}',
    );
    try {
      final response = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'write',
        'args': [
          [pickingId],
          updates,
        ],
        'kwargs': {},
      });
      debugPrint(
        '[PickingForm.saveChanges] id=$pickingId response=$response',
      );
      return response == true;
    } catch (e, st) {
      debugPrint('[PickingForm.saveChanges] id=$pickingId ERROR: $e\n$st');
      return false;
    }
  }
}
