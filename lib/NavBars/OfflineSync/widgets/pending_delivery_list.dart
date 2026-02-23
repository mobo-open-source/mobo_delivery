import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../Pickings/PickingFormPage/services/hive_service.dart';
import '../services/connectivity_service.dart';
import '../services/odoo_offline_service.dart';
import '../services/offline_sync_service.dart';

/// Displays a list of offline-validated (pending) deliveries that are ready to be synced to Odoo.
///
/// Features:
///   - Shows each validated picking with name and current status
///   - "Sync Validated Deliveries" button (disabled when offline or syncing)
///   - Empty state with Lottie ghost animation when no pending validations
///   - Periodic network check (every 10 seconds) to update offline status
///   - Calls `onSynced` callback after successful sync to refresh parent UI
class PendingDeliveryList extends StatefulWidget {
  /// List of pending validated delivery maps (from Hive/offline storage)
  final List<Map<String, dynamic>> pending;

  /// Optional callback invoked after successful sync (usually to refresh parent)
  final Future<void> Function()? onSynced;

  const PendingDeliveryList({super.key, required this.pending, this.onSynced});

  @override
  State<PendingDeliveryList> createState() => _PendingDeliveryListState();
}

/// Manages state for displaying and syncing offline-validated (pending) deliveries.
///
/// Responsibilities:
///   - Initializes Odoo client and connectivity service
///   - Periodically checks network status (every 10s)
///   - Handles manual sync of validated items when online
///   - Shows loading state during sync
///   - Displays simple picking info (name & status)
///   - Shows empty state with animation when no pending validations exist
class _PendingDeliveryListState extends State<PendingDeliveryList> {
  bool isSyncing = false;
  bool isOffline = true;
  late OdooOfflineSyncService odooService;
  late OfflineSyncService syncService;
  late ConnectivityService connectivityService;
  Timer? _networkTimer;

  @override
  void initState() {
    super.initState();
    odooService = OdooOfflineSyncService();
    syncService = OfflineSyncService(HiveService(), odooService);

    // Start periodic network check
    _networkTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _init();
    });
  }

  @override
  void dispose() {
    _networkTimer?.cancel();
    _networkTimer = null;
    super.dispose();
  }

  /// Initializes Odoo client and connectivity service, then updates offline status.
  ///
  /// Called on init and periodically via timer.
  /// Uses `ConnectivityService` to ping Odoo server.
  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('url') ?? '';
    connectivityService = ConnectivityService(url);

    await odooService.initClient();
    final offline = !(await connectivityService.isConnectedToOdoo());

    if (!mounted) return;

    setState(() {
      isOffline = offline;
    });
  }

  /// Manually triggers sync of all pending validated deliveries to Odoo.
  ///
  /// Flow:
  ///   1. Checks if online → shows error if offline
  ///   2. Sets syncing state (disables button)
  ///   3. Calls sync service to push validations
  ///   4. Triggers parent refresh via `onSynced` callback
  ///   5. Shows success/error snackbar
  ///   6. Tracks sync event for analytics
  Future<void> _manualSync() async {
    try {
      if (isOffline) {
        CustomSnackbar.showError(context, 'Cannot sync while offline.');

        return;
      }

      setState(() => isSyncing = true);

      await syncService.syncPendingValidations(widget.pending);

      if (widget.onSynced != null) {
        await widget.onSynced!();
      }

      setState(() => isSyncing = false);
      CustomSnackbar.showSuccess(context, 'Offline deliveries synced successfully!');

    } catch (e) {
      setState(() => isSyncing = false);
      CustomSnackbar.showError(context, 'Something went wrong, Please try again later.!');

    }
  }

  /// Reusable centered layout with Lottie animation, title, subtitle, and optional button.
  ///
  /// Used for empty states and other full-screen messages within this list.
  Widget _buildCenteredLottie({
    required String lottie,
    required String title,
    String? subtitle,
    Widget? button,
    required bool isDark,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Lottie.asset(lottie, width: 260),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                  if (button != null) ...[const SizedBox(height: 12), button],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Shows empty state with ghost animation when no pending validated deliveries exist.
  Widget _buildEmptyState(bool isDark, BuildContext context) {
    return _buildCenteredLottie(
      lottie: 'assets/empty_ghost.json',
      title: 'No validated deliveries found',
      subtitle: null,
      isDark: isDark,
      button: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return widget.pending.isEmpty
        ? Expanded(child: Center(child: _buildEmptyState(isDark, context)))
        : ListView.builder(
            itemCount: widget.pending.length + 1,
            itemBuilder: (context, index) {
              if (index == widget.pending.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isSyncing || widget.pending.isEmpty
                          ? null
                          : _manualSync,
                      icon: const Icon(HugeIcons.strokeRoundedDatabaseSync01),
                      label: Text(
                        isSyncing
                            ? "Syncing Deliveries..."
                            : 'Sync Validated Deliveries',
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.black : Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? Colors.white
                            : AppStyle.primaryColor,
                        foregroundColor: isDark
                            ? Colors.black
                            :Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        disabledBackgroundColor: isDark
                            ? Colors.grey[700]!
                            : Colors.grey[400]!,
                      ),
                    ),
                  ),
                );
              }

              final item = widget.pending[index];
              return Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[850] : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.grey[850]! : Colors.grey[200]!,
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF000000).withOpacity(0.05),
                      offset: const Offset(0, 6),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                margin: const EdgeInsets.only(bottom: 8, top: 8),
                child: ListTile(
                  leading: Icon(
                    HugeIcons.strokeRoundedTruck,
                    color: isDark ? Colors.white : AppStyle.primaryColor,
                  ),
                  title: Text(
                    item['pickingData']['name'] ?? 'Unknown',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  subtitle: Text(
                    'Status: ${item['pickingData']['state']}',
                    style: TextStyle(
                      fontWeight: FontWeight.normal,
                      color: isDark ? Colors.white70 : Colors.black,
                    ),
                  ),
                ),
              );
            },
          );
  }
}
