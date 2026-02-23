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

/// Displays a list of offline-updated deliveries (stock pickings) and their product updates pending sync to Odoo.
///
/// Features:
///   - Merges picking updates and product changes into a single enriched list
///   - Shows detailed info for each updated picking (title, scheduled date, origin, move type, partner, note, etc.)
///   - Lists updated products with name and quantity
///   - "Sync All Updates" button (disabled when offline or syncing)
///   - Empty state with Lottie ghost animation when no pending updates
///   - Periodic network check (every 10 seconds) to update offline status
///   - Calls `onSynced` and `onProductSynced` callbacks after successful sync
class UpdatedDeliveryList extends StatefulWidget {
  /// List of pending picking-level updates (from Hive)
  final List<Map<String, dynamic>> updates;

  /// List of pending product-level updates (from Hive)
  final List<Map<String, dynamic>> products;

  /// Optional callback after successful picking updates sync
  final Future<void> Function()? onSynced;

  /// Optional callback after successful product updates sync
  final Future<void> Function()? onProductSynced;

  const UpdatedDeliveryList({
    super.key,
    required this.updates,
    required this.products,
    this.onSynced,
    this.onProductSynced,
  });

  @override
  State<UpdatedDeliveryList> createState() => _UpdatedDeliveryListState();
}

/// Manages state for displaying and syncing offline-updated deliveries & products.
///
/// Responsibilities:
///   - Merges picking updates and product changes into a unified list
///   - Initializes Odoo client and connectivity service
///   - Periodically checks network status (every 10s)
///   - Handles manual sync of both picking and product updates when online
///   - Shows loading state during sync
///   - Displays rich picking details and product list
///   - Shows empty state with animation when no pending updates exist
class _UpdatedDeliveryListState extends State<UpdatedDeliveryList> {
  bool isSyncing = false;
  bool isOffline = true;
  late OdooOfflineSyncService odooService;
  late OfflineSyncService syncService;
  late ConnectivityService connectivityService;

  /// Merged list of picking updates with their associated product changes
  List<Map<String, dynamic>> mergedList = [];
  Timer? _networkTimer;

  @override
  void initState() {
    super.initState();
    odooService = OdooOfflineSyncService();
    syncService = OfflineSyncService(HiveService(), odooService);
    _mergeData();

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

  /// Merges initial picking updates and product updates into a single enriched list.
  ///
  /// Creates a map keyed by `pickingId`, then attaches products to each picking.
  /// Handles cases where products exist without matching picking updates.
  void _mergeData() {
    final Map<int, Map<String, dynamic>> temp = {};

    for (var update in widget.updates) {
      final pickingId = update['pickingId'];
      temp[pickingId] = {
        "pickingId": pickingId,
        "pickingData": update['pickingData'] ?? {},
        "products": [],
        "pickingName": update['pickingData']?['title'] ?? "Updated Picking",
      };
    }

    for (var product in widget.products) {
      final pickingId = product['pickingId'];
      final pickingName = product['pickingName'];

      if (temp.containsKey(pickingId)) {
        temp[pickingId]!["products"].add(product['productData']);
      } else {
        temp[pickingId] = {
          "pickingId": pickingId,
          "pickingData": {},
          "products": [product['productData']],
          "pickingName": pickingName,
        };
      }
    }

    mergedList = temp.values.toList();
  }

  /// Manually triggers sync of all pending picking updates and product updates to Odoo.
  ///
  /// Flow:
  ///   1. Checks if online → shows error if offline
  ///   2. Sets syncing state (disables button)
  ///   3. Syncs both updates and products in parallel (`Future.wait`)
  ///   4. Reloads fresh data from Hive
  ///   5. Re-merges data and triggers parent callbacks
  ///   6. Shows success/error snackbar
  ///   7. Tracks sync event for analytics
  Future<void> _manualSync() async {
    try {
      if (isOffline) {
        CustomSnackbar.showError(context, 'Cannot sync while offline.');
        return;
      }

      setState(() => isSyncing = true);

      await Future.wait([
        syncService.syncPendingUpdates(widget.updates),
        syncService.syncProductUpdates(widget.products),
      ]);

      final freshUpdates = await syncService.getPendingUpdates();
      final freshProducts = await syncService.getProductUpdates();

      if (widget.onSynced != null) await widget.onSynced!();
      if (widget.onProductSynced != null) await widget.onProductSynced!();

      _mergeDataFromLists(freshUpdates, freshProducts);

      setState(() => isSyncing = false);

      CustomSnackbar.showSuccess(
        context,
        'Offline updated deliveries synced successfully!',
      );
    } catch (e) {
      setState(() => isSyncing = false);
      CustomSnackbar.showError(
        context,
        'Something went wrong, Please try again later.!',
      );
    }
  }

  /// Updates `mergedList` after a sync using fresh data from Hive.
  ///
  /// Re-merges the newly synced (or remaining) updates and products.
  void _mergeDataFromLists(
    List<Map<String, dynamic>> updates,
    List<Map<String, dynamic>> products,
  ) {
    final Map<int, Map<String, dynamic>> temp = {};

    for (var update in updates) {
      final pickingId = update['pickingId'];
      temp[pickingId] = {
        "pickingId": pickingId,
        "pickingData": update['pickingData'] ?? {},
        "products": [],
      };
    }

    for (var product in products) {
      final pickingId = product['pickingId'];
      final pickingName = product['pickingName'];
      if (temp.containsKey(pickingId)) {
        temp[pickingId]!["products"].add(product['productData']);
      } else {
        temp[pickingId] = {
          "pickingId": pickingId,
          "pickingData": {},
          "products": [product['productData']],
          "pickingName": pickingName,
        };
      }
    }

    mergedList = temp.values.toList();
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

  /// Shows empty state with ghost animation when no pending updated deliveries exist.
  Widget _buildEmptyState(bool isDark, BuildContext context) {
    return _buildCenteredLottie(
      lottie: 'assets/empty_ghost.json',
      title: 'No updated deliveries found',
      subtitle: null,
      isDark: isDark,
      button: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Empty state when no items after merging
    if (mergedList.isEmpty) {
      return Expanded(child: Center(child: _buildEmptyState(isDark, context)));
    }

    return ListView.builder(
      itemCount: mergedList.length + 1,
      itemBuilder: (context, index) {
        if (index == mergedList.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isSyncing || mergedList.isEmpty ? null : _manualSync,
                icon: const Icon(HugeIcons.strokeRoundedDatabaseSync01),
                label: Text(
                  isSyncing ? "Syncing..." : 'Sync All Updates',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.black : Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark
                      ? Colors.white
                      : AppStyle.primaryColor,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
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

        final item = mergedList[index];
        final pickingData = item['pickingData'] ?? {};
        final updatesData = pickingData['updates'] ?? {};
        final products = item['products'] as List;
        final pickingName =
            (item['products'] != null && item['products'].isNotEmpty)
            ? item['products'][0]['pickingName'] ?? "Updated Picking"
            : "Updated Picking";

        final details = <String>[];
        final productDetails = <String>[];
        if (updatesData['scheduled_date'] != null &&
            updatesData['scheduled_date'].toString().isNotEmpty) {
          details.add("Scheduled Date: ${updatesData['scheduled_date']}");
        }
        if (updatesData['origin'] != null &&
            updatesData['origin'].toString().isNotEmpty) {
          details.add("Origin: ${updatesData['origin']}");
        }
        if (updatesData['date_done'] != null &&
            updatesData['date_done'].toString().isNotEmpty) {
          details.add("Date Done: ${updatesData['date_done']}");
        }
        if (updatesData['move_type'] != null &&
            updatesData['move_type'].toString().isNotEmpty) {
          details.add("Move Type: ${updatesData['move_type']}");
        }
        if (updatesData['user_name'] != null &&
            updatesData['user_name'].toString().isNotEmpty) {
          details.add("Responsible: ${updatesData['user_name']}");
        }
        if (updatesData['partner_name'] != null &&
            updatesData['partner_name'].toString().isNotEmpty) {
          details.add("Delivery Address: ${updatesData['partner_name']}");
        }
        if (updatesData['note'] != null &&
            updatesData['note'].toString().isNotEmpty) {
          details.add("Note: ${updatesData['note']}");
        }
        for (final product in products) {
          final move = product['move'];

          if (move != null && move is Map) {
            final productId = move['product_id'];
            final productName = (productId is List && productId.length > 1)
                ? productId[1]
                : '';
            final qty = move['quantity'] ?? move['product_uom_qty'] ?? '';
            final uom = move['quantity_product_uom'] ?? '';

            productDetails.add("$productName - $qty $uom");
          }
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
              pickingData['title'] ?? pickingName,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (details.isNotEmpty) ...details.map((d) => Text(d)).toList(),
                if (productDetails.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    "Products:",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  ...productDetails
                      .map(
                        (p) => Text(
                          p.toString(),
                          style: TextStyle(
                            fontWeight: FontWeight.normal,
                            color: isDark ? Colors.white70 : Colors.black,
                          ),
                        ),
                      )
                      .toList(),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
