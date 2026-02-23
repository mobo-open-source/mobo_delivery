import 'package:equatable/equatable.dart';

/// Base class for all events in the AttachDocuments BLoC.
///
/// All events must extend this class to ensure proper equality comparison
/// (via Equatable) and to maintain a consistent event hierarchy.
///
/// This helps with:
///   - Debugging (better toString output)
///   - State management predictability
///   - Preventing unnecessary rebuilds when events are equal
abstract class AttachDocumentsEvent extends Equatable {
  const AttachDocumentsEvent();

  @override
  List<Object?> get props => [];
}

/// Event triggered once when the AttachDocuments screen is first created.
///
/// Purpose:
///   - Initialize Odoo client connection
///   - Set up Hive for offline caching
///   - Load any cached data as a quick first render
///   - Trigger the initial fetch of stock pickings
///
/// This is usually added automatically in the BLoC constructor or widget init.
class InitializeAttachDocuments extends AttachDocumentsEvent {
  const InitializeAttachDocuments();
}

/// Event used to load previously cached pickings when operating offline.
///
/// This event bypasses the network layer and directly populates the UI
/// with Hive-cached data for the requested page and total count.
///
/// Typically emitted after navigation (e.g. page change) when no internet is available.
class LoadOfflineDocuments extends AttachDocumentsEvent {
  final List<Map<String, dynamic>> pickings;
  final int currentPage;
  final int totalCount;

  LoadOfflineDocuments({
    required this.pickings,
    required this.currentPage,
    required this.totalCount,
  });
}

/// Main event for fetching paginated stock pickings from Odoo (or triggering offline load).
///
/// Supports:
///   - Pagination (page + itemsPerPage)
///   - Search by query
///   - Multiple filters (status, type, etc.)
///   - Optional grouping (by status, origin, operation type)
///
/// When offline, the UI layer usually falls back to cached data instead of using this event directly.
class FetchDocumentStockPickings extends AttachDocumentsEvent {
  final int page;
  final int itemsPerPage;
  final String? searchQuery;
  final List<String>? filters;
  final String? groupBy;

  const FetchDocumentStockPickings(this.page, this.itemsPerPage, {
    this.searchQuery,
    this.filters,
    this.groupBy,
  });

  @override
  List<Object?> get props => [page, itemsPerPage, searchQuery, filters, groupBy];
}

/// Event triggered when the user uploads a file or signature for a specific picking.
///
/// Carries the base64-encoded content, MIME type, original filename,
/// and the target picking ID to attach the file to (usually via Odoo chatter/attachments).
class UploadFile extends AttachDocumentsEvent {
  final String mimeType;
  final String base64File;
  final int pickingId;
  final String fileName;

  const UploadFile(this.mimeType, this.base64File, this.pickingId, this.fileName);

  @override
  List<Object?> get props => [mimeType, base64File, pickingId, fileName];
}