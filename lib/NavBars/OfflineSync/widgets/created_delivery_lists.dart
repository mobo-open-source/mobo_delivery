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

/// Displays a list of offline-created deliveries (stock pickings) that are pending sync to Odoo.
///
/// Features:
///   - Shows each created picking with name, partner, operation type, scheduled date,
///     origin, move type, user, note, and product list
///   - "Sync Created Deliveries" button (disabled when offline or syncing)
///   - Empty state with Lottie ghost animation when no pending creates
///   - Periodic network check (every 10 seconds) to update offline status
///   - Calls `onSynced` callback after successful sync to refresh parent UI
class CreatedDeliveryList extends StatefulWidget {
  /// List of pending created delivery maps (from Hive/offline storage)
  final List<Map<String, dynamic>> creates;

  /// Optional callback invoked after successful sync (usually to refresh parent)
  final Future<void> Function()? onSynced;

  const CreatedDeliveryList({super.key, required this.creates, this.onSynced});

  @override
  State<CreatedDeliveryList> createState() => _CreatedDeliveryListState();
}

/// Manages state for displaying and syncing offline-created deliveries.
///
/// Responsibilities:
///   - Initializes Odoo client and connectivity service
///   - Periodically checks network status (every 10s)
///   - Handles manual sync of created items when online
///   - Shows loading state during sync
///   - Displays rich details for each pending creation (products, notes, etc.)
///   - Shows empty state with animation when no pending creations exist
class _CreatedDeliveryListState extends State<CreatedDeliveryList> {
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
    isOffline = !(await connectivityService.isConnectedToOdoo());
    setState(() {});
  }

  /// Manually triggers sync of all pending created deliveries to Odoo.
  ///
  /// Flow:
  ///   1. Checks if online → shows error if offline
  ///   2. Sets syncing state (disables button)
  ///   3. Calls sync service to push creations
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

      await syncService.syncPendingCreates(widget.creates);

      if (widget.onSynced != null) {
        await widget.onSynced!();
      }

      setState(() => isSyncing = false);

      CustomSnackbar.showSuccess(
        context,
        'Offline created deliveries synced successfully!',
      );
    } catch (e) {
      setState(() => isSyncing = false);
      CustomSnackbar.showError(
        context,
        'Something went wrong, Please try again later.!',
      );
    }
  }

  /// Reusable centered layout with Lottie animation, title, subtitle, and optional button.
  ///
  /// Used for empty states and other full-screen messages.
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

  /// Shows empty state with ghost animation when no pending created deliveries exist.
  Widget _buildEmptyState(bool isDark, BuildContext context) {
    return _buildCenteredLottie(
      lottie: 'assets/empty_ghost.json',
      title: 'No created deliveries found',
      subtitle: null,
      isDark: isDark,
      button: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Empty state when no items
    if (widget.creates.isEmpty) {
      return Expanded(child: Center(child: _buildEmptyState(isDark, context)));
    }

    return ListView.builder(
      itemCount: widget.creates.length + 1,
      itemBuilder: (context, index) {
        // Sync button at the bottom
        if (index == widget.creates.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isSyncing || widget.creates.isEmpty
                    ? null
                    : _manualSync,
                icon: const Icon(HugeIcons.strokeRoundedDatabaseSync01),
                label: Text(
                  isSyncing ? "Syncing Deliveries..." : 'Sync Created Deliveries',
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
              "Picking Order ${index + 1}",
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppStyle.primaryColor,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.creates[index]['pickingData']['partnerName'] != null)
                  Text(
                    "Partner Name: ${widget.creates[index]['pickingData']['partnerName']}",
                    style: TextStyle(
                      fontWeight: FontWeight.normal,
                      color: isDark ? Colors.white70 : Colors.black,
                    ),
                  ),

                if (widget.creates[index]['pickingData']['operationTypeName'] !=
                    null)
                  Text(
                    "Operation Type: ${widget.creates[index]['pickingData']['operationTypeName']}",
                    style: TextStyle(
                      fontWeight: FontWeight.normal,
                      color: isDark ? Colors.white70 : Colors.black,
                    ),
                  ),

                if (widget.creates[index]['pickingData']['scheduledDate'] !=
                    null)
                  Text(
                    "Scheduled Date: ${widget.creates[index]['pickingData']['scheduledDate']}",
                    style: TextStyle(
                      fontWeight: FontWeight.normal,
                      color: isDark ? Colors.white70 : Colors.black,
                    ),
                  ),

                if (widget.creates[index]['pickingData']['origin'] != null &&
                    widget.creates[index]['pickingData']['origin'] != "None")
                  Text(
                    "Origin: ${widget.creates[index]['pickingData']['origin']}",
                    style: TextStyle(
                      fontWeight: FontWeight.normal,
                      color: isDark ? Colors.white70 : Colors.black,
                    ),
                  ),

                if (widget.creates[index]['pickingData']['moveType'] != null)
                  Text(
                    "Move Type: ${widget.creates[index]['pickingData']['moveType'] == "direct"
                        ? "As soon as possible"
                        : widget.creates[index]['pickingData']['moveType'] == "one"
                        ? "When all products are ready"
                        : widget.creates[index]['pickingData']['moveType']}",
                    style: TextStyle(
                      fontWeight: FontWeight.normal,
                      color: isDark ? Colors.white70 : Colors.black,
                    ),
                  ),

                if (widget.creates[index]['pickingData']['userName'] != null)
                  Text(
                    "User Name: ${widget.creates[index]['pickingData']['userName']}",
                    style: TextStyle(
                      fontWeight: FontWeight.normal,
                      color: isDark ? Colors.white70 : Colors.black,
                    ),
                  ),

                if (widget.creates[index]['pickingData']['note'] != null &&
                    widget.creates[index]['pickingData']['note']
                        .toString()
                        .isNotEmpty)
                  Text(
                    "Note: ${widget.creates[index]['pickingData']['note']}",
                    style: TextStyle(
                      fontWeight: FontWeight.normal,
                      color: isDark ? Colors.white70 : Colors.black,
                    ),
                  ),

                if (widget.creates[index]['pickingData']['products'] != null &&
                    (widget.creates[index]['pickingData']['products'] as List)
                        .isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      Text(
                        "Products:",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      ...List.generate(
                        (widget.creates[index]['pickingData']['products']
                                as List)
                            .length,
                        (prodIndex) {
                          final product = widget
                              .creates[index]['pickingData']['products'][prodIndex];
                          return Text(
                            "- ${product['productName']} (Qty: ${product['productUomQty']})",
                            style: TextStyle(
                              fontWeight: FontWeight.normal,
                              color: isDark ? Colors.white70 : Colors.black,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
