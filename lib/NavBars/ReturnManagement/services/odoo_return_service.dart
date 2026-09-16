import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/company/session/company_session_manager.dart';

/// Service layer for managing **return pickings** (reverse transfers / customer returns) in Odoo.
///
/// Handles:
/// • Counting & fetching paginated return-eligible pickings
/// • Building filter domains for presets ("My Transfer", "Already Returned", etc.)
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
  /// The presets offered here — operation type, ownership, return status and
  /// date range — are the ones that stay meaningful across every row the list
  /// shows (see [_returnsDomain]), which is dominated by completed transfers.
  /// Used for both count and search_read operations.
  List<dynamic> buildFilterDomain(List<String> filters, int uid) {
    final List<dynamic> domain = [];

    for (final filter in filters) {
      switch (filter) {
        case 'my_transfer':
          domain.add(['user_id', '=', uid]);
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

        case 'has_return':
          domain.add(['return_count', '>', 0]);
          break;

        case 'no_return':
          domain.add(['return_count', '=', 0]);
          break;

        case 'this_week':
          domain.add(['scheduled_date', '>=', _formatDate(_startOfWeek())]);
          break;

        case 'this_month':
          domain.add(['scheduled_date', '>=', _formatDate(_startOfMonth())]);
          break;

        case 'warning':
          domain.add(['activity_exception_decoration', '!=', false]);
          break;
      }
    }

    return domain;
  }

  DateTime _startOfWeek() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - 1));
  }

  DateTime _startOfMonth() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  String _formatDate(DateTime date) {
    return date.toUtc().toString().replaceFirst('Z', '').trim();
  }

  /// Completed transfers (the ones a return can be created *from*) plus every
  /// actual return record regardless of state. The second clause matters:
  /// Odoo's return wizard creates the return in `confirmed`/`assigned`, never
  /// `done`, so a `state = 'done'` domain alone can never show a return that
  /// was just created.
  ///
  /// `return_id` ("Return of") is the field Odoo itself sets on a return
  /// picking to point back at the picking it returns — present on
  /// `stock.picking` in 17, 18 and 19 alike (verified against Odoo's own
  /// source, not assumed). An earlier version of this domain used
  /// `origin_returned_picking_id`, a field that does not exist anywhere in
  /// stock's model — every query silently fell back to [_doneOnlyDomain]
  /// below, so returns never actually showed before they were validated.
  static const List<dynamic> _returnsDomain = [
    '|',
    ['state', '=', 'done'],
    ['return_id', '!=', false],
  ];

  /// Fallback for a deployment where `return_id` has been removed or
  /// renamed by a customization; preserves the original done-only
  /// behaviour rather than failing the list outright.
  static const List<dynamic> _doneOnlyDomain = [
    ['state', '=', 'done'],
  ];

  bool _isMissingReturnField(Object e) =>
      e.toString().toLowerCase().contains('return_id');

  List<dynamic> _buildDomain(
    List<dynamic> base,
    String? searchText,
    List<String>? filters,
    int? uid,
  ) {
    final domain = List<dynamic>.from(base);
    if (searchText != null && searchText.isNotEmpty) {
      domain.add(['name', 'ilike', searchText]);
    }
    if (filters != null && filters.isNotEmpty) {
      domain.addAll(buildFilterDomain(filters, uid!));
    }
    return domain;
  }

  /// Counts the rows the returns list shows (see [_returnsDomain]) matching filters/search
  ///
  /// Used for pagination total count and progress indicators.
  /// Throws exception on RPC failure for UI error handling.
  Future<int> StockCount({String? searchText, List<String>? filters}) async {
    try {
      final session = await CompanySessionManager.getCurrentSession();
      final uid = session!.userId;

      Future<dynamic> count(List<dynamic> base) {
        return CompanySessionManager.callKwWithCompany({
          'model': 'stock.picking',
          'method': 'search_count',
          'args': [_buildDomain(base, searchText, filters, uid)],
          'kwargs': {},
        });
      }

      dynamic pickingCount;
      try {
        pickingCount = await count(_returnsDomain);
      } catch (e) {
        if (_isMissingReturnField(e)) {
          pickingCount = await count(_doneOnlyDomain);
        } else {
          rethrow;
        }
      }
      return pickingCount ?? 0;
    } catch (e) {
      throw Exception('Failed to count stock pickings: $e');
    }
  }

  /// Fetches the paginated returns list (see [_returnsDomain])
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
      final session = await CompanySessionManager.getCurrentSession();
      final uid = session!.userId;

      const baseFields = [
        'id',
        'name',
        'state',
        'origin',
        'partner_id',
        'scheduled_date',
        'picking_type_id',
        'picking_type_code',
        'return_count',
      ];

      Future<dynamic> search(List<dynamic> base, List<String> fields) {
        return CompanySessionManager.callKwWithCompany({
          'model': 'stock.picking',
          'method': 'search_read',
          'args': [_buildDomain(base, searchText, filters, uid)],
          'kwargs': {'fields': fields, 'limit': itemsPerPage, 'offset': offset},
        });
      }

      dynamic pickingItems;
      try {
        pickingItems = await search(_returnsDomain, [
          ...baseFields,
          'return_id',
        ]);
      } catch (e) {
        if (_isMissingReturnField(e)) {
          pickingItems = await search(_doneOnlyDomain, baseFields);
        } else {
          rethrow;
        }
      }
      return List<Map<String, dynamic>>.from(pickingItems ?? []);
    } catch (e) {
      throw Exception('Failed to fetch stock pickings: $e');
    }
  }

  /// Fetches the returnable moves for a picking using Odoo's
  /// `stock.return.picking` wizard as the calculator. The wizard's
  /// onchange/compute on `picking_id` populates `product_return_moves`
  /// with the correct returnable quantity per line — already accounting
  /// for previously-returned units, pending reservations, cancelled
  /// moves, etc. — so the bottom sheet pre-fills match Odoo's web UI.
  ///
  /// Returns line maps shaped as `{id, product_id, quantity, move_id, uom_id}`.
  /// Throws on failure.
  Future<List<Map<String, dynamic>>> fetchReturnableMoves(int pickingId) async {
    try {
      final createResult = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.return.picking',
        'method': 'create',
        'args': [
          {'picking_id': pickingId},
        ],
        'kwargs': {
          'context': {'active_id': pickingId, 'active_model': 'stock.picking'},
        },
      });

      final int wizardId;
      if (createResult is int) {
        wizardId = createResult;
      } else if (createResult is List && createResult.isNotEmpty) {
        final first = createResult.first;
        if (first is int) {
          wizardId = first;
        } else if (first is Map) {
          wizardId = first['id'] as int;
        } else {
          throw Exception('Unexpected wizard id type: ${first.runtimeType}');
        }
      } else {
        throw Exception('Failed to create return wizard.');
      }

      final wizardRows = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.return.picking',
        'method': 'read',
        'args': [
          [wizardId],
          ['product_return_moves'],
        ],
        'kwargs': {},
      });

      if (wizardRows is! List || wizardRows.isEmpty) return [];
      final firstRow = wizardRows.first;
      if (firstRow is! Map) return [];
      final lineIds =
          (firstRow as Map<String, dynamic>)['product_return_moves'] as List? ??
          const [];
      if (lineIds.isEmpty) return [];

      final lines = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.return.picking.line',
        'method': 'read',
        'args': [
          List<int>.from(lineIds),
          ['id', 'product_id', 'quantity', 'move_id', 'uom_id'],
        ],
        'kwargs': {},
      });

      final result = List<Map<String, dynamic>>.from(lines ?? const []);

      final productIds = <int>{
        for (final line in result)
          if (line['product_id'] is List &&
              (line['product_id'] as List).isNotEmpty)
            (line['product_id'] as List).first as int,
      }.toList();

      if (productIds.isNotEmpty) {
        try {
          final products = await CompanySessionManager.callKwWithCompany({
            'model': 'product.product',
            'method': 'read',
            'args': [
              productIds,
              ['id', 'image_128'],
            ],
            'kwargs': {},
          });
          final imageById = <int, String>{};
          for (final p in (products as List? ?? const [])) {
            final map = p as Map<String, dynamic>;
            final img = map['image_128'];
            if (img is String && img.isNotEmpty) {
              imageById[map['id'] as int] = img;
            }
          }
          for (final line in result) {
            if (line['product_id'] is List &&
                (line['product_id'] as List).isNotEmpty) {
              final pid = (line['product_id'] as List).first as int;
              if (imageById.containsKey(pid)) {
                line['image'] = imageById[pid];
              }
            }
          }
        } catch (_) {}
      }

      return result;
    } catch (e) {
      throw Exception('Failed to fetch returnable moves: $e');
    }
  }

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

  /// Creates a new return picking via Odoo's `stock.return.picking`
  /// wizard. Replaces the wizard's auto-populated lines with the
  /// user-supplied ones, then triggers return creation (method differs
  /// pre/post Odoo 18). Returns the new return picking's id — both
  /// `create_returns` (17) and `action_create_returns` (18/19) hand back an
  /// `ir.actions.act_window` with `res_id` set to it (verified against
  /// Odoo's own source) — or `null` if that id could not be determined.
  /// Throws on RPC / wizard failure.
  Future<int?> createReturn(
    int pickingId,
    List<List<Object>> returnLines,
  ) async {
    if (returnLines.isEmpty) {
      throw Exception('No quantity specified for return.');
    }

    final prefs = await SharedPreferences.getInstance();
    final int version = prefs.getInt('version') ?? 0;

    final createResult = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.return.picking',
      'method': 'create',
      'args': [
        {'picking_id': pickingId},
      ],
      'kwargs': {
        'context': {'active_id': pickingId, 'active_model': 'stock.picking'},
      },
    });

    final int wizardId;
    if (createResult is int) {
      wizardId = createResult;
    } else if (createResult is List && createResult.isNotEmpty) {
      final first = createResult.first;
      if (first is int) {
        wizardId = first;
      } else if (first is Map) {
        wizardId = first['id'] as int;
      } else {
        throw Exception('Unexpected wizard id type: ${first.runtimeType}');
      }
    } else {
      throw Exception('Failed to create return wizard.');
    }

    final List<dynamic> replacementLines = [
      [5, 0, 0],
      ...returnLines,
    ];

    await CompanySessionManager.callKwWithCompany({
      'model': 'stock.return.picking',
      'method': 'write',
      'args': [
        [wizardId],
        {'product_return_moves': replacementLines},
      ],
      'kwargs': {},
    });

    final method = version < 18 ? 'create_returns' : 'action_create_returns';
    final actionResult = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.return.picking',
      'method': method,
      'args': [
        [wizardId],
      ],
      'kwargs': {},
    });

    if (actionResult is Map) {
      final resId = actionResult['res_id'];
      if (resId is int) return resId;
    }
    return null;
  }
}
