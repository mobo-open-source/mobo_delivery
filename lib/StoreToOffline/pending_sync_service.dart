import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../NavBars/AttachDocument/services/odoo_attach_service.dart';
import '../NavBars/Pickings/CreateNewPicking/services/odoo_create_picking_service.dart';
import '../NavBars/Pickings/PickingFormPage/services/hive_service.dart';
import '../NavBars/Pickings/PickingFormPage/services/odoo_picking_form_service.dart';
import '../core/company/services/connectivity_service.dart';

/// Result of a single sync run, surfaced to the UI for snackbar feedback.
class SyncResult {
  final int succeeded;
  final int failed;
  final bool skipped;

  /// Product lines discarded because they could never be sent (missing
  /// product or non-positive quantity). Surfaced so the drop isn't silent.
  final int droppedLines;

  const SyncResult({
    this.succeeded = 0,
    this.failed = 0,
    this.skipped = false,
    this.droppedLines = 0,
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

  final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  /// Pickings created offline and not yet pushed to Odoo. Tracked separately
  /// so the Pickings list can show them — they exist only in Hive and never
  /// appear in a server-backed list.
  final ValueNotifier<int> pendingCreateCount = ValueNotifier<int>(0);

  Future<int> countPending() async {
    await _hive.initialize();
    final results = await Future.wait([
      _hive.getPendingCreates(),
      _hive.getPendingUpdates(),
      _hive.getPendingProductUpdates(),
      _hive.getPendingValidations(),
      _hive.getPendingCancellations(),
      _hive.getPendingAttachments(),
    ]);
    pendingCreateCount.value = results.first.length;
    return results.fold<int>(0, (sum, list) => sum + list.length);
  }

  Future<void> refreshCount() async {
    pendingCount.value = await countPending();
  }

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
    HiveService.onPendingQueueChanged = refreshCount;
    refreshCount();
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
      int droppedLines = 0;

      succeeded += await _drainCreates(
        onFail: () => failed++,
        onDropped: (n) => droppedLines += n,
      );
      succeeded += await _drainUpdates(onFail: () => failed++);
      succeeded += await _drainProductUpdates(onFail: () => failed++);
      succeeded += await _drainValidations(onFail: () => failed++);
      succeeded += await _drainCancellations(onFail: () => failed++);
      succeeded += await _drainAttachments(onFail: () => failed++);

      return SyncResult(
        succeeded: succeeded,
        failed: failed,
        droppedLines: droppedLines,
      );
    } finally {
      _running = false;
      await refreshCount();
    }
  }

  /// Drains queued offline creates.
  ///
  /// The remote id is persisted the moment Odoo assigns it, and each product
  /// line is removed from the payload as it lands, so any interruption
  /// resumes where it stopped rather than creating a duplicate picking.
  Future<int> _drainCreates({
    required void Function() onFail,
    required void Function(int) onDropped,
  }) async {
    final creates = await _hive.getPendingCreates();
    if (creates.isEmpty) return 0;
    final createService = await _createServiceWithUrl();
    int ok = 0;
    for (final c in creates) {
      try {
        final data = Map<String, dynamic>.from(c.pickingData);

        int? remoteId = _asInt(data['remotePickingId']);
        if (remoteId == null) {
          final partnerId = _asInt(data['partnerId']);
          final operationTypeId = _asInt(data['operationTypeId']);
          if (partnerId == null || operationTypeId == null) {
            onFail();
            continue;
          }
          remoteId = await createService.createPicking(
            partnerId: partnerId,
            operationTypeId: operationTypeId,
            scheduledDate: data['scheduledDate']?.toString() ?? '',
            origin: data['origin']?.toString(),
            moveType: data['moveType']?.toString() ?? 'direct',
            userId: _asInt(data['userId']),
            note: data['note']?.toString(),
          );

          data['remotePickingId'] = remoteId;
          await _hive.updatePendingCreateData(c.pickingId, data);
          await _hive.remapPendingAttachmentsPickingId(c.pickingId, remoteId);
        }

        final pickingCompanyId = await createService.getPickingCompanyId(
          remoteId,
        );

        final rawProducts = data['products'];
        final queued = rawProducts is List
            ? rawProducts.whereType<Map>().toList()
            : const <Map>[];

        int dropped = 0;
        bool anyLine = false;
        bool needsConfirm = data['needsConfirm'] == true;

        if (queued.isNotEmpty) {
          int? locationId = _asInt(queued.first['defaultLocationSrcId']);
          int? locationDestId = _asInt(queued.first['defaultLocationDestId']);
          if (locationId == null || locationDestId == null) {
            final locations = await createService.getPickingLocations(remoteId);
            locationId ??= locations['location_id'] as int?;
            locationDestId ??= locations['location_dest_id'] as int?;
          }

          if (locationId == null || locationDestId == null) {
            onFail();
            continue;
          }

          final remaining = <Map>[];
          for (final raw in queued) {
            final productId = _asInt(raw['productId']);
            final qty = _asDouble(raw['productUomQty']) ?? 0.0;
            if (productId == null || qty <= 0) {
              dropped++;
              continue;
            }
            try {
              await createService.createStockMove(
                name: raw['productName']?.toString() ?? 'Product',
                productId: productId,
                productUomQty: qty,
                productUomId: _asInt(raw['productUomId']) ?? 1,
                pickingId: remoteId,
                locationId: locationId,
                locationDestId: locationDestId,
                companyId: pickingCompanyId,
              );
              anyLine = true;
            } catch (_) {
              remaining.add(raw);
            }
          }

          if (anyLine) needsConfirm = true;
          data['products'] = remaining;
          data['needsConfirm'] = needsConfirm;
          await _hive.updatePendingCreateData(c.pickingId, data);

          if (remaining.isNotEmpty) {
            onFail();
            continue;
          }
        }

        if (needsConfirm) {
          try {
            await createService.confirmPicking(
              remoteId,
              companyId: pickingCompanyId,
            );
          } catch (_) {}
        }

        await _hive.clearPendingCreates(c.pickingId);
        if (dropped > 0) onDropped(dropped);
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

        final success = await _formService.saveChanges(u.pickingId, updatesMap);
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

  Future<int> _drainProductUpdates({required void Function() onFail}) async {
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
          await p.delete();
          ok++;
        } else {
          final locations = await _formService.getPickingLocations(p.pickingId);
          final src = locations.locationId;
          final dst = locations.locationDestId;
          if (src == null || dst == null) {
            onFail();
            continue;
          }
          final productName = (productIdRaw is List && productIdRaw.length > 1)
              ? productIdRaw[1].toString()
              : (p.pickingName ?? 'Product');
          final uomId =
              _asInt(move['product_uom']) ?? _asInt(move['uom_id']) ?? 1;
          String? pickingState;
          try {
            final loaded = await _formService.loadPickings(p.pickingId);
            if (loaded.isNotEmpty) pickingState = loaded.first.state;
          } catch (_) {}
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
          await p.delete();
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
    return type == 'ir.actions.act_window' || type == 'ir.actions.client';
  }

  Future<int> _drainValidations({required void Function() onFail}) async {
    final pending = await _hive.getPendingValidations();
    int ok = 0;
    for (final v in pending) {
      try {
        final result = await _formService.validatePicking(v.pickingId);
        if (_isWizardAction(result)) {
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

  Future<int> _drainCancellations({required void Function() onFail}) async {
    final pending = await _hive.getPendingCancellations();
    int ok = 0;
    for (final c in pending) {
      try {
        final result = await _formService.cancelPicking(c.pickingId);
        if (_isWizardAction(result)) {
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

  Future<int> _drainAttachments({required void Function() onFail}) async {
    final map = await _hive.getPendingAttachmentsMap();
    if (map.isEmpty) return 0;
    final service = OdooAttachService();
    int ok = 0;
    for (final entry in map.entries) {
      final att = entry.value;
      try {
        await service.uploadFileToChatter(
          att.mimeType,
          att.base64File,
          att.pickingId,
          att.fileName,
        );
        await _hive.clearPendingAttachmentByKey(entry.key);
        ok++;
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
