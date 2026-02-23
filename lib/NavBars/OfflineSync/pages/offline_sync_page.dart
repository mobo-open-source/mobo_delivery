import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/utils/globals.dart';
import '../../Pickings/PickingFormPage/services/hive_service.dart';
import '../services/connectivity_service.dart';
import '../services/odoo_offline_service.dart';
import '../services/offline_sync_service.dart';
import '../widgets/cancelled_delivery_list.dart';
import '../widgets/created_delivery_lists.dart';
import '../widgets/offline_status_indicator.dart';
import '../widgets/pending_delivery_list.dart';
import '../widgets/updated_delivery_list.dart';

/// Screen that displays all offline-pending delivery operations (created, updated, cancelled, validated)
/// and allows syncing them when internet is available.
///
/// Features:
///   - Shows current offline/online status with indicator
///   - Tabbed view for different operation types
///   - Periodic network connectivity check (every 10 seconds)
///   - Lazy-loads pending data from Hive via OfflineSyncService
///   - Each tab widget handles its own sync UI and callbacks
class OfflineSyncPage extends StatefulWidget {
  const OfflineSyncPage({super.key});

  @override
  State<OfflineSyncPage> createState() => _OfflineSyncPageState();
}

/// Manages offline sync UI state, connectivity monitoring, data loading,
/// and periodic network checks.
///
/// Responsibilities:
///   - Initialize services (OdooOfflineSyncService, OfflineSyncService, ConnectivityService)
///   - Load all pending operation lists from Hive on init
///   - Periodically check Odoo server reachability
///   - Refresh UI when sync completes in child widgets
class _OfflineSyncPageState extends State<OfflineSyncPage> {
  bool isOffline = true;
  bool isSyncing = false;
  List<Map<String, dynamic>> pending = [];
  List<Map<String, dynamic>> pendingCancel = [];
  List<Map<String, dynamic>> pendingUpdates = [];
  List<Map<String, dynamic>> pendingCreates = [];
  List<Map<String, dynamic>> productUpdates = [];
  Timer? networkTimer;

  late OdooOfflineSyncService odooService;
  late OfflineSyncService syncService;
  late ConnectivityService connectivityService;

  @override
  void initState() {
    super.initState();
    odooService = OdooOfflineSyncService();
    syncService = OfflineSyncService(HiveService(), odooService);
    _init();
  }

  /// Initializes services, loads all pending data, and starts periodic network check.
  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('url') ?? '';
    connectivityService = ConnectivityService(url);

    await odooService.initClient();
    await _loadPending();
    await _loadCancelled();
    await _loadUpdates();
    await _loadProducts();
    await _loadCreated();
    networkTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkNetwork();
    });

    await _checkNetwork();
  }

  /// Checks connectivity to Odoo server and updates offline status.
  ///
  /// Uses `ConnectivityService.isConnectedToOdoo()` which pings the server.
  /// Only triggers rebuild if status actually changed.
  Future<void> _checkNetwork() async {
    final connected = await connectivityService.isConnectedToOdoo();
    if (mounted && isOffline == connected) {
      setState(() {
        isOffline = !connected;
      });
    }
  }

  /// Loads pending validations from Hive via sync service.
  Future<void> _loadPending() async {
    pending = await syncService.getPendingValidations();
    setState(() {});
  }

  /// Loads pending cancellations from Hive.
  Future<void> _loadCancelled() async {
    pendingCancel = await syncService.getPendingCancellation();
    setState(() {});
  }

  /// Loads pending create operations from Hive.
  Future<void> _loadCreated() async {
    pendingCreates = await syncService.getPendingCreates();
    setState(() {});
  }

  /// Loads pending update operations from Hive.
  Future<void> _loadUpdates() async {
    pendingUpdates = await syncService.getPendingUpdates();
    setState(() {});
  }

  /// Loads pending product updates from Hive.
  Future<void> _loadProducts() async {
    productUpdates = await syncService.getProductUpdates();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            OfflineStatusIndicator(isOffline: isOffline),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Pending Offline Deliveries:",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: DefaultTabController(
                length: 4,
                child: Column(
                  children: [
                    TabBar(
                      indicator: UnderlineTabIndicator(
                        borderSide: BorderSide(
                          width: 3,
                          color: isDark
                              ? Colors.white
                              : AppStyle.primaryColor,
                        ),
                        insets: EdgeInsets.symmetric(
                          horizontal: 16,
                        ),
                      ),
                      labelColor: isDark ? Colors.white : AppStyle.primaryColor,
                      labelStyle: TextStyle(fontWeight: FontWeight.normal),
                      unselectedLabelColor: Colors.grey,
                      isScrollable: true,
                      tabs: [
                        Tab(text: "Created"),
                        Tab(text: "Updated"),
                        Tab(text: "Cancelled"),
                        Tab(text: "Validated"),
                      ],
                    ),
                    const SizedBox(height: 10),

                    Expanded(
                      child: TabBarView(
                        children: [
                          CreatedDeliveryList(
                            creates: pendingCreates,
                            onSynced: _loadCreated,
                          ),
                          UpdatedDeliveryList(
                            updates: pendingUpdates,
                            products: productUpdates,
                            onSynced: _loadUpdates,
                            onProductSynced: _loadProducts,
                          ),
                          CancelledDeliveryList(
                            cancel: pendingCancel,
                            onSynced: _loadCancelled,
                          ),
                          PendingDeliveryList(
                            pending: pending,
                            onSynced: _loadPending,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
