import 'package:equatable/equatable.dart';

/// Base event class for ReturnManagementBloc
abstract class ReturnManagementEvent extends Equatable {
  const ReturnManagementEvent();

  @override
  List<Object?> get props => [];
}

/// Initialize screen & load initial data
class InitializeReturnManagement extends ReturnManagementEvent {
  final bool forceRefresh;
  const InitializeReturnManagement({this.forceRefresh = false});

  @override
  List<Object?> get props => [forceRefresh];
}

/// Fetch paginated return-eligible pickings
class FetchStockPickings extends ReturnManagementEvent {
  final int currentPage;
  final String? searchText;
  final List<String>? filters;
  final String? groupBy;

  const FetchStockPickings(
    this.currentPage, {
    this.searchText,
    this.filters,
    this.groupBy,
  });

  @override
  List<Object?> get props => [currentPage, searchText, filters, groupBy];
}

/// Apply search query (triggers fetch)
class SearchPickings extends ReturnManagementEvent {
  final String query;

  SearchPickings(this.query);

  @override
  List<Object?> get props => [query];
}

/// Temporarily highlight a picking in UI
class HighlightPicking extends ReturnManagementEvent {
  final int? pickingId;

  const HighlightPicking(this.pickingId);

  @override
  List<Object?> get props => [pickingId];
}
