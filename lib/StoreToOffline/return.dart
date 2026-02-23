import 'package:odoo_rpc/odoo_rpc.dart';

import '../NavBars/Pickings/PickingFormPage/services/hive_service.dart';
import '../core/company/session/company_session_manager.dart';

/// Service that syncs "done" stock pickings (returns & completed transfers)
/// and related stock moves from Odoo to local Hive storage for offline use.
///
/// Main purpose:
///   - Cache completed pickings (state = 'done') – often returns or finished operations
///   - Cache all stock moves (currently no filter – fetches everything)
///
/// Data is stored via [HiveService] for use in offline return picking screens.
class ReturnToOffline {
  int? userId;
  OdooClient? client;
  String url = "";
  final HiveService _hiveService = HiveService();

  /// Initializes Odoo session, Hive, and triggers sync of done pickings + moves.
  ///
  /// Throws [Exception] if no active session is available.
  Future<void> initializeOdooClient() async {
    final session = await CompanySessionManager.getCurrentSession();
    if (session == null) throw Exception("No active session");
    await _hiveService.initialize();
    await loadPickings();
    await loadMove();
  }

  /// Loads all "done" stock pickings from Odoo and saves them to Hive.
  ///
  /// Fetches:
  ///   - Total count of done pickings
  ///   - All picking records with state = 'done'
  ///
  /// Currently fetches **all fields** (`fields: []`) — consider limiting to needed ones.
  Future<void> loadPickings() async {
    try {
      final pickingCount = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'search_count',
        'args': [
          ['state', '=', 'done'],
        ],
        'kwargs': {},
      });

      await _hiveService.saveTotalCount(pickingCount);

      // Fetch all done pickings
      final pickingItems = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [
          [
            ['state', '=', 'done'],
          ],
        ],
        'kwargs': {'fields': []},
      });
      if (pickingItems != null) {
        await _hiveService.saveReturnPickings(
          List<Map<String, dynamic>>.from(pickingItems),
        );
      }
    } catch (e) {}
  }

  /// Loads **all** stock moves from Odoo (no filter) and saves them to Hive.
  ///
  /// Warning: fetching every stock move in the system can be very slow/heavy
  /// if the database is large. Consider adding domain filters (e.g. recent dates,
  /// specific picking types, or linked to done pickings only).
  Future<void> loadMove() async {
    try {
      final moveData = await CompanySessionManager.callKwWithCompany({
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
      if (moveData != null) {
        await _hiveService.saveStockMoves(
          List<Map<String, dynamic>>.from(moveData),
        );
      }
    } catch (e) {}
  }
}
