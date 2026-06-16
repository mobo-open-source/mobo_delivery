import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../NavBars/Pickings/CreateNewPicking/services/odoo_create_picking_service.dart';
import '../NavBars/Pickings/PickingFormPage/services/hive_service.dart';
import '../NavBars/Pickings/PickingFormPage/services/odoo_picking_form_service.dart';
import '../core/company/services/connectivity_service.dart';

/// Result of a single sync run, surfaced to the UI for snackbar feedback.
class SyncResult {
  final int succeeded;
  final int failed;
  final bool skipped;

  const SyncResult({
    this.succeeded = 0,
    this.failed = 0,
    this.skipped = false,
  });

  bool get isEmpty => succeeded == 0 && failed == 0;
}

/// Drains the offline-save Hive queues (validations, cancellations, picking
/// header updates, new picking creates, product line edits) to Odoo when
/// connectivity returns. Processes in dependency order so creates precede
/// updates that target them. Per-item errors leave the row queued for the
/// next retry; the rest of the queue continues.
class PendingSyncService {
  PendingSyncService._();
  static final PendingSyncService instance = PendingSyncService._();

  final HiveService _hive = HiveService();
  final OdooPickingFormService _formService = OdooPickingFormService();

  Future<OdooCreatePickingService> _createServiceWithUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('url') ?? '';
    return OdooCreatePickingService(url);
  }

  bool _running = false;
  StreamSubscription<bool>? _serverSub;

  /// Subscribes to [ConnectivityService.onServerChanged] so each
  /// server-restoration event auto-drains the queues. Idempotent.
  void start() {
    if (_serverSub != null) return;
    _serverSub = ConnectivityService.instance.onServerChanged.listen((up) {
      if (up) syncAll();
    });
  }

  Future<void> stop() async {
    await _serverSub?.cancel();
    _serverSub = null;
  }

  /// One-shot drain. Returns counts so the caller can show a snackbar.
  Future<SyncResult> syncAll() async {
    if (_running) return const SyncResult(skipped: true);
    _running = true;
    try {
      await _hive.initialize();

      int succeeded = 0;
      int failed = 0;

      succeeded += await _drainCreates(onFail: () => failed++);
      succeeded += await _drainUpdates(onFail: () => failed++);
      succeeded += await _drainProductUpdates(onFail: () => failed++);
      succeeded += await _drainValidations(onFail: () => failed++);
      succeeded += await _drainCancellations(onFail: () => failed++);

      return SyncResult(succeeded: succeeded, failed: failed);
    } finally {
      _running = false;
    }
  }

  Future<int> _drainCreates({required void Function() onFail}) async {
    final creates = await _hive.getPendingCreates();
    if (creates.isEmpty) return 0;
    final createService = await _createServiceWithUrl();
    int ok = 0;
    for (final c in creates) {
      try {
        final data = c.pickingData;
        final partnerId = _asInt(data['partnerId']);
        final operationTypeId = _asInt(data['operationTypeId']);
        if (partnerId == null || operationTypeId == null) {
          onFail();
          continue;
        }
        final newPickingId = await createService.createPicking(
          partnerId: partnerId,
          operationTypeId: operationTypeId,
          scheduledDate: data['scheduledDate']?.toString() ?? '',
          origin: data['origin']?.toString(),
          moveType: data['moveType']?.toString() ?? 'direct',
          userId: _asInt(data['userId']),
          note: data['note']?.toString(),
        );

        // Replay any product moves that were queued with the picking.
        // Read the picking's actual company so the moves are stamped
        // with the same company — otherwise multi-company record rules
        // hide them from the picking view.
        final products = data['products'];
        bool hasProducts = false;
        final pickingCompanyId =
            await createService.getPickingCompanyId(newPickingId);
        if (products is List && products.isNotEmpty) {
          int? locationId = _asInt(
            (products.first is Map) ? products.first['defaultLocationSrcId'] : null,
          );
          int? locationDestId = _asInt(
            (products.first is Map) ? products.first['defaultLocationDestId'] : null,
          );
          if (locationId == null || locationDestId == null) {
            final locations =
                await createService.getPickingLocations(newPickingId);
            locationId ??= locations['location_id'] as int?;
            locationDestId ??= locations['location_dest_id'] as int?;
          }
          if (locationId != null && locationDestId != null) {
            for (final raw in products) {
              if (raw is! Map) continue;
              final productId = _asInt(raw['productId']);
              final uomId = _asInt(raw['productUomId']) ?? 1;
              final qty = _asDouble(raw['productUomQty']) ?? 0.0;
              final name = raw['productName']?.toString() ?? 'Product';
              if (productId == null || qty <= 0) continue;
              await createService.createStockMove(
                name: name,
                productId: productId,
                productUomQty: qty,
                productUomId: uomId,
                pickingId: newPickingId,
                locationId: locationId,
                locationDestId: locationDestId,
                companyId: pickingCompanyId,
              );
              hasProducts = true;
            }
          }
        }

        if (hasProducts) {
          try {
            await createService.confirmPicking(
              newPickingId,
              companyId: pickingCompanyId,
            );
          } catch (_) {
            // Best-effort in headless sync. Picking + moves are saved;
            // user can confirm manually from the picking detail page.
          }
        }

        await _hive.clearPendingCreates(c.pickingId);
        ok++;
      } catch (_) {
        onFail();
      }
    }
    return ok;
  }

  Future<int> _drainUpdates({required void Function() onFail}) async {
    final updates = await _hive.getPendingUpdates();
    int ok = 0;
    for (final u in updates) {
      try {
        final raw = u.pickingData;
        final Map<String, dynamic> updatesMap = (raw['updates'] is Map)
            ? Map<String, dynamic>.from(raw['updates'] as Map)
            : Map<String, dynamic>.from(raw);

        updatesMap.removeWhere((_, value) => value == null);

        final success =
            await _formService.saveChanges(u.pickingId, updatesMap);
        if (success) {
          await _hive.clearPendingUpdates(u.pickingId);
          ok++;
        } else {
          onFail();
        }
      } catch (_) {
        onFail();
      }
    }
    return ok;
  }

  Future<int> _drainProductUpdates({
    required void Function() onFail,
  }) async {
    final entries = await _hive.getPendingProductUpdates();
    int ok = 0;
    for (final p in entries) {
      try {
        final move = p.productData['move'];
        if (move is! Map) {
          onFail();
          continue;
        }

        final moveId = _asInt(move['id']);
        final productIdRaw = move['product_id'];
        final productId = productIdRaw is List && productIdRaw.isNotEmpty
            ? _asInt(productIdRaw.first)
            : _asInt(productIdRaw);
        final qty = _asDouble(move['quantity']);

        if (productId == null || qty == null) {
          onFail();
          continue;
        }

        if (moveId != null) {
          await _formService.updateProductMove(moveId, productId, qty);
          await _hive.clearPendingProductUpdates(p.pickingId);
          ok++;
        } else {
          final locations =
              await _formService.getPickingLocations(p.pickingId);
          final src = locations.locationId;
          final dst = locations.locationDestId;
          if (src == null || dst == null) {
            onFail();
            continue;
          }
          final productName =
              (productIdRaw is List && productIdRaw.length > 1)
                  ? productIdRaw[1].toString()
                  : (p.pickingName ?? 'Product');
          final uomId =
              _asInt(move['product_uom']) ?? _asInt(move['uom_id']) ?? 1;
          // Fetch picking state so addProductToLine can confirm the new
          // move when the picking is already past draft. Without this the
          // synced move would stay orphaned in 'draft' and silently break
          // subsequent validate / mark-as-todo on that picking.
          String? pickingState;
          try {
            final loaded = await _formService.loadPickings(p.pickingId);
            if (loaded.isNotEmpty) pickingState = loaded.first.state;
          } catch (_) {
            // Best-effort; default to skipping the post-create confirm.
          }
          await _formService.addProductToLine(
            p.pickingId,
            productId,
            productName,
            uomId,
            qty,
            src,
            dst,
            pickingState: pickingState,
          );
          await _hive.clearPendingProductUpdates(p.pickingId);
          ok++;
        }
      } catch (_) {
        onFail();
      }
    }
    return ok;
  }

  /// Returns true when an Odoo response map represents a wizard
  /// action (backorder confirm, immediate transfer, scrap warning,
  /// SMS confirm, etc.) — those can't be resolved in a headless
  /// background sync, so we leave the queue entry in place and let
  /// the user finish it from the picking detail page next time.
  bool _isWizardAction(dynamic result) {
    if (result is! Map) return false;
    final type = result['type'];
    return type == 'ir.actions.act_window' ||
        type == 'ir.actions.client';
  }

  Future<int> _drainValidations({required void Function() onFail}) async {
    final pending = await _hive.getPendingValidations();
    int ok = 0;
    for (final v in pending) {
      try {
        final result = await _formService.validatePicking(v.pickingId);
        if (_isWizardAction(result)) {
          // Wizard popped on the server (e.g. backorder confirmation).
          // We can't drive it from background sync — keep the entry
          // pending and surface it as "failed/retry" so the user sees
          // it and can finish from the picking detail page.
          onFail();
        } else if (result == true) {
          await _hive.clearPendingValidation(v.pickingId);
          ok++;
        } else {
          onFail();
        }
      } catch (_) {
        onFail();
      }
    }
    return ok;
  }

  Future<int> _drainCancellations({
    required void Function() onFail,
  }) async {
    final pending = await _hive.getPendingCancellations();
    int ok = 0;
    for (final c in pending) {
      try {
        final result = await _formService.cancelPicking(c.pickingId);
        if (_isWizardAction(result)) {
          // Same handling as validation: wizard requires UI, leave
          // queued and let the user finish it manually.
          onFail();
        } else if (result == true) {
          await _hive.clearPendingCancellation(c.pickingId);
          ok++;
        } else {
          onFail();
        }
      } catch (_) {
        onFail();
      }
    }
    return ok;
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  double? _asDouble(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
