import '../../../core/company/session/company_session_manager.dart';

/// Service layer responsible for all Odoo RPC interactions related to attaching documents
/// to stock pickings (transfers, receipts, deliveries, etc.).
///
/// This class:
///   - Initializes the Odoo client via session
///   - Counts and fetches paginated stock pickings with search/filter/group support
///   - Builds complex domain filters for Odoo search_read/search_count
///   - Uploads files/signatures as attachments linked to stock.picking records
///
/// All methods use `CompanySessionManager` for authenticated JSON-RPC calls.
/// Throws exceptions on critical failures; returns safe defaults (empty list/false) on non-critical errors.
class OdooAttachService {
  int? userId;
  String url = '';

  /// Initializes the Odoo client connection using the current active session.
  ///
  /// Throws an exception if no valid session exists (user not logged in).
  /// This method should be called early (e.g. during BLoC initialization)
  /// before any other RPC calls are made.
  Future<void> initializeClient() async {
    final session = await CompanySessionManager.getCurrentSession();
    if (session == null) throw Exception("No active session");
  }

  /// Returns the total count of stock pickings matching the given search text and filters.
  ///
  /// Used for:
  ///   - Pagination UI (showing total pages/items)
  ///   - Displaying "X results found"
  ///
  /// Builds domain dynamically based on search and selected filters.
  /// Throws on network/auth failure.
  Future<int> StockCount({String? searchText, List<String>? filters}) async {
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

  /// Builds Odoo domain filters based on UI-selected filter chips.
  ///
  /// Each filter key maps to one or more domain conditions:
  ///   - 'to_do'       → assigned to current user or unassigned + not done/cancelled
  ///   - 'my_transfer' → assigned to current user
  ///   - 'late'        → overdue (deadline passed or has_deadline_issue)
  ///   - 'warning'     → has activity exception
  ///   - etc.
  ///
  /// Returns a flat list of domain clauses that can be combined with AND/OR.
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

  /// Fetches a paginated page of stock pickings with optional search, filters, and grouping.
  ///
  /// Returns a list of picking records with selected fields:
  ///   - id, name, note, scheduled_date, state, picking_type_id, origin
  ///
  /// Used for both initial load and pagination/infinite scroll.
  /// Returns empty list on failure (graceful degradation).
  Future<List<Map<String, dynamic>>> fetchAttachmentStockPickings(
    int page,
    int itemsPerPage, {
    String? searchQuery,
    List<String>? filters,
    String? groupBy,
  }) async {
    try {
      final offset = page * itemsPerPage;

      final List<Object?> domain = [];

      if (searchQuery != null && searchQuery.isNotEmpty) {
        domain.addAll([
          '|',
          ['name', 'ilike', searchQuery],
          ['note', 'ilike', searchQuery],
        ]);
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
            'picking_type_id',
            'origin',
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

  /// Uploads a file (signature/image/PDF/etc.) as an attachment to a specific stock picking.
  ///
  /// Creates an `ir.attachment` record linked to `stock.picking` via `res_model` and `res_id`.
  /// File content is sent as base64-encoded `datas` field.
  ///
  /// Returns `true` on success, `false` on failure (no exception thrown).
  Future<bool> uploadFileToChatter(
    String mimeType,
    String base64Data,
    int pickingId,
    String fileName,
  ) async {
    try {
      final attachmentId = await CompanySessionManager.callKwWithCompany({
        'model': 'ir.attachment',
        'method': 'create',
        'args': [
          {
            'name': fileName,
            'res_model': 'stock.picking',
            'res_id': pickingId,
            'datas': base64Data,
            'type': 'binary',
            'mimetype': mimeType,
          },
        ],
        'kwargs': {},
      });
      return attachmentId != null;
    } catch (e) {
      return false;
    }
  }
}
