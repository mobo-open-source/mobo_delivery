import '../../Pickings/PickingFormPage/services/hive_service.dart';
import 'odoo_offline_service.dart';

/// Central service that bridges offline storage (Hive) with online Odoo RPC calls
/// to synchronize deferred actions when internet connectivity is restored.
///
/// This service:
///   - Retrieves pending operations of various types from Hive
///   - Delegates actual Odoo RPC calls to `OdooOfflineSyncService`
///   - Clears successfully synced items from Hive
///   - Handles five main types of offline actions:
///     1. Validations (button_validate)
///     2. Cancellations (action_cancel)
///     3. Picking-level updates (write on stock.picking)
///     4. Product/move-level updates (write on stock.move)
///     5. New picking creations (create on stock.picking with move_ids)
///
/// All sync methods are idempotent and safe to retry; they skip or ignore failures
/// gracefully to avoid blocking the sync process.
class OfflineSyncService {
  final HiveService hiveService;
  final OdooOfflineSyncService odooService;

  OfflineSyncService(this.hiveService, this.odooService);

  /// Fetches all pending picking validations stored offline in Hive.
  ///
  /// Returns a list of maps containing `pickingId` and `pickingData`.
  /// Used to display pending validations in the UI and to sync them later.
  Future<List<Map<String, dynamic>>> getPendingValidations() async {
    final validations = await hiveService.getPendingValidations();
    return validations
        .map((v) => {'pickingId': v.pickingId, 'pickingData': v.pickingData})
        .toList();
  }

  /// Synchronizes all pending validations to Odoo and clears them from Hive on success.
  ///
  /// For each validation:
  ///   - Calls `validatePicking(pickingId)` via Odoo service
  ///   - Clears the item from Hive if the RPC call returns a non-null result
  ///
  /// Continues processing even if individual calls fail (fail-safe)
  Future<void> syncPendingValidations(
    List<Map<String, dynamic>> pending,
  ) async {
    for (var validation in pending) {
      final pickingId = validation['pickingId'];
      final result = await odooService.validatePicking(pickingId);
      if (result != null) {
        await hiveService.clearPendingValidation(pickingId);
      }
    }
  }

  /// Fetches all pending picking cancellations stored offline.
  ///
  /// Returns a list of maps with `pickingId` and `pickingData`.
  Future<List<Map<String, dynamic>>> getPendingCancellation() async {
    final cancellations = await hiveService.getPendingCancellations();
    return cancellations
        .map((v) => {'pickingId': v.pickingId, 'pickingData': v.pickingData})
        .toList();
  }

  /// Synchronizes all pending cancellations to Odoo and removes them from Hive on success.
  ///
  /// Calls `cancelPicking(pickingId)` for each item.
  /// Clears Hive entry only if RPC returns non-null.
  Future<void> syncPendingCancellation(
    List<Map<String, dynamic>> pending,
  ) async {
    for (var cancel in pending) {
      final pickingId = cancel['pickingId'];
      final result = await odooService.cancelPicking(pickingId);
      if (result != null) {
        await hiveService.clearPendingCancellation(pickingId);
      }
    }
  }

  /// Retrieves all pending picking-level updates from Hive.
  ///
  /// Returns list of maps with `pickingId` and `pickingData` (updated fields).
  Future<List<Map<String, dynamic>>> getPendingUpdates() async {
    final updates = await hiveService.getPendingUpdates();
    return updates
        .map((v) => {'pickingId': v.pickingId, 'pickingData': v.pickingData})
        .toList();
  }

  /// Synchronizes all pending picking updates to Odoo.
  ///
  /// For each update:
  ///   - Re-initializes Odoo client (safety measure)
  ///   - Calls `saveChanges(pickingId, pickingData)`
  ///   - Clears Hive entry only on successful write (result == true)
  ///
  /// Catches and ignores individual failures to continue syncing others.
  Future<void> syncPendingUpdates(List<Map<String, dynamic>> pending) async {
    for (var update in pending) {
      final pickingId = update['pickingId'];
      final pickingData = update['pickingData'];
      try {
        await odooService.initClient();
        final result = await odooService.saveChanges(pickingId, pickingData);
        if (result != null && result == true) {
          await hiveService.clearPendingUpdates(pickingId);
        }
      } catch (e) {}
    }
  }

  /// Fetches all pending new picking creations from Hive.
  ///
  /// Returns list of maps with `pickingId` (temporary) and `pickingData`.
  Future<List<Map<String, dynamic>>> getPendingCreates() async {
    final creates = await hiveService.getPendingCreates();
    return creates
        .map((v) => {'pickingId': v.pickingId, 'pickingData': v.pickingData})
        .toList();
  }

  /// Synchronizes all pending new picking creations to Odoo.
  ///
  /// For each create:
  ///   - Calls `createPicking(creates: pickingData)`
  ///   - Clears Hive entry if new picking ID is returned
  Future<void> syncPendingCreates(List<Map<String, dynamic>> pending) async {
    for (var create in pending) {
      final pickingId = create['pickingId'];
      final pickingData = create['pickingData'];
      final result = await odooService.createPicking(creates: pickingData);
      if (result != null) {
        await hiveService.clearPendingCreates(pickingId);
      }
    }
  }

  /// Fetches all pending product/move updates from Hive.
  ///
  /// Returns list of maps containing:
  ///   - pickingId
  ///   - pickingName
  ///   - productData (move details)
  Future<List<Map<String, dynamic>>> getProductUpdates() async {
    final products = await hiveService.getPendingProductUpdates();
    return products
        .map(
          (v) => {
            'pickingId': v.pickingId,
            'pickingName': v.pickingName,
            'productData': v.productData,
          },
        )
        .toList();
  }

  /// Synchronizes all pending product/move updates to Odoo.
  ///
  /// For each product update:
  ///   - Re-initializes Odoo client
  ///   - Calls `productUpdates(...)` with move/location data
  ///   - Clears Hive entry only on success
  ///
  /// Skips null/invalid data and silently ignores individual failures.
  Future<void> syncProductUpdates(List<Map<String, dynamic>> products) async {
    for (var product in products) {
      final pickingId = product['pickingId'];
      final productData = product['productData'];

      if (productData == null) continue;

      final moveData = productData['move'];
      final location_id_int = productData['location_id_int'] ?? 0;

      final location_dest_id_int = productData['location_dest_id_int'] ?? 0;

      try {
        await odooService.initClient();
        final result = await odooService.productUpdates(
          pickingId,
          moveData,
          location_id_int,
          location_dest_id_int,
        );

        if (result) {
          await hiveService.clearPendingProductUpdates(pickingId);
        } else {}
      } catch (e) {}
    }
  }
}
