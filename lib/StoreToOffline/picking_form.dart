import 'package:hive/hive.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../NavBars/Pickings/PickingFormPage/models/move_line.dart';
import '../NavBars/Pickings/PickingFormPage/models/return_picking.dart';
import '../NavBars/Pickings/PickingFormPage/services/hive_service.dart';
import '../core/company/session/company_session_manager.dart';

/// Service that syncs essential picking-related data from Odoo to local Hive storage
/// so the picking form can work offline (or with very poor connectivity).
///
/// Currently caches:
/// - Partners (customers/suppliers)
/// - Users (employees)
/// - Products
/// - Operation Types (picking types)
/// - Stock Moves
/// - Stock Pickings
/// - Stock Move Lines
/// - Return pickings (linked via return_ids)
///
/// All methods are silent on error (catch-all) — consider adding logging in production.
class PickingFormToOffline {
  int? userId;
  OdooClient? client;
  String url = "";
  final HiveService _hiveService = HiveService();

  /// Initializes Odoo session, Hive, and triggers full data sync.
  ///
  /// Throws if no active session exists.
  Future<void> initializeOdooClient() async {
    final session = await CompanySessionManager.getCurrentSession();
    if (session == null) throw Exception("No active session");
    await _hiveService.initialize();
    await loadPickings();
    await loadProducts();
    await loadPartners();
    await loadUsers();
    await loadProductMoves();
    await loadOperationTypes();
    await loadStockMoveLines();
    await loadAndCacheReturnPickings();
  }

  Future<void> loadPartners() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getInt('userId') ?? 0;

      final partnerItems = await CompanySessionManager.callKwWithCompany({
        'model': 'res.partner',
        'method': 'search_read',
        'args': [[]],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'street',
            'city',
            'zip',
            'state_id',
            'country_id',
          ],
        },
      });

      if (partnerItems != null) {
        await _hiveService.savePartners(
          List<Map<String, dynamic>>.from(partnerItems),
        );
      }
    } catch (e) {}
  }

  Future<void> loadUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getInt('userId') ?? 0;

      final userItems = await CompanySessionManager.callKwWithCompany({
        'model': 'res.users',
        'method': 'search_read',
        'args': [
          [
            ['active', '=', true],
          ],
        ],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'image_1920',
            'phone',
            'email',
            'company_id',
            'contact_address',
          ],
        },
      });

      if (userItems != null) {
        await _hiveService.saveUsers(
          List<Map<String, dynamic>>.from(userItems),
        );
      }
    } catch (e) {}
  }

  Future<void> loadProducts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getInt('userId') ?? 0;

      final productItems = await CompanySessionManager.callKwWithCompany({
        'model': 'product.product',
        'method': 'search_read',
        'args': [[]],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'default_code',
            'list_price',
            'standard_price',
            'uom_id',
          ],
        },
      });

      if (productItems != null) {
        await _hiveService.saveProducts(
          List<Map<String, dynamic>>.from(productItems),
        );
      }
    } catch (e) {}
  }

  Future<void> loadOperationTypes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getInt('userId') ?? 0;

      final operationTypeItems = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking.type',
        'method': 'search_read',
        'args': [[]],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'default_location_src_id',
            'default_location_dest_id',
          ],
        },
      });

      if (operationTypeItems != null) {
        await _hiveService.saveOperationTypes(
          List<Map<String, dynamic>>.from(operationTypeItems),
        );
      }
    } catch (e) {}
  }

  Future<void> loadProductMoves() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getInt('userId') ?? 0;

      final moveItems = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [[]],
        'kwargs': {
          'fields': [
            'id',
            'product_id',
            'product_uom_qty',
            'product_uom',
            'picking_id',
            'state',
          ],
        },
      });

      if (moveItems != null) {
        await _hiveService.saveStockMoves(
          List<Map<String, dynamic>>.from(moveItems),
        );
      }
    } catch (e) {}
  }

  Future<void> loadPickings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getInt('userId') ?? 0;

      final pickingItems = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [],
        'kwargs': {},
      });

      if (pickingItems != null) {
        await _hiveService.savePickings(
          List<Map<String, dynamic>>.from(pickingItems),
        );
      }
    } catch (e) {}
  }

  Future<void> loadStockMoveLines() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getInt('userId') ?? 0;

      final moveLines = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.move.line',
        'method': 'search_read',
        'args': [[]],
        'kwargs': {
          'fields': [
            'picking_id',
            'product_id',
            'location_id',
            'lot_id',
            'quantity_product_uom',
          ],
        },
      });

      if (moveLines != null) {
        final List<Map<String, dynamic>> moveLinesList =
            List<Map<String, dynamic>>.from(moveLines);

        final box = await Hive.openBox<MoveLine>('move_lines');

        for (var line in moveLinesList) {
          final pickingValue = line['picking_id'];
          final pickingId = (pickingValue is List && pickingValue.isNotEmpty)
              ? pickingValue[0]
              : 0;

          final moveLine = MoveLine(
            id: line['id'] ?? 0,
            pickingId: pickingId,
            data: line,
          );

          await box.put('${pickingId}_${line['id'] ?? 0}', moveLine);
        }
      }
    } catch (e) {}
  }

  /// Loads return pickings and caches them keyed by original picking ID.
  Future<void> loadAndCacheReturnPickings() async {
    final box = await Hive.openBox<ReturnPicking>('return_pickings');

    try {
      // Step 1: Get all pickings and their return_ids
      final returnData = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [[]],
        'kwargs': {
          'fields': ['id', 'return_ids'],
        },
      });

      if (returnData == null || returnData.isEmpty) return;

      for (var picking in returnData) {
        final pickingId = picking['id'] ?? 0;
        final List<dynamic> returnIds = picking['return_ids'] ?? [];
        if (returnIds.isEmpty) continue;

        // Step 2: Fetch details of return pickings
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
                  'id',
                  'name',
                  'partner_id',
                  'scheduled_date',
                  'origin',
                  'state',
                ],
              },
            });

        if (returnFilteredData == null) continue;

        for (var data in returnFilteredData) {
          final partner = data['partner_id'] as List<dynamic>? ?? [0, ''];
          final returnPicking = ReturnPicking(
            id: data['id'] ?? 0,
            pickingId: pickingId ?? 0,
            name: data['name'] ?? '',
            partnerId: partner.isNotEmpty ? partner[0] : 0,
            scheduledDate: data['scheduled_date'] ?? '',
            origin: data['origin'] ?? '',
            state: data['state'] ?? '',
            data: data,
          );

          // Key by original picking ID (overwrites if multiple returns)
          await box.put('${pickingId}', returnPicking);
        }
      }
    } catch (e) {}
  }
}
