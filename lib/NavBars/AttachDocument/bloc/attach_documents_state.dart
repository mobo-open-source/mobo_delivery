import 'package:equatable/equatable.dart';

/// Base class for all states in the AttachDocuments BLoC.
///
/// Defines common behavior and properties:
///   - `groupedPickings`: map used when grouping is active
///   - `isGrouped`: convenience getter to check if results are grouped
///
/// All concrete states extend this class to ensure proper equality comparison
/// (via Equatable) and consistent access to grouped data across the UI.
abstract class AttachDocumentsState extends Equatable {
  const AttachDocumentsState();

  Map<String, List<Map<String, dynamic>>> get groupedPickings => {};

  bool get isGrouped => groupedPickings.isNotEmpty;

  @override
  List<Object?> get props => [];
}

/// Initial empty state before any data is loaded or initialization begins.
///
/// Used as the starting point of the BLoC.
/// UI typically shows a loading indicator or skeleton when in this state.
class AttachDocumentsInitial extends AttachDocumentsState {}

/// Loading state shown during initial data fetch or refresh.
///
/// Usually displays a full-screen shimmer/grid loading animation.
class AttachDocumentsLoading extends AttachDocumentsState {}

/// Main success state containing the list of stock pickings and pagination info.
///
/// Supports both flat list view and grouped view (when `groupedPickings` is populated).
/// Includes metadata for pagination UI (current page, total count, displayed range).
class AttachDocumentsLoaded extends AttachDocumentsState {
  final List<Map<String, dynamic>> pickings;
  final int currentPage;
  final bool isFetchingMore;
  final int displayedCount;
  final int totalCount;
  static const int itemsPerPage = 40;
  final Map<String, List<Map<String, dynamic>>> groupedPickings;

  const AttachDocumentsLoaded({
    required this.pickings,
    this.currentPage = 0,
    this.isFetchingMore = false,
    this.displayedCount = 0,
    this.totalCount = 0,
    this.groupedPickings = const {},
  });

  /// Generates human-readable page range string (e.g. "1-40", "41-80", "81-85")
  ///
  /// Handles edge cases:
  ///   - Zero items → "0-0"
  ///   - Last page with fewer items → correct upper bound
  String get pageRange {
    if (totalCount == 0) return '0-0';
    final start = currentPage * itemsPerPage + 1;
    final maxEnd = start + itemsPerPage - 1;
    final safeUpperBound = totalCount < start ? start : totalCount;
    final end = maxEnd.clamp(start, safeUpperBound);
    return '$start-$end';
  }

  @override
  List<Object?> get props => [
    pickings,
    currentPage,
    isFetchingMore,
    displayedCount,
    totalCount,
    groupedPickings,
  ];
}

/// Transient success state emitted after a successful file/signature upload.
///
/// Preserves the current list of pickings and pagination info so the UI
/// doesn't flicker or lose scroll position. Carries success flag and message.
class AttachDocumentsFileUploaded extends AttachDocumentsState {
  final bool success;
  final String message;
  final List<Map<String, dynamic>> pickings;
  final bool isFetchingMore;
  final int displayedCount;
  final int totalCount;
  final int currentPage;
  final Map<String, List<Map<String, dynamic>>> groupedPickings;

  const AttachDocumentsFileUploaded({
    required this.success,
    required this.message,
    required this.pickings,
    this.isFetchingMore = false,
    this.displayedCount = 0,
    this.totalCount = 0,
    this.currentPage = 0,
    this.groupedPickings = const {},
  });

  @override
  List<Object?> get props => [
    success,
    message,
    pickings,
    isFetchingMore,
    displayedCount,
    totalCount,
    currentPage,
    groupedPickings,
  ];
}

/// Error state containing an error message and preserved previous data.
///
/// Allows the UI to:
///   - Show error banner/snackbar
///   - Keep displaying the last successful list
///   - Offer retry or offline fallback options
class AttachDocumentsError extends AttachDocumentsState {
  final String message;
  final List<Map<String, dynamic>> pickings;
  final bool isFetchingMore;
  final int displayedCount;
  final int totalCount;
  final int currentPage;
  final Map<String, List<Map<String, dynamic>>> groupedPickings;

  const AttachDocumentsError(
    this.message, {
    required this.pickings,
    this.isFetchingMore = false,
    this.displayedCount = 0,
    this.totalCount = 0,
    this.currentPage = 0,
    this.groupedPickings = const {},
  });

  @override
  List<Object?> get props => [
    message,
    pickings,
    isFetchingMore,
    displayedCount,
    totalCount,
    currentPage,
    groupedPickings,
  ];
}
