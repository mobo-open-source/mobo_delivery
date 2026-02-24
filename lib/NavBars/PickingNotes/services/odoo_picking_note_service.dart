import '../../../core/company/session/company_session_manager.dart';

/// Service layer responsible for all Odoo RPC operations related to picking internal notes.
///
/// This class handles:
///   - Session-based Odoo client initialization
///   - Building complex domain filters for stock picking search
///   - Counting pickings matching filters/search
///   - Fetching paginated pickings with note field
///   - Saving/updating the internal `note` field on a `stock.picking` record
///
/// All RPC calls are routed through `CompanySessionManager` using the authenticated session.
/// Methods return safe defaults (0, [], false) on failure for graceful degradation.
class OdooPickingNoteService {
  int? userId;
  String url = '';

  /// Initializes the Odoo RPC client using the current authenticated session.
  ///
  /// Must be called before any other RPC methods.
  /// Throws an exception if no active session exists (user not logged in).
  Future<void> initializeClient() async {
    final session = await CompanySessionManager.getCurrentSession();
    if (session == null) throw Exception("No active session");
  }

  /// Builds Odoo domain clauses for filtering stock pickings based on UI filter chips.
  ///
  /// Each filter key maps to one or more domain conditions:
  ///   - 'to_do'       → assigned to current user or unassigned + not done/cancelled
  ///   - 'my_transfer' → assigned to current user
  ///   - 'late'        → overdue (deadline passed or has_deadline_issue)
  ///   - 'warning'     → has activity exception
  ///   - etc.
  ///
  /// Returns a flat list of domain clauses that can be combined with AND/OR logic.
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

  /// Returns the total count of stock pickings matching the given search text and filters.
  ///
  /// Used for pagination UI ("X results") and displaying total pages/items.
  /// Builds domain dynamically from search and selected filters.
  /// Throws descriptive exception on failure (network/auth/RPC error).
  Future<int> StockCount({
    String? searchText,
    List<String> filters = const [],
  }) async {
    try {
      List<List<dynamic>> domain = [];

      if (searchText != null && searchText.isNotEmpty) {
        domain.add(['name', 'ilike', searchText]);
      }
      final session = await CompanySessionManager.getCurrentSession();
      final uid = session!.userId;

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

  /// Fetches a paginated page of stock pickings with optional search and filters.
  ///
  /// Returns list of picking records with selected fields:
  ///   - id, name, note, scheduled_date, state, origin, picking_type_id
  ///
  /// Used for both initial load and pagination.
  /// Returns empty list on any failure (graceful degradation).
  Future<List<Map<String, dynamic>>> fetchStockPickings(
    int page,
    int itemsPerPage, {
    String? searchQuery,
    List<String>? filters,
  }) async {
    try {
      final offset = page * itemsPerPage;

      List<List<dynamic>> domain = [];

      if (searchQuery != null && searchQuery.isNotEmpty) {
        domain.add(['name', 'ilike', searchQuery]);
      }
      final session = await CompanySessionManager.getCurrentSession();
      final uid = session!.userId;

      if (filters != null && filters.isNotEmpty) {
        domain.addAll(buildFilterDomain(filters, uid!));
      }

      final pickingItems = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [domain],
        'kwargs': {
          'fields': [
            'id',
            'name',
            'note',
            'scheduled_date',
            'state',
            'origin',
            'picking_type_id',
          ],
          'limit': itemsPerPage,
          'offset': offset,
        },
      });

      return List<Map<String, dynamic>>.from(pickingItems ?? []);
    } catch (e) {
      return [];
    }
  }

  /// Saves or updates the internal note field on a specific stock picking.
  ///
  /// Uses `stock.picking.write()` to set the `note` field.
  /// Returns `true` on success, `false` on any failure (network/auth/RPC error).
  Future<bool> saveNote(int pickingId, String note) async {
    await initializeClient();

    try {
      final result = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'write',
        'args': [
          [pickingId],
          {'note': note},
        ],
        'kwargs': {},
      });
      return result == true;
    } catch (e) {
      return false;
    }
  }
}
