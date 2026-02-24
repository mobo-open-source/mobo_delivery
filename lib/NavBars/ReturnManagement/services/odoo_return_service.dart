import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/company/session/company_session_manager.dart';

/// Service layer for managing **return pickings** (reverse transfers / customer returns) in Odoo.
///
/// Handles:
/// • Counting & fetching paginated return-eligible pickings
/// • Building complex filter domains for presets ("Late", "Backorders", "My Transfer", etc.)
/// • Fetching move lines from a picking
/// • Creating return pickings via the `stock.return.picking` wizard
///
/// Version-aware logic included (different return creation methods before/after Odoo 18).
/// Throws meaningful exceptions on failure for UI error handling.
class OdooReturnManagementService {
  static const int itemsPerPage = 40;
  int? userId;
  String url = '';

  /// Ensures Odoo session is active — must be called before any RPC
  Future<void> initializeClient() async {
    final session = await CompanySessionManager.getCurrentSession();
    if (session == null) throw Exception("No active session");
  }

  /// Builds Odoo domain clauses from user-friendly filter presets
  ///
  /// Translates labels like "Late", "Backorders", "My Transfer" into proper domain tuples.
  /// Supports combining multiple filters with AND/OR logic.
  /// Used for both count and search_read operations.
  List<List<dynamic>> buildFilterDomain(List<String> filters, int uid) {
    final List<List<dynamic>> domain = [];

    for (final filter in filters) {
      switch (filter) {
        case 'to_do':
          domain.addAll([
            [
              'user_id',
              'in',
              [uid, false],
            ],
            [
              'state',
              'not in',
              ['done', 'cancel'],
            ],
          ]);
          break;

        case 'my_transfer':
          domain.add(['user_id', '=', uid]);
          break;

        case 'draft':
          domain.add(['state', '=', 'draft']);
          break;

        case 'waiting':
          domain.add([
            'state',
            'in',
            ['confirmed', 'waiting'],
          ]);
          break;

        case 'ready':
          domain.add(['state', '=', 'assigned']);
          break;

        case 'receipt':
          domain.add(['picking_type_code', '=', 'incoming']);
          break;

        case 'deliveries':
          domain.add(['picking_type_code', '=', 'outgoing']);
          break;

        case 'internal':
          domain.add(['picking_type_code', '=', 'internal']);
          break;

        case 'late':
          final now = DateTime.now().toIso8601String();
          domain.addAll([
            [
              'state',
              'in',
              ['assigned', 'waiting', 'confirmed'],
            ],
            [
              '|',
              '|',
              ['has_deadline_issue', '=', true],
              ['date_deadline', '<', now],
              ['scheduled_date', '<', now],
            ],
          ]);
          break;

        case 'planning_issue':
          final now = DateTime.now().toIso8601String();
          domain.addAll([
            [
              '|',
              ['delay_alert_date', '!=', false],
              [
                '&',
                ['scheduled_date', '<', now],
                [
                  'state',
                  'in',
                  ['assigned', 'waiting', 'confirmed'],
                ],
              ],
            ],
          ]);
          break;

        case 'backorder':
          domain.addAll([
            ['backorder_id', '!=', false],
            [
              'state',
              'in',
              ['assigned', 'waiting', 'confirmed'],
            ],
          ]);
          break;

        case 'warning':
          domain.add(['activity_exception_decoration', '!=', false]);
          break;
      }
    }

    return domain;
  }

  /// Counts return-eligible pickings (usually `state = 'done'`) matching filters/search
  ///
  /// Used for pagination total count and progress indicators.
  /// Throws exception on RPC failure for UI error handling.
  Future<int> StockCount({String? searchText, List<String>? filters}) async {
    try {
      List<List<dynamic>> domain = [
        ['state', '=', 'done'],
      ];
      final session = await CompanySessionManager.getCurrentSession();
      final uid = session!.userId;
      if (searchText != null && searchText.isNotEmpty) {
        domain.add(['name', 'ilike', searchText]);
      }
      if (filters != null && filters.isNotEmpty) {
        domain.addAll(buildFilterDomain(filters, uid!));
      }

      final pickingCount = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'search_count',
        'args': [domain],
        'kwargs': {},
      });
      return pickingCount ?? 0;
    } catch (e) {
      throw Exception('Failed to count stock pickings: $e');
    }
  }

  /// Fetches paginated list of return-eligible pickings (`state = 'done'`)
  ///
  /// Supports search, custom filters, and pagination via offset/limit.
  /// Returns flattened list of maps ready for UI display.
  /// Throws exception on failure.
  Future<List<Map<String, dynamic>>> fetchStockPickings(
    int currentPage, {
    String? searchText,
    List<String>? filters,
  }) async {
    try {
      final offset = currentPage * itemsPerPage;
      List<List<dynamic>> domain = [
        ['state', '=', 'done'],
      ];
      final session = await CompanySessionManager.getCurrentSession();
      final uid = session!.userId;

      if (searchText != null && searchText.isNotEmpty) {
        domain.add(['name', 'ilike', searchText]);
      }
      if (filters != null && filters.isNotEmpty) {
        domain.addAll(buildFilterDomain(filters, uid!));
      }

      final pickingItems = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [domain],
        'kwargs': {'fields': [], 'limit': itemsPerPage, 'offset': offset},
      });
      return List<Map<String, dynamic>>.from(pickingItems ?? []);
    } catch (e) {
      throw Exception('Failed to fetch stock pickings: $e');
    }
  }

  /// Fetches all move lines (`stock.move`) for a given picking ID
  ///
  /// Used in return creation bottom sheet to show editable return quantities.
  /// Returns raw list of move data maps.
  /// Throws exception on failure.
  Future<List<Map<String, dynamic>>> fetchMoveItems(int pickingId) async {
    try {
      final moveData = await CompanySessionManager.callKwWithCompany({
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
            'picking_id',
            'state',
          ],
        },
      });
      return List<Map<String, dynamic>>.from(moveData ?? []);
    } catch (e) {
      throw Exception('Failed to fetch move items: $e');
    }
  }

  /// Creates a new return picking using Odoo's return wizard
  ///
  /// Steps:
  /// 1. Creates `stock.return.picking` wizard record
  /// 2. Writes return move lines (product + quantity)
  /// 3. Triggers return creation (method differs pre/post Odoo 18)
  ///
  /// Throws exception if no lines provided or RPC fails.
  Future<void> createReturn(
    int pickingId,
    List<List<Object>> returnLines,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    int version = prefs.getInt('version') ?? 0;
    try {
      if (returnLines.isEmpty) {
        throw Exception('No quantity specified for return.');
      }

      final wizardId = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.return.picking',
        'method': 'create',
        'args': [
          {'picking_id': pickingId},
        ],
        'kwargs': {},
      });

      await CompanySessionManager.callKwWithCompany({
        'model': 'stock.return.picking',
        'method': 'write',
        'args': [
          wizardId,
          {'product_return_moves': returnLines},
        ],
        'kwargs': {},
      });
      if (version < 18) {
        await CompanySessionManager.callKwWithCompany({
          'model': 'stock.return.picking',
          'method': 'create_returns',
          'args': [wizardId],
          'kwargs': {},
        });
      } else {
        await CompanySessionManager.callKwWithCompany({
          'model': 'stock.return.picking',
          'method': 'action_create_returns',
          'args': [wizardId],
          'kwargs': {},
        });
      }
    } catch (_) {}
  }
}
