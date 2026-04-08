import 'package:equatable/equatable.dart';

/// Immutable state class for `ReturnManagementBloc`.
///
/// Holds all UI-relevant data for the return management screen:
/// - Loading & pagination flags
/// - List of return-eligible pickings (raw + filtered)
/// - Grouping data (when active)
/// - Search/filter/group parameters
/// - Error messages
/// - Highlight animation state
///
/// Uses `Equatable` for efficient state comparison (only rebuilds when actual data changes).
/// Provides `copyWith` for immutable updates and `pageRange` computed getter for UI display.
class ReturnManagementState extends Equatable {
  final bool isLoading;
  final bool isFetchingMore;
  final List<Map<String, dynamic>> pickings;
  final List<Map<String, dynamic>> filteredPickings;
  final int currentPage;
  final int? highlightedPickingId;
  final String? error;
  final Map<String, List<Map<String, dynamic>>> groupedPickings;
  final Map<String, bool> groupExpanded;
  final List<String> filters;
  final String? groupBy;

  final int totalCount;
  final int displayedCount;
  final String? searchText;
  static const int itemsPerPage = 40;


  const ReturnManagementState({
    this.isLoading = true,
    this.isFetchingMore = false,
    this.pickings = const [],
    this.filteredPickings = const [],
    this.currentPage = 0,
    this.highlightedPickingId,
    this.error,
    this.totalCount = 0,
    this.displayedCount = 0,
    this.searchText,
    this.groupedPickings = const {},
    this.groupExpanded = const {},
    this.filters = const [],
    this.groupBy
  });

  /// Computed getter: returns human-readable page range string
  /// (e.g. "1-40", "41-80", "1-12" for last partial page)
  String get pageRange {
    if (totalCount == 0) return '0-0';
    final start = currentPage * itemsPerPage + 1;
    final maxEnd = start + itemsPerPage - 1;
    final safeUpperBound = totalCount < start ? start : totalCount;
    final end = maxEnd.clamp(start, safeUpperBound);
    return '$start-$end';
  }

  /// Creates a new state instance with updated values
  /// (immutable update pattern — only changed fields are provided)
  ReturnManagementState copyWith({
    bool? isLoading,
    bool? isFetchingMore,
    List<Map<String, dynamic>>? pickings,
    List<Map<String, dynamic>>? filteredPickings,
    int? currentPage,
    int? highlightedPickingId,
    String? error,
    int? totalCount,
    int? displayedCount,
    String? searchText,
    Map<String, List<Map<String, dynamic>>>? groupedPickings,
    Map<String, bool>? groupExpanded,
    List<String>? filters,
    String? groupBy,
  }) {
    return ReturnManagementState(
      isLoading: isLoading ?? this.isLoading,
      isFetchingMore: isFetchingMore ?? this.isFetchingMore,
      pickings: pickings ?? this.pickings,
      filteredPickings: filteredPickings ?? this.filteredPickings,
      currentPage: currentPage ?? this.currentPage,
      highlightedPickingId: highlightedPickingId ?? this.highlightedPickingId,
      error: error,
      totalCount: totalCount ?? this.totalCount,
      displayedCount: displayedCount ?? this.displayedCount,
      searchText: searchText ?? this.searchText,
      groupedPickings: groupedPickings ?? this.groupedPickings,
      groupExpanded: groupExpanded ?? this.groupExpanded,
      filters: filters ?? this.filters,
      groupBy: groupBy ?? this.groupBy,
    );
  }

  /// Equality props — used by Equatable to decide when to rebuild UI
  @override
  List<Object?> get props => [
    isLoading,
    isFetchingMore,
    pickings,
    filteredPickings,
    currentPage,
    highlightedPickingId,
    error,
    totalCount,
    displayedCount,
    searchText,
    groupedPickings,
    groupExpanded,
    filters,
    groupBy,
  ];
}