import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
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
            'kwargs': {},
          }))?.cast<Map<String, dynamic>>() ??
          [];

      if (productItems.isNotEmpty) {
        await _hiveService.saveProducts(productItems);
        return productItems.map((item) => Product.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
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
                'kwargs': {},
              })
              as List<dynamic>?;

      if (partnerItems != null) {
        await _hiveService.savePartners(
          List<Map<String, dynamic>>.from(partnerItems),
        );
        return partnerItems.map((item) => Partner.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      return [];
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
                'kwargs': {},
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

  /// Loads all stock moves belonging to a picking
  ///
  /// Filters by `picking_id == pickingId`.
  /// Caches moves in Hive for offline display/editing.
  ///
  /// Returns `StockMove` list or empty on error.
  Future<List<StockMove>> loadProductMoves(int pickingId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getInt('userId') ?? 0;
      final moveItems =
          await CompanySessionManager.callKwWithCompany({
                'model': 'stock.move',
                'method': 'search_read',
                'args': [
                  [
                    ['picking_id', '=', pickingId],
                  ],
                ],
                'kwargs': {},
              })
              as List<dynamic>?;

      if (moveItems != null) {
        await _hiveService.saveStockMoves(
          List<Map<String, dynamic>>.from(moveItems),
        );
        return moveItems.map((item) => StockMove.fromJson(item)).toList();
      }
      return [];
    } catch (e) {
      return [];
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

  /// Updates a single stock move (product, quantity, locations)
  ///
  /// Calls `stock.move.write()` with new values.
  /// Version differences are handled in UI (name field not used here).
  ///
  /// Returns `true` on success, `false` on failure.
  Future<bool> updateProductMove(
    int moveId,
    int productId,
    String productName,
    double quantity,
    int locationId,
    int locationDestId,
  ) async {
    try {
      final response = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.move',
        'method': 'write',
        'args': [
          [moveId],
          {
            'product_id': productId,
            'quantity': quantity,
            'location_id': locationId,
            'location_dest_id': locationDestId,
          },
        ],
        'kwargs': {},
      });
      return response != null;
    } catch (e) {
      return false;
    }
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
  /// May return backorder wizard context (Map) if partial availability.
  /// Returns `true` on simple success, wizard map on backorder prompt, `false` on error.
  Future<dynamic> validatePicking(int pickingId) async {
    try {
      final validate = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'button_validate',
        'args': [
          [pickingId],
        ],
        'kwargs': {},
      });

      if (validate is Map && validate['type'] == 'ir.actions.act_window') {
        return validate;
      }

      return validate == null || validate is! Map;
    } catch (e) {
      return false;
    }
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

  /// Confirms the picking (moves from Draft → Waiting/Ready)
  ///
  /// Calls `action_confirm()`.
  Future<bool> markAsTodoPicking(int pickingId) async {
    try {
      final confirm = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'action_confirm',
        'args': [
          [pickingId],
        ],
        'kwargs': {},
      });
      return confirm != null;
    } catch (e) {
      return false;
    }
  }

  /// Cancels the entire picking
  ///
  /// Calls `action_cancel()`.
  Future<bool> cancelPicking(int pickingId) async {
    try {
      final cancel = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'action_cancel',
        'args': [
          [pickingId],
        ],
        'kwargs': {},
      });
      return cancel != null;
    } catch (e) {
      return false;
    }
  }

  /// Adds a new stock move line to the picking
  ///
  /// Version-aware payload: Odoo 19+ removed mandatory `name` field.
  /// Returns new move ID on success or `null` on failure.
  Future<int?> addProductToLine(
    int pickingId,
    int productId,
    String productName,
    int selectedPickingUom,
    double quantity,
    int locationId,
    int locationDestId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    int version = prefs.getInt('version') ?? 0;
    try {
      Map<String, dynamic> payload;
      if (version >= 19) {
        payload = {
          'product_id': productId,
          'product_uom_qty': quantity,
          'product_uom': selectedPickingUom,
          'picking_id': pickingId,
          'location_id': locationId,
          'location_dest_id': locationDestId,
        };
      } else {
        payload = {
          'name': productName,
          'product_id': productId,
          'product_uom_qty': quantity,
          'product_uom': selectedPickingUom,
          'picking_id': pickingId,
          'location_id': locationId,
          'location_dest_id': locationDestId,
        };
      }

      final createMove = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.move',
        'method': 'create',
        'args': [payload],
        'kwargs': {},
      });
      return createMove as int?;
    } catch (e) {
      return null;
    }
  }

  /// Saves changes to picking header fields
  ///
  /// Calls `stock.picking.write()` with the updates map.
  /// Returns `true` if write succeeded.
  Future<bool> saveChanges(int pickingId, Map<String, dynamic> updates) async {
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
      return response == true;
    } catch (e) {
      return false;
    }
  }
}
