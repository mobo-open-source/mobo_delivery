import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_ce/hive.dart';

import '../../../../core/company/session/company_session_manager.dart';
import '../models/picking_model.dart';
import '../../PickingFormPage/models/picking_form.dart';

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

  Map<String, List<Map<String, dynamic>>> allPickingsByLocation = {};
  Map<String, List<Map<String, dynamic>>> previousPickingsByLocation = {};
  Map<String, int> currentPage = {};
  Map<String, bool> hasNextPage = {};
  Map<String, int> totalPickingsCount = {};

  /// Global picking count matching the current domain — computed via ONE
  /// `search_count` on the full domain so it doesn't depend on all per-warehouse
  /// fetches completing under the initial timeout.
  int globalPickingCount = 0;

  final int pageSize = 40;

  /// Clears all pagination-related state (pages, offsets, hasMore flags)
  void clearPaginationState() {
    currentPage.clear();
    hasNextPage.clear();
    totalPickingsCount.clear();
    globalPickingCount = 0;
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

    if (connectivityResult.any((r) => r != ConnectivityResult.none)) {
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
    bool forceRefresh = false,
  }) async {
    final isConnected = await checkNetworkConnectivity();
    isDataFromHive = !isConnected;

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
  List<dynamic> buildFilterDomain(List<String> filters, int uid) {
    final List<dynamic> domain = [];

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
          final now = DateTime.now()
              .toUtc()
              .toString()
              .replaceFirst('Z', '')
              .trim();
          domain.addAll([
            '&',
            [
              'state',
              'in',
              ['assigned', 'waiting', 'confirmed'],
            ],
            '|',
            '|',
            ['has_deadline_issue', '=', true],
            ['date_deadline', '<', now],
            ['scheduled_date', '<', now],
          ]);
          break;

        case 'planning_issue':
          final now = DateTime.now()
              .toUtc()
              .toString()
              .replaceFirst('Z', '')
              .trim();
          domain.addAll([
            '|',
            ['delay_alert_date', '!=', false],
            '&',
            ['scheduled_date', '<', now],
            [
              'state',
              'in',
              ['assigned', 'waiting', 'confirmed'],
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

        case 'donetoday':
          final now = DateTime.now();
          final startOfDay = DateTime.utc(now.year, now.month, now.day);
          final endOfDay = startOfDay.add(const Duration(days: 1));
          String odooTs(DateTime d) =>
              d.toIso8601String().replaceFirst('T', ' ').split('.').first;
          domain.addAll([
            ['state', '=', 'done'],
            ['date_done', '>=', odooTs(startOfDay)],
            ['date_done', '<', odooTs(endOfDay)],
          ]);
          break;
      }
    }

    return domain;
  }

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

      List<dynamic> baseDomain = [];
      final session = await CompanySessionManager.getCurrentSession();
      final uid = session!.userId;

      final hasExplicitTypeChip =
          filters != null &&
          filters.any(
            (f) => f == 'receipt' || f == 'deliveries' || f == 'internal',
          );

      if (filters != null && filters.isNotEmpty) {
        baseDomain.addAll(buildFilterDomain(filters, uid!));
      }
      if (searchTerm != null && searchTerm.isNotEmpty) {
        baseDomain.add(['name', 'ilike', searchTerm]);
      }
      if (!hasExplicitTypeChip && type != null && type.isNotEmpty) {
        baseDomain.add(['picking_type_code', '=', type]);
      }

      try {
        final count = await CompanySessionManager.callKwWithCompany({
          'model': 'stock.picking',
          'method': 'search_count',
          'args': [baseDomain],
          'kwargs': {},
        });
        globalPickingCount = (count as int?) ?? 0;
      } catch (_) {}

      final warehouseTasks = <Future<void>>[];
      for (var warehouse in warehouseItems ?? []) {
        final String warehouseName = warehouse['name'];
        final int warehouseId = warehouse['id'] is int
            ? warehouse['id']
            : int.parse(warehouse['id'].toString());

        final int page =
            pageOverrides?[warehouseName] ?? currentPage[warehouseName] ?? 0;
        final int offset = page * pageSize;
        currentPage[warehouseName] = page;

        warehouseTasks.add(
          _fetchWarehousePickings(
            warehouseName: warehouseName,
            warehouseId: warehouseId,
            page: page,
            offset: offset,
            baseDomain: baseDomain,
            type: type,
            hasExplicitTypeChip: hasExplicitTypeChip,
            version: version,
          ),
        );
      }

      await Future.wait(warehouseTasks);
    } on OdooSessionExpiredException {
      rethrow;
    } catch (_) {}
  }

  /// Fetches one warehouse's pickings — picking types first, then count
  /// and search_read in parallel. Writes its slice of state into
  /// `allPickingsByLocation`, `totalPickingsCount`, `hasNextPage` on
  /// completion. Per-warehouse failures degrade to empty state without
  /// blocking other warehouses; session expiry is rethrown so the caller
  /// can log the user out.
  Future<void> _fetchWarehousePickings({
    required String warehouseName,
    required int warehouseId,
    required int page,
    required int offset,
    required List<dynamic> baseDomain,
    required String? type,
    required bool hasExplicitTypeChip,
    required int version,
  }) async {
    try {
      final pickingTypes = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking.type',
        'method': 'search_read',
        'args': [
          [
            ['warehouse_id', '=', warehouseId],
            if (!hasExplicitTypeChip && type != null && type.isNotEmpty)
              ['code', '=', type],
          ],
        ],
        'kwargs': {
          'fields': ['id'],
        },
      });

      final List<int> pickingTypeIds =
          (pickingTypes as List?)
              ?.map((e) => int.parse(e['id'].toString()))
              .toList() ??
          [];
      if (pickingTypeIds.isEmpty) {
        allPickingsByLocation[warehouseName] = [];
        hasNextPage[warehouseName] = false;
        totalPickingsCount[warehouseName] = 0;
        return;
      }

      final List<dynamic> domain = List.from(baseDomain)
        ..add(['picking_type_id', 'in', pickingTypeIds]);

      final List<String> fields = [
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

      final results = await Future.wait<dynamic>([
        CompanySessionManager.callKwWithCompany({
          'model': 'stock.picking',
          'method': 'search_count',
          'args': [domain],
          'kwargs': {},
        }),
        CompanySessionManager.callKwWithCompany({
          'model': 'stock.picking',
          'method': 'search_read',
          'args': [domain],
          'kwargs': {'fields': fields, 'limit': pageSize, 'offset': offset},
        }),
      ]);
      final pickingCount = results[0];
      final pickingItems = results[1];
      totalPickingsCount[warehouseName] = pickingCount ?? 0;

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
              'picking_type_code': type ?? 'outgoing',
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
      hasNextPage[warehouseName] = (pickingCount ?? 0) > (page + 1) * pageSize;
    } on OdooSessionExpiredException {
      rethrow;
    } catch (_) {
      allPickingsByLocation[warehouseName] = [];
      totalPickingsCount[warehouseName] = 0;
      hasNextPage[warehouseName] = false;
    }
  }

  /// Loads and filters pickings from Hive when offline or as fast baseline
  ///
  /// Applies search, state, date, type filters directly on cached `Picking` objects.
  /// Groups results by `warehouseName` and updates pagination state for offline mode.
  Future<void> clearLocalCache() async {
    allPickingsByLocation.clear();
    totalPickingsCount.clear();
    hasNextPage.clear();
    hasMorePickings.clear();
    warehouseOffsets.clear();
    previousPickingsByLocation.clear();

    if (Hive.isBoxOpen('pickings')) {
      await Hive.box<Picking>('pickings').clear();
    }
    if (Hive.isBoxOpen('stock_picking_return_box')) {
      await Hive.box<PickingForm>('stock_picking_return_box').clear();
    }
    if (Hive.isBoxOpen('stock_picking_box')) {
      await Hive.box<PickingForm>('stock_picking_box').clear();
    }
  }
}
