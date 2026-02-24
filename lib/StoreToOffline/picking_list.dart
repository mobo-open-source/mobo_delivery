import 'package:hive/hive.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../NavBars/Pickings/PickingFormPage/services/hive_service.dart';
import '../NavBars/Pickings/PickingListPage/models/picking_model.dart';
import '../core/company/session/company_session_manager.dart';

/// Service that syncs stock picking list data from Odoo to local Hive storage
/// for offline access in the picking list screen.
///
/// Main features:
/// - Fetches pickings with optional filters (date, state, type, search)
/// - Also loads related stock moves
/// - Groups pickings by warehouse name
/// - Stores enriched Picking model objects in Hive
///
/// All fetches are silent on error (catch-all). Consider adding logging.
class pickingListToOffline {
  int? userId;
  OdooClient? client;
  String url = "";

  /// Temporary in-memory grouping: warehouseName → list of picking maps
  Map<String, List<Map<String, dynamic>>> _allPickingsByLocation = {};
  final HiveService _hiveService = HiveService();

  /// Initializes session, Hive, and loads picking data.
  ///
  /// Throws if no active session is found.
  Future<void> initializeOdooClient() async {
    final session = await CompanySessionManager.getCurrentSession();
    if (session == null) throw Exception("No active session");
    await _hiveService.initialize();
    await stockPickings();
  }

  /// Loads stock pickings from Odoo with optional filters and saves them offline.
  ///
  /// Filters are combined into an Odoo domain.
  /// Also fetches related stock moves and picking types.
  ///
  /// Stores result grouped by warehouse → Hive box 'pickings'
  Future<void> stockPickings({
    DateTime? scheduledDate,
    DateTime? deadlineDate,
    String? state,
    String? type,
    String? searchTerm,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getInt('userId') ?? 0;
      int version = prefs.getInt('version') ?? 0;

      await CompanySessionManager.callKwWithCompany({
        'model': 'stock.warehouse',
        'method': 'search_read',
        'args': [
          [
          ],
        ],
        'kwargs': {
          'fields': ['id', 'name'],
        },
      });

      List<List<dynamic>> domain = [];
      if (searchTerm != null && searchTerm.isNotEmpty) {
        domain.add(['name', 'ilike', searchTerm]);
      }
      if (state != null) {
        domain.add(['state', '=', state]);
      }
      if (type != null) {
        domain.add(['picking_type_code', '=', type]);
      }
      if (scheduledDate != null) {
        final dateStrStart =
            "${scheduledDate.year}-${scheduledDate.month.toString().padLeft(2, '0')}-${scheduledDate.day.toString().padLeft(2, '0')} 00:00:00";
        final dateStrEnd =
            "${scheduledDate.year}-${scheduledDate.month.toString().padLeft(2, '0')}-${scheduledDate.day.toString().padLeft(2, '0')} 23:59:59";
        domain.add(['scheduled_date', '>=', dateStrStart]);
        domain.add(['scheduled_date', '<=', dateStrEnd]);
      }
      if (deadlineDate != null && type == 'incoming') {
        final dateStrStart =
            "${deadlineDate.year}-${deadlineDate.month.toString().padLeft(2, '0')}-${deadlineDate.day.toString().padLeft(2, '0')} 00:00:00";
        final dateStrEnd =
            "${deadlineDate.year}-${deadlineDate.month.toString().padLeft(2, '0')}-${deadlineDate.day.toString().padLeft(2, '0')} 23:59:59";
        domain.add(['date_deadline', '>=', dateStrStart]);
        domain.add(['date_deadline', '<=', dateStrEnd]);
      }

      // Fields to fetch from stock.picking
      List<String> pickingFields = [
        'id',
        'name',
        'scheduled_date',
        'date_deadline',
        'picking_type_id',
        'picking_type_code',
        'partner_id',
        'state',
        'move_type',
        'user_id',
        'location_id',
        'location_dest_id',
        'products_availability',
        'origin',
        'show_check_availability',
      ];

      if (version < 19) {
        pickingFields.addAll(['group_id']);
      }

      // Get total count (useful for pagination UI later)
      final pickingCount = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'search_count',
        'args': [domain],
        'kwargs': {},
      });

      await _hiveService.saveTotalCount(pickingCount);

      // Fetch pickings
      final pickingItems = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [domain],
        'kwargs': {'fields': pickingFields},
      });

      final pickingIds =
          (pickingItems as List?)?.map((picking) => picking['id']).toList() ??
          [];

      // Fetch related stock moves
      final moveItems = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [
          [
            ['picking_id', 'in', pickingIds],
          ],
        ],
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

      // Fetch picking types (for warehouse mapping)
      final pickingTypeIds = pickingItems
          ?.map(
            (item) =>
                (item['picking_type_id'] is List &&
                    item['picking_type_id'].isNotEmpty)
                ? item['picking_type_id'][0]
                : null,
          )
          .where((id) => id != null)
          .toSet()
          .toList();

      final pickingTypes = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking.type',
        'method': 'search_read',
        'args': [
          [
            ['id', 'in', pickingTypeIds ?? []],
          ],
        ],
        'kwargs': {
          'fields': ['id', 'name', 'warehouse_id'],
        },
      });

      _allPickingsByLocation.clear();

      final Map<int, dynamic> pickingTypeWarehouseMap = {
        for (var pt in pickingTypes ?? []) pt['id']: pt['warehouse_id'],
      };

      Map<int, List<Map<String, dynamic>>> movesByPickingId = {};
      for (var move in moveItems ?? []) {
        int pickingId = move['picking_id'][0];
        movesByPickingId.putIfAbsent(pickingId, () => []).add({
          'product': move['product_id'] is List ? move['product_id'][1] : '',
          'quantity': move['product_uom_qty'],
          'state': move['state'],
        });
      }

      // Enrich and group pickings
      for (var picking in pickingItems ?? []) {
        int pickingId = picking['id'];
        int pickingTypeId = picking['picking_type_id'][0];
        var warehouse = pickingTypeWarehouseMap[pickingTypeId];

        if (warehouse != null && warehouse.isNotEmpty) {
          String warehouseName = warehouse[1];

          List<dynamic> relatedMoves = (moveItems ?? [])
              .where((move) => move['picking_id'][0] == pickingId)
              .toList();

          _allPickingsByLocation.putIfAbsent(warehouseName, () => []).add({
            'id': pickingId.toString(),
            'scheduled_date': picking['scheduled_date'],
            'date_deadline': (picking['date_deadline'] is String)
                ? picking['date_deadline']
                : '',
            'picking_type_code': picking['picking_type_code'],
            'item': picking['name'],
            'partner_id': picking['partner_id'] is List
                ? picking['partner_id'][1]
                : '',
            'partner_id_int': picking['partner_id'] is List
                ? picking['partner_id'][0].toString()
                : '0',
            'picking_type_id': picking['picking_type_id'] is List
                ? picking['picking_type_id'][1]
                : '',
            'picking_type_id_int': picking['picking_type_id'] is List
                ? picking['picking_type_id'][0].toString()
                : '0',
            'products_availability':
                picking['products_availability']?.toString() ?? '',
            'origin': picking['origin']?.toString() ?? '',
            'return_count': picking['return_count']?.toString() ?? '',
            'show_check_availability':
                picking['show_check_availability']?.toString() ?? '',
            'state': picking['state']?.toString() ?? '',
            'location_id_int': picking['location_id'] is List
                ? picking['location_id'][0].toString()
                : '0',
            'location_dest_id_int': picking['location_dest_id'] is List
                ? picking['location_dest_id'][0].toString()
                : '0',
            'move_ids': relatedMoves,
            'move_type': picking['move_type']?.toString() ?? '',
            'user_id': picking['user_id'] is List ? picking['user_id'][1] : '',
            'user_id_int': picking['user_id'] is List
                ? picking['user_id'][1]
                : '',
            if (version < 19) ...{
              'group_id': picking['group_id'] is List
                  ? picking['group_id'][1]
                  : '',
              'group_id_int': picking['group_id'] is List
                  ? picking['group_id'][0].toString()
                  : '0',
            },
            'company_id': picking['company_id'] is List
                ? picking['company_id'][1]
                : '',
            'company_id_int': picking['company_id'] is List
                ? picking['company_id'][0].toString()
                : '0',
          });
        }
      }
      await storePickingsToHive();
    } catch (e) {
    }
  }

  /// Stores enriched picking data into Hive box 'pickings'
  Future<void> storePickingsToHive() async {
    final box = Hive.box<Picking>('pickings');
    await box.clear();

    for (var entry in _allPickingsByLocation.entries) {
      final warehouse = entry.key;
      for (var picking in entry.value) {
        final p = Picking(
          id: picking['id'],
          item: picking['item'],
          scheduledDate: picking['scheduled_date'] ?? '',
          deadlineDate: picking['date_deadline'] ?? '',
          state: picking['state'],
          partner: picking['partner_id'],
          partnerId: picking['partner_id'] is List
              ? picking['partner_id'][0].toString()
              : '0',
          origin: picking['origin'],
          moveIds: List<Map<String, dynamic>>.from(picking['move_ids'] ?? []),
          warehouseName: warehouse,
          pickingTypeCode: picking['picking_type_code'],
          pickingTypeId: picking['picking_type_id'] is List
              ? picking['picking_type_id'][1]
              : '',
          pickingTypeIdInt: picking['picking_type_id'] is List
              ? picking['picking_type_id'][0].toString()
              : '0',
          productAvailability:
              picking['products_availability']?.toString() ?? '',
          returnCount: picking['return_count']?.toString() ?? '',
          showCheckAvailability:
              picking['show_check_availability']?.toString() ?? '',
          locationIdInt: picking['location_id'] is List
              ? picking['location_id'][0].toString()
              : '0',
          locationDestIdInt: picking['location_dest_id'] is List
              ? picking['location_dest_id'][0].toString()
              : '0',
          moveType: picking['move_type']?.toString() ?? '',
          userId: picking['user_id'] is List ? picking['user_id'][1] : '',
          userIdInt: picking['user_id'] is List ? picking['user_id'][1] : '',
          groupId: picking['group_id'] is List ? picking['group_id'][1] : '',
          groupIdInt: picking['group_id'] is List
              ? picking['group_id'][0].toString()
              : '0',
          companyId: picking['company_id'] is List
              ? picking['company_id'][1]
              : '',
          companyIdInt: picking['company_id'] is List
              ? picking['company_id'][0].toString()
              : '0',
        );
        await box.put(p.id, p);
      }
    }
  }
}
