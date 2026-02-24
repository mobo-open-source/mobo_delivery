import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive/hive.dart';

import '../../../../core/company/session/company_session_manager.dart';
import '../models/picking_model.dart';

/// Service layer responsible for fetching, caching, filtering, and paginating stock pickings
/// grouped by warehouse/location.
///
/// Features:
/// • Online: fetches paginated pickings from Odoo per warehouse
/// • Offline: loads and filters cached `Picking` models from Hive
/// • Supports search, state/type/date filters, custom filter presets ("Late", "Backorders", etc.)
/// • Pagination with next/prev page per location
/// • Grouping & domain building for advanced filters
///
/// Data is stored in memory (`allPickingsByLocation`) and persisted in Hive via `Picking` model.
class PickingService {
  String url = "";
  int? userId;
  bool isDataFromHive = false;

  // ───────────────────────────────────────────────
  //  In-memory state for UI & pagination
  // ───────────────────────────────────────────────
  Map<String, List<Map<String, dynamic>>> allPickingsByLocation = {};
  Map<String, List<Map<String, dynamic>>> previousPickingsByLocation = {};
  Map<String, int> currentPage = {};
  Map<String, bool> hasNextPage = {};
  Map<String, int> totalPickingsCount = {};

  final int pageSize = 40;

  /// Clears all pagination-related state (pages, offsets, hasMore flags)
  void clearPaginationState() {
    currentPage.clear();
    hasNextPage.clear();
    totalPickingsCount.clear();
    warehouseOffsets.clear();
    hasMorePickings.clear();
  }

  Map<String, int> warehouseOffsets = {};
  Map<String, bool> hasMorePickings = {};

  /// Returns human-readable page range string (e.g. "1-40") for a location
  String pageRangeForLocation(String location) {
    final page = currentPage[location] ?? 0;
    final total = totalPickingsCount[location] ?? 0;
    final start = page * pageSize + 1;
    final end = (start + pageSize - 1).clamp(start, total);
    return '$start-$end';
  }

  // ───────────────────────────────────────────────
  //  Initialization & Connectivity
  // ───────────────────────────────────────────────

  /// Ensures Odoo session is active — call before any RPC
  Future<void> initializeOdooClient() async {
    final session = await CompanySessionManager.getCurrentSession();
    if (session == null) throw Exception("No active session");
  }

  /// Checks both device network and Odoo server reachability
  ///
  /// Returns `true` only if network exists **and** `$url/web` responds 200 within 5s.
  Future<bool> checkNetworkConnectivity() async {
    final prefs = await SharedPreferences.getInstance();
    url = prefs.getString('url') ?? '';
    final connectivityResult = await Connectivity().checkConnectivity();

    if (connectivityResult != ConnectivityResult.none) {
      try {
        final response = await http
            .get(Uri.parse('$url/web'))
            .timeout(const Duration(seconds: 5));

        return response.statusCode == 200;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  // ───────────────────────────────────────────────
  //  Main Fetch Entry Point
  // ───────────────────────────────────────────────

  /// Primary method to load pickings — combines online + offline paths
  ///
  /// 1. Checks connectivity
  /// 2. Always loads from Hive first (fast offline support)
  /// 3. If online, fetches fresh data from Odoo and updates cache
  Future<void> fetchData({
    DateTime? scheduledDate,
    DateTime? deadlineDate,
    String? state,
    String? type,
    String? searchTerm,
    List<String>? filters,
    Map<String, int>? pageOverrides,
  }) async {
    final isConnected = await checkNetworkConnectivity();
    isDataFromHive = !isConnected;

    // Always load from Hive first (fast baseline)
    await loadPickingsFromHive(
      searchTerm: searchTerm ?? '',
      state: state,
      scheduleDate: scheduledDate,
      deadlineDate: deadlineDate,
      type: type ?? 'outgoing',
    );

    await stockPickings(
      scheduledDate: scheduledDate,
      deadlineDate: deadlineDate,
      state: state,
      type: type,
      searchTerm: searchTerm,
      filters: filters,
      pageOverrides: pageOverrides,
    );
  }

  // ───────────────────────────────────────────────
  //  Pagination Helpers (used in UI)
  // ───────────────────────────────────────────────

  void appendPage(String location, List<Map<String, dynamic>> newPickings) {
    final current = allPickingsByLocation[location] ?? [];
    allPickingsByLocation[location] = [...current, ...newPickings];
  }

  void removeLastPage(String location, int pageSize) {
    final list = allPickingsByLocation[location];
    if (list == null || list.length <= pageSize) {
      allPickingsByLocation[location] = [];
      return;
    }
    allPickingsByLocation[location] = list.sublist(0, list.length - pageSize);
  }

  /// Builds Odoo domain clauses from preset filter names
  ///
  /// Translates user-friendly filter labels ("Late", "Backorders", "My Transfer", etc.)
  /// into proper domain tuples for `stock.picking.search_count` and `search_read`.
  List<List<dynamic>> buildFilterDomain(List<String> filters, int uid) {
    final List<List<dynamic>> domain = [];

    for (final filter in filters) {
      switch (filter) {
        case 'to_do':
          domain.addAll([
            [
              'user_id',
              'in',
              [uid, false],
            ],
            [
              'state',
              'not in',
              ['done', 'cancel'],
            ],
          ]);
          break;

        case 'my_transfer':
          domain.add(['user_id', '=', uid]);
          break;

        case 'draft':
          domain.add(['state', '=', 'draft']);
          break;

        case 'waiting':
          domain.add([
            'state',
            'in',
            ['confirmed', 'waiting'],
          ]);
          break;

        case 'ready':
          domain.add(['state', '=', 'assigned']);
          break;

        case 'receipt':
          domain.add(['picking_type_code', '=', 'incoming']);
          break;

        case 'deliveries':
          domain.add(['picking_type_code', '=', 'outgoing']);
          break;

        case 'internal':
          domain.add(['picking_type_code', '=', 'internal']);
          break;

        case 'late':
          final now = DateTime.now().toIso8601String();
          domain.addAll([
            [
              'state',
              'in',
              ['assigned', 'waiting', 'confirmed'],
            ],
            [
              '|',
              '|',
              ['has_deadline_issue', '=', true],
              ['date_deadline', '<', now],
              ['scheduled_date', '<', now],
            ],
          ]);
          break;

        case 'planning_issue':
          final now = DateTime.now().toIso8601String();
          domain.addAll([
            [
              '|',
              ['delay_alert_date', '!=', false],
              [
                '&',
                ['scheduled_date', '<', now],
                [
                  'state',
                  'in',
                  ['assigned', 'waiting', 'confirmed'],
                ],
              ],
            ],
          ]);
          break;

        case 'backorder':
          domain.addAll([
            ['backorder_id', '!=', false],
            [
              'state',
              'in',
              ['assigned', 'waiting', 'confirmed'],
            ],
          ]);
          break;

        case 'warning':
          domain.add(['activity_exception_decoration', '!=', false]);
          break;
      }
    }

    return domain;
  }

  // ───────────────────────────────────────────────
  //  Online Fetch (Odoo RPC)
  // ───────────────────────────────────────────────

  /// Fetches paginated pickings from Odoo, grouped by warehouse
  ///
  /// • Builds domain from filters, search, state, type
  /// • Fetches warehouses → picking types per warehouse → pickings
  /// • Stores results in `allPickingsByLocation` (flattened for UI)
  /// • Updates pagination state (`currentPage`, `hasNextPage`, `totalPickingsCount`)
  Future<void> stockPickings({
    DateTime? scheduledDate,
    DateTime? deadlineDate,
    String? state,
    String? type,
    String? searchTerm,
    List<String>? filters,
    Map<String, int>? pageOverrides,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int version = prefs.getInt('version') ?? 0;

      // Fetch all warehouses
      final warehouseItems = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.warehouse',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'fields': ['id', 'name'],
        },
      });

      if (pageOverrides == null) {
        allPickingsByLocation.clear();
        currentPage.clear();
        hasNextPage.clear();
        totalPickingsCount.clear();
      }

      // Base domain (filters + search)
      List<List<dynamic>> baseDomain = [];
      final session = await CompanySessionManager.getCurrentSession();
      final uid = session!.userId;

      if (filters != null && filters.isNotEmpty) {
        baseDomain.addAll(buildFilterDomain(filters, uid!));
      }
      if (searchTerm != null && searchTerm.isNotEmpty)
        baseDomain.add(['name', 'ilike', searchTerm]);

      for (var warehouse in warehouseItems ?? []) {
        String warehouseName = warehouse['name'];
        int warehouseId = warehouse['id'] is int
            ? warehouse['id']
            : int.parse(warehouse['id'].toString());

        if (pageOverrides != null && !pageOverrides.containsKey(warehouseName))
          continue;

        int page =
            pageOverrides?[warehouseName] ?? currentPage[warehouseName] ?? 0;
        int offset = page * pageSize;
        currentPage[warehouseName] = page;

        // Get picking types for this warehouse
        final pickingTypes = await CompanySessionManager.callKwWithCompany({
          'model': 'stock.picking.type',
          'method': 'search_read',
          'args': [
            [
              ['warehouse_id', '=', warehouseId],
            ],
          ],
          'kwargs': {
            'fields': ['id'],
          },
        });

        List<int> pickingTypeIds =
            (pickingTypes as List?)
                ?.map((e) => int.parse(e['id'].toString()))
                .toList() ??
            [];
        if (pickingTypeIds.isEmpty) {
          allPickingsByLocation[warehouseName] = [];
          hasNextPage[warehouseName] = false;
          totalPickingsCount[warehouseName] = 0;
          continue;
        }

        // Final domain for this warehouse
        List<List<dynamic>> domain = List.from(baseDomain)
          ..add(['picking_type_id', 'in', pickingTypeIds]);

        // Total count for pagination
        final pickingCount = await CompanySessionManager.callKwWithCompany({
          'model': 'stock.picking',
          'method': 'search_count',
          'args': [domain],
          'kwargs': {},
        });
        totalPickingsCount[warehouseName] = pickingCount ?? 0;

        // Fields to fetch
        List<String> fields = [
          'id',
          'name',
          'scheduled_date',
          'date_deadline',
          'picking_type_code',
          'partner_id',
          'state',
          'move_type',
          'user_id',
          'location_id',
          'location_dest_id',
          'products_availability',
          'origin',
          'show_check_availability',
          'picking_type_id',
        ];
        if (version < 19) fields.add('group_id');

        // Fetch page of pickings
        final pickingItems = await CompanySessionManager.callKwWithCompany({
          'model': 'stock.picking',
          'method': 'search_read',
          'args': [domain],
          'kwargs': {'fields': fields, 'limit': pageSize, 'offset': offset},
        });

        // Flatten for UI
        final List<Map<String, dynamic>> mappedPickings =
            (pickingItems as List?)?.map((picking) {
              return {
                'id': picking['id'].toString(),
                'item': picking['name'],
                'scheduled_date': picking['scheduled_date'],
                'state': picking['state'],
                'origin': picking['origin'],
                'picking_type': picking['picking_type_id'] is List
                    ? picking['picking_type_id'][1]
                    : '',
                'partner_id': picking['partner_id'] is List
                    ? picking['partner_id'][1]
                    : '',
                'partner_id_int': picking['partner_id'] is List
                    ? picking['partner_id'][0].toString()
                    : '0',
                if (version < 19) ...{
                  'group_id': picking['group_id'] is List
                      ? picking['group_id'][1]
                      : '',
                  'group_id_int': picking['group_id'] is List
                      ? picking['group_id'][0].toString()
                      : '0',
                },
              };
            }).toList() ??
            [];

        allPickingsByLocation[warehouseName] = mappedPickings;
        hasNextPage[warehouseName] =
            (pickingCount ?? 0) > (page + 1) * pageSize;
      }
    } catch (_) {}
  }

  // ───────────────────────────────────────────────
  //  Offline / Hive Loading
  // ───────────────────────────────────────────────

  /// Loads and filters pickings from Hive when offline or as fast baseline
  ///
  /// Applies search, state, date, type filters directly on cached `Picking` objects.
  /// Groups results by `warehouseName` and updates pagination state for offline mode.
  Future<void> loadPickingsFromHive({
    required String searchTerm,
    required String? state,
    required DateTime? scheduleDate,
    required DateTime? deadlineDate,
    required String type,
  }) async {
    final box = Hive.box<Picking>('pickings');

    final List<Picking> localPickings = box.values.toList();
    List<Picking> filtered = localPickings;

    if (searchTerm.isNotEmpty) {
      final lower = searchTerm.toLowerCase();
      filtered = filtered.where((p) {
        return (p.item?.toLowerCase().contains(lower) ?? false);
      }).toList();
    }

    if (state != null && state.isNotEmpty) {
      filtered = filtered.where((p) => p.state == state).toList();
    }

    if (type.isNotEmpty) {
      filtered = filtered.where((p) => p.pickingTypeCode == type).toList();
    }

    if (scheduleDate != null) {
      final start = DateTime(
        scheduleDate.year,
        scheduleDate.month,
        scheduleDate.day,
      );
      final end = start
          .add(const Duration(days: 1))
          .subtract(const Duration(microseconds: 1));
      filtered = filtered.where((p) {
        if (p.scheduledDate == null) return false;
        final d = DateTime.parse(p.scheduledDate!);
        return d.isAfter(start) && d.isBefore(end);
      }).toList();
    }

    if (deadlineDate != null) {
      final start = DateTime(
        deadlineDate.year,
        deadlineDate.month,
        deadlineDate.day,
      );
      final end = start
          .add(const Duration(days: 1))
          .subtract(const Duration(microseconds: 1));
      filtered = filtered.where((p) {
        if (p.deadlineDate == null) return false;
        final d = DateTime.parse(p.deadlineDate!);
        return d.isAfter(start) && d.isBefore(end);
      }).toList();
    }

    final Map<String, List<Picking>> pickingsByWarehouse = {};

    for (final picking in filtered) {
      final warehouse = picking.warehouseName ?? 'Unknown';
      pickingsByWarehouse.putIfAbsent(warehouse, () => []).add(picking);
    }

    allPickingsByLocation.clear();
    totalPickingsCount.clear();
    hasNextPage.clear();

    const int pageSize = 40;

    for (final entry in pickingsByWarehouse.entries) {
      final warehouseName = entry.key;
      final List<Picking> warehousePickings = entry.value;

      final int offset = warehouseOffsets[warehouseName] ?? 0;

      final int end = (offset + pageSize).clamp(0, warehousePickings.length);
      final List<Picking> page = warehousePickings.sublist(offset, end);

      totalPickingsCount[warehouseName] = warehousePickings.length;
      hasNextPage[warehouseName] = end < warehousePickings.length;

      allPickingsByLocation[warehouseName] = page
          .map(
            (p) => <String, dynamic>{
              'id': p.id,
              'item': p.item,
              'scheduled_date': p.scheduledDate,
              'state': p.state,
              'partner_id': p.partner ?? '',
            },
          )
          .toList();
    }

    hasMorePickings
      ..clear()
      ..addAll(hasNextPage);
  }
}
