import 'package:odoo_rpc/odoo_rpc.dart';

import '../NavBars/Pickings/PickingFormPage/services/hive_service.dart';
import '../core/company/session/company_session_manager.dart';

/// Service responsible for syncing select stock picking data (mainly notes & attachments)
/// from Odoo to local offline storage (Hive) for use when offline.
///
/// Currently focuses on:
/// - Loading basic picking info (id, name, note, scheduled_date, state)
/// - Saving it to Hive for offline access
///
/// Future extensions could include:
///   - Attachments (ir.attachment linked to pickings)
///   - Full note syncing
///   - Background periodic sync
///   - Conflict resolution
class AttachmentAndNotesToOffline {
  int? userId;
  OdooClient? client;
  String url = "";
  final HiveService _hiveService = HiveService();

  /// Initializes the Odoo client using the current session and prepares Hive.
  ///
  /// Throws [Exception] if no active session is found.
  /// Also initializes Hive and loads initial picking data.
  Future<void> initializeOdooClient() async {
    final session = await CompanySessionManager.getCurrentSession();
    if (session == null) throw Exception("No active session");
    await _hiveService.initialize();
    await loadPickings();
  }

  /// Fetches basic stock picking records from Odoo and saves them to Hive.
  ///
  /// Currently fetches: id, name, note, scheduled_date, state
  /// No domain filter applied → fetches **all** pickings (can be heavy).
  ///
  /// Silent on error (catches everything) — consider logging in production.
  Future<void> loadPickings() async {
    try {
      final pickingItems = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'fields': ['id', 'name', 'note', 'scheduled_date', 'state'],
        },
      });
      if (pickingItems != null) {
        await _hiveService.savePickings(
          List<Map<String, dynamic>>.from(pickingItems),
        );
      }
    } catch (e) {}
  }
}
