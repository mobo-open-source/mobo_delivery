import 'package:flutter_bloc/flutter_bloc.dart';
import '../services/odoo_return_service.dart';
import '../../Pickings/PickingFormPage/services/hive_service.dart';
import 'return_management_event.dart';
import 'return_management_state.dart';

/// BLoC responsible for managing the return pickings screen state and business logic.
///
/// Handles:
/// • Initialization & data loading (online + Hive cache fallback)
/// • Paginated fetching of return-eligible pickings
/// • Filtering (search, presets like "Late", "Backorders")
/// • Grouping (by status, origin, type)
/// • Creating new return pickings via wizard
/// • Highlighting newly created returns temporarily
///
/// Uses `OdooReturnManagementService` for RPC calls and `HiveService` for offline caching.
/// Emits rich state updates including loading flags, errors, filtered/grouped data, and pagination info.
class ReturnManagementBloc
    extends Bloc<ReturnManagementEvent, ReturnManagementState> {
  final OdooReturnManagementService odooService;
  final HiveService hiveService;

  ReturnManagementBloc(this.odooService, this.hiveService)
    : super(const ReturnManagementState()) {
    on<InitializeReturnManagement>(_onInitialize);
    on<FetchStockPickings>(_onFetchStockPickings);
    on<CreateReturn>(_onCreateReturn);
    on<HighlightPicking>(_onHighlightPicking);

    // Search is handled inline (debounced in UI) but triggers fetch
    on<SearchPickings>((event, emit) async {
      try {
        // Count matching items (used for pagination total)
        final filteredCount = await odooService.StockCount(
          searchText: event.query,
        );

        // Client-side filter for instant feedback (while fetching full page)
        final filtered = state.pickings.where((p) {
          final name = p['name']?.toString().toLowerCase() ?? '';
          final location = (p['partner_id'] != null && p['partner_id'] is List)
              ? p['partner_id'][1].toString().toLowerCase()
              : '';
          final searchLower = event.query.toLowerCase();
          return name.contains(searchLower) || location.contains(searchLower);
        }).toList();

        // Adjust displayed count based on page size
        final displayedCount =
            filteredCount > OdooReturnManagementService.itemsPerPage
            ? filtered.length.clamp(0, OdooReturnManagementService.itemsPerPage)
            : filteredCount;
        emit(
          state.copyWith(
            filteredPickings: filtered,
            searchText: event.query,
            displayedCount: displayedCount,
            totalCount: filteredCount,
            currentPage: 0,
          ),
        );

        // Trigger full paginated fetch with search applied
        add(
          FetchStockPickings(
            0,
            searchText: event.query,
            filters: state.filters,
            groupBy: state.groupBy,
          ),
        );
      } catch (e) {
        emit(state.copyWith(error: 'Failed to apply search: $e'));
      }
    });
  }

  /// Initializes the BLoC: loads session, Hive, cached returns, and triggers first fetch
  Future<void> _onInitialize(
    InitializeReturnManagement event,
    Emitter<ReturnManagementState> emit,
  ) async {
    try {
      emit(state.copyWith(isLoading: true));

      // Ensure Odoo client & Hive are ready
      odooService.initializeClient();
      await hiveService.initialize();

      // Load cached returns first for instant offline UX
      final hivePickings = await hiveService.getReturnPickings();
      int totalCount = await hiveService.getTotalCount();
      if (hivePickings.isNotEmpty) {
        emit(
          state.copyWith(
            pickings: hivePickings.map((p) => p.toJson()).toList(),
            displayedCount: hivePickings.length,
            isFetchingMore: false,
            totalCount: totalCount,
          ),
        );
      }

      // Fetch fresh data (will update cache if online)
      add(FetchStockPickings(0));
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          isFetchingMore: false,
          error: 'Initialization failed: $e',
        ),
      );
    }
  }

  /// Fetches paginated return-eligible pickings (usually done state) with filters/search/grouping
  Future<void> _onFetchStockPickings(
    FetchStockPickings event,
    Emitter<ReturnManagementState> emit,
  ) async {
    try {
      emit(
        state.copyWith(isFetchingMore: true),
      );

      // Get total count for pagination UI
      final count = await odooService.StockCount(
        searchText: event.searchText,
        filters: event.filters,
      );
      await hiveService.saveTotalCount(count);

      // Fetch current page
      final items = await odooService.fetchStockPickings(
        event.currentPage,
        searchText: event.searchText,
        filters: event.filters,
      );
      if (items.isNotEmpty) {
        await hiveService.saveReturnPickings(items);
      }

      // Apply client-side search filter for instant UI feedback
      final searchLower = event.searchText?.toLowerCase() ?? '';
      final filtered = searchLower.isNotEmpty
          ? items.where((p) {
              final name = p['name']?.toString().toLowerCase() ?? '';
              final location =
                  (p['partner_id'] != null && p['partner_id'] is List)
                  ? p['partner_id'][1].toString().toLowerCase()
                  : '';
              return name.contains(searchLower) ||
                  location.contains(searchLower);
            }).toList()
          : items;

      // Build grouped data if grouping is active
      Map<String, List<Map<String, dynamic>>> grouped = {};
      Map<String, bool> expanded = {};

      if (event.groupBy != null && event.groupBy!.isNotEmpty) {
        for (final item in items) {
          String key = _getGroupKey(item, event.groupBy!);
          grouped.putIfAbsent(key, () => []);
          grouped[key]!.add(item);
          expanded.putIfAbsent(key, () => true);
        }
      }

      // Calculate new displayed count (handles pagination append/prepend)
      final newDisplayedCount = event.currentPage == 0
          ? filtered
                .length
          : event.currentPage > state.currentPage
          ? state.displayedCount +
                filtered
                    .length
          : state.displayedCount - (state.filteredPickings.length);

      emit(
        state.copyWith(
          pickings: items,
          filteredPickings: filtered,
          isLoading: false,
          isFetchingMore: false,
          searchText: event.searchText,
          currentPage: event.currentPage,
          totalCount: count ?? 0,
          displayedCount: newDisplayedCount.clamp(0, count ?? 0),
          filters: event.filters ?? [],
          groupBy: event.groupBy,
          groupedPickings: grouped,
          groupExpanded: expanded,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isFetchingMore: false,
          isLoading: false,
          error: 'Failed to fetch stock pickings: $e',
        ),
      );
    }
  }

  String capitalizeFirstLetter(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  /// Helper to generate group key based on selected field
  String _getGroupKey(Map<String, dynamic> item, String field) {
    final value = item[field];

    if (field == 'state') {
      return capitalizeFirstLetter(value) ?? value ?? 'Unknown';
    }
    if (field == 'partner_id' && value is List && value.length > 1) {
      return value[1].toString();
    }
    if (field == 'origin') {
      return value?.toString() ?? 'No Source';
    }
    if (field == 'picking_type_id' && value is List && value.length > 1) {
      return value[1].toString();
    }
    return value?.toString() ?? 'Unknown';
  }

  /// Creates a new return picking from selected move lines
  Future<void> _onCreateReturn(
    CreateReturn event,
    Emitter<ReturnManagementState> emit,
  ) async {
    try {
      await odooService.createReturn(event.pickingId, event.returnLines);

      // Refresh current page to show updated list
      add(FetchStockPickings(state.currentPage));

      // Highlight the new return briefly
      add(HighlightPicking(event.pickingId));

    } catch (e) {
      emit(state.copyWith(error: 'Failed to create return: $e'));
    }
  }

  /// Temporarily highlights a picking (e.g. after return creation)
  Future<void> _onHighlightPicking(
    HighlightPicking event,
    Emitter<ReturnManagementState> emit,
  ) async {
    emit(state.copyWith(highlightedPickingId: event.pickingId));
    await Future.delayed(const Duration(seconds: 2));
    emit(state.copyWith(highlightedPickingId: null));
  }
}
