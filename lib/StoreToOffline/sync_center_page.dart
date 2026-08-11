import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../NavBars/AttachDocument/models/pending_attachment.dart';
import '../NavBars/Pickings/CreateNewPicking/models/Hive/pending_creates.dart';
import '../NavBars/Pickings/PickingFormPage/models/pending_updates.dart';
import '../NavBars/Pickings/PickingFormPage/models/pending_validation.dart';
import '../NavBars/Pickings/PickingFormPage/models/product_update.dart';
import '../NavBars/Pickings/PickingFormPage/services/hive_service.dart';
import '../shared/utils/globals.dart';
import '../shared/widgets/buttons/mobo_button.dart';
import '../shared/widgets/snackbar.dart';
import 'pending_sync_service.dart';

/// A single queued offline change, normalized for display in the Sync Center.
class _PendingRow {
  final String group;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Future<void> Function() onDelete;

  _PendingRow({
    required this.group,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onDelete,
  });
}

/// Lists everything queued in the offline write-queues (creates, header
/// updates, product-line edits, validations, cancellations, attachments) and
/// lets the user trigger a manual sync or drop a queued item.
class SyncCenterPage extends StatefulWidget {
  const SyncCenterPage({super.key});

  @override
  State<SyncCenterPage> createState() => _SyncCenterPageState();
}

class _SyncCenterPageState extends State<SyncCenterPage> {
  final HiveService _hive = HiveService();
  List<_PendingRow> _rows = [];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _hive.initialize();
    final results = await Future.wait([
      _hive.getPendingCreates(),
      _hive.getPendingUpdates(),
      _hive.getPendingProductUpdates(),
      _hive.getPendingValidations(),
      _hive.getPendingCancellations(),
    ]);

    final rows = <_PendingRow>[];

    for (final PendingCreates c in results[0] as List<PendingCreates>) {
      final data = c.pickingData;
      final partner = (data['partnerName'] ?? '').toString();
      final opType = (data['operationTypeName'] ?? '').toString();
      rows.add(
        _PendingRow(
          group: 'New Pickings',
          icon: HugeIcons.strokeRoundedAddCircle,
          color: Colors.blue,
          title: partner.isNotEmpty ? partner : 'New picking',
          subtitle: opType.isNotEmpty ? opType : 'Created offline',
          onDelete: () => _hive.clearPendingCreates(c.pickingId),
        ),
      );
    }

    for (final PendingUpdates u in results[1] as List<PendingUpdates>) {
      final keys = u.pickingData.keys
          .where((k) => u.pickingData[k] != null)
          .join(', ');
      rows.add(
        _PendingRow(
          group: 'Header Updates',
          icon: HugeIcons.strokeRoundedEdit02,
          color: Colors.orange,
          title: 'Picking #${u.pickingId}',
          subtitle: keys.isEmpty ? 'Field changes' : 'Changed: $keys',
          onDelete: () => _hive.clearPendingUpdates(u.pickingId),
        ),
      );
    }

    for (final ProductUpdates p in results[2] as List<ProductUpdates>) {
      rows.add(
        _PendingRow(
          group: 'Product Line Changes',
          icon: HugeIcons.strokeRoundedPackage,
          color: AppStyle.primaryColor,
          title: p.pickingName?.isNotEmpty == true
              ? p.pickingName!
              : 'Picking #${p.pickingId}',
          subtitle: 'Product line add / edit',
          onDelete: () => _hive.clearPendingProductUpdates(p.pickingId),
        ),
      );
    }

    for (final PendingValidation v in results[3] as List<PendingValidation>) {
      rows.add(
        _PendingRow(
          group: 'Validations',
          icon: HugeIcons.strokeRoundedCheckmarkCircle02,
          color: Colors.green,
          title: 'Picking #${v.pickingId}',
          subtitle: 'Validate transfer',
          onDelete: () => _hive.clearPendingValidation(v.pickingId),
        ),
      );
    }

    for (final PendingValidation c in results[4] as List<PendingValidation>) {
      rows.add(
        _PendingRow(
          group: 'Cancellations',
          icon: HugeIcons.strokeRoundedCancelCircle,
          color: Colors.red,
          title: 'Picking #${c.pickingId}',
          subtitle: 'Cancel transfer',
          onDelete: () => _hive.clearPendingCancellation(c.pickingId),
        ),
      );
    }

    final attachments = await _hive.getPendingAttachmentsMap();
    attachments.forEach((key, PendingAttachment a) {
      rows.add(
        _PendingRow(
          group: 'Attachments',
          icon: HugeIcons.strokeRoundedAttachment,
          color: Colors.teal,
          title: a.fileName,
          subtitle: 'Attach to picking #${a.pickingId}',
          onDelete: () => _hive.clearPendingAttachmentByKey(key),
        ),
      );
    });

    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
    PendingSyncService.instance.refreshCount();
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    final result = await PendingSyncService.instance.syncAll();
    if (!mounted) return;
    setState(() => _syncing = false);

    if (result.skipped) {
      CustomSnackbar.showWarning(context, 'A sync is already in progress.');
    } else if (result.isEmpty) {
      CustomSnackbar.showInfo(context, 'Nothing to sync.');
    } else {
      final dropped = result.droppedLines > 0
          ? ' ${result.droppedLines} invalid product '
                'line${result.droppedLines == 1 ? '' : 's'} skipped.'
          : '';
      if (result.failed == 0) {
        CustomSnackbar.showSuccess(
          context,
          'Synced ${result.succeeded} offline change'
          '${result.succeeded == 1 ? '' : 's'}.$dropped',
        );
      } else {
        CustomSnackbar.showWarning(
          context,
          'Synced ${result.succeeded} — ${result.failed} still pending '
          'retry.$dropped',
        );
      }
    }
    await _load();
  }

  Future<void> _delete(_PendingRow row) async {
    await row.onDelete();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    const order = [
      'New Pickings',
      'Header Updates',
      'Product Line Changes',
      'Validations',
      'Cancellations',
      'Attachments',
    ];
    final grouped = <String, List<_PendingRow>>{};
    for (final r in _rows) {
      grouped.putIfAbsent(r.group, () => []).add(r);
    }
    final sections = order.where(grouped.containsKey).toList();

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        forceMaterialTransparency: true,
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        title: Text(
          'Offline Sync',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 22,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            HugeIcons.strokeRoundedArrowLeft01,
            color: isDark ? Colors.white : Colors.black,
            size: 28,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
          ? _buildEmptyState(isDark)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  for (final section in sections) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                      child: Text(
                        '$section (${grouped[section]!.length})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ),
                    ...grouped[section]!.map((r) => _buildCard(r, isDark)),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: _rows.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: MoboButton.primary(
                  label: 'Sync now (${_rows.length})',
                  icon: HugeIcons.strokeRoundedRefresh,
                  isLoading: _syncing,
                  loadingLabel: 'Syncing',
                  onPressed: _syncing ? null : _syncNow,
                ),
              ),
            ),
    );
  }

  Widget _buildCard(_PendingRow r, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: r.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(r.icon, color: r.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  r.subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove from queue',
            splashRadius: 20,
            icon: Icon(
              HugeIcons.strokeRoundedDelete02,
              size: 20,
              color: isDark ? Colors.grey[400] : Colors.grey[500],
            ),
            onPressed: () => _delete(r),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            HugeIcons.strokeRoundedCloudUpload,
            size: 64,
            color: isDark ? Colors.grey[700] : Colors.grey[400],
          ),
          const SizedBox(height: 12),
          Text(
            'All changes are synced',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Nothing is waiting to be sent to the server.',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}
