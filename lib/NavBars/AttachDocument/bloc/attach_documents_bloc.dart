import 'package:flutter_bloc/flutter_bloc.dart';
import '../../Pickings/PickingFormPage/services/hive_service.dart';
import 'attach_documents_event.dart';
import 'attach_documents_state.dart';
import '../services/odoo_attach_service.dart';

/// BLoC responsible for managing the state of the document attachment screen.
///
/// Handles:
///   - Initialization and connectivity setup
///   - Fetching paginated stock pickings (online + offline fallback via Hive)
///   - Filtering, searching, grouping
///   - Uploading files/signatures to Odoo chatter/attachments
///   - Error handling and loading states
class AttachDocumentsBloc extends Bloc<AttachDocumentsEvent, AttachDocumentsState> {
  final OdooAttachService _odooService;
  final HiveService _hiveService;
  final int itemsPerPage;

  String? searchQuery;
  DateTime? scheduledDate;
  String? type;

  AttachDocumentsBloc({
    required OdooAttachService odooService,
    required HiveService hiveService,
    this.itemsPerPage = 40,
  })  : _odooService = odooService,
        _hiveService = hiveService,
        super(AttachDocumentsInitial()) {
    on<InitializeAttachDocuments>(_onInitialize);
    on<FetchDocumentStockPickings>(_onFetchDocumentStockPickings);
    on<UploadFile>(_onUploadFile);
    on<LoadOfflineDocuments>(_onLoadOfflineDocuments);
  }

  /// Initializes services, loads cached data if available, and triggers initial fetch.
  ///
  /// Sequence:
  ///   1. Initializes Odoo client & Hive
  ///   2. Loads cached pickings & total count from Hive
  ///   3. Attempts to get fresh total count from server
  ///   4. Emits loaded state with cached data (if any)
  ///   5. Triggers first page fetch
  ///
  /// Falls back to cached data on initialization failure.
  Future<void> _onInitialize(
      InitializeAttachDocuments event,
      Emitter<AttachDocumentsState> emit,
      ) async {
    emit(AttachDocumentsLoading());
    try {
      await _odooService.initializeClient();
      await _hiveService.initialize();

      final cachedPickings = await _hiveService.getPickings();
      int totalCount = await _hiveService.getTotalCount();

      totalCount = await _odooService.StockCount();

      if (cachedPickings.isNotEmpty) {
        final pickings = cachedPickings.map((p) => p.toJson() as Map<String, dynamic>).toList();
        emit(AttachDocumentsLoaded(
          pickings: pickings,
          currentPage: 0,
          displayedCount: totalCount > itemsPerPage ? pickings.length.clamp(0, itemsPerPage) : totalCount,
          totalCount: totalCount,
        ));
      }

      add(const FetchDocumentStockPickings(0, 10));
    } catch (e) {
      int totalCount = await _hiveService.getTotalCount();
      final cachedPickings = await _hiveService.getPickings();
      if (cachedPickings.isNotEmpty) {
        final pickings = cachedPickings.map((p) => p.toJson() as Map<String, dynamic>).toList();
        emit(AttachDocumentsLoaded(
          pickings: pickings,
          totalCount: totalCount,
          currentPage: 0,
        ));
      }
    }
  }

  /// Loads previously cached offline pickings into the loaded state.
  ///
  /// Used when user navigates pages while offline and cached data exists.
  /// Directly emits loaded state with provided pickings, page, and total count.
  Future<void> _onLoadOfflineDocuments(
      LoadOfflineDocuments event,
      Emitter<AttachDocumentsState> emit,
      ) async {
    emit(AttachDocumentsLoaded(
      pickings: event.pickings,
      currentPage: event.currentPage,
      displayedCount: event.pickings.length,
      totalCount: event.totalCount,
    ));
  }

  /// Capitalizes the first letter of a string (used for group keys).
  String capitalizeFirstLetter(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  /// Generates a display-friendly group key based on the selected grouping field.
  ///
  /// Special handling for:
  ///   - 'state' → capitalized label
  ///   - 'partner_id' / 'picking_type_id' → takes display name from list [id, name]
  ///   - 'origin' → source document or fallback
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

  /// Fetches paginated stock pickings from Odoo (or Hive offline fallback).
  ///
  /// Flow:
  ///   1. Emits loading-more state with previous data
  ///   2. Gets fresh total count from server
  ///   3. Fetches new page of pickings
  ///   4. Saves to Hive for offline use
  ///   5. Builds grouped data if groupBy is set
  ///   6. Emits updated loaded state
  ///
  /// On error: emits error state while preserving previous pickings
  Future<void> _onFetchDocumentStockPickings(
      FetchDocumentStockPickings event,
      Emitter<AttachDocumentsState> emit,
      ) async {
    searchQuery = event.searchQuery;

    try {
      emit(
      AttachDocumentsLoaded(
        pickings: state is AttachDocumentsLoaded
            ? (state as AttachDocumentsLoaded).pickings
            : state is AttachDocumentsFileUploaded
            ? (state as AttachDocumentsFileUploaded).pickings
            : state is AttachDocumentsError
            ? (state as AttachDocumentsError).pickings
            : [],
        currentPage: event.page,
        isFetchingMore: true,
        displayedCount: state is AttachDocumentsLoaded
            ? (state as AttachDocumentsLoaded).displayedCount
            : state is AttachDocumentsFileUploaded
            ? (state as AttachDocumentsFileUploaded).displayedCount
            : state is AttachDocumentsError
            ? (state as AttachDocumentsError).displayedCount
            : 0,
        totalCount: state is AttachDocumentsLoaded
            ? (state as AttachDocumentsLoaded).totalCount
            : state is AttachDocumentsFileUploaded
            ? (state as AttachDocumentsFileUploaded).totalCount
            : state is AttachDocumentsError
            ? (state as AttachDocumentsError).totalCount
            : 0,
      ));

      final totalCount = await _odooService.StockCount(
        searchText: event.searchQuery,
        filters: event.filters,
      );
      await _hiveService.saveTotalCount(totalCount);

      final newPickingsDynamic = await _odooService.fetchAttachmentStockPickings(
        event.page,
        event.itemsPerPage,
        searchQuery: event.searchQuery,
        filters: event.filters,
        groupBy: event.groupBy,
      );

      final newPickings = newPickingsDynamic.map((item) => item as Map<String, dynamic>).toList();

      final displayedCount = (event.page * itemsPerPage + newPickings.length).clamp(0, totalCount);

      await _hiveService.savePickings(newPickings);
      Map<String, List<Map<String, dynamic>>> grouped = {};

      if (event.groupBy != null && event.groupBy!.isNotEmpty) {
        for (var p in newPickings) {
          String key = _getGroupKey(p, event.groupBy!);
          grouped.putIfAbsent(key, () => []).add(p);
        }
      }

      emit(AttachDocumentsLoaded(
        pickings: newPickings,
        currentPage: event.page,
        isFetchingMore: false,
        displayedCount: displayedCount,
        totalCount: totalCount,
        groupedPickings: grouped,
      ));
    } catch (e) {
      emit(AttachDocumentsError(
        'Failed to fetch pickings: $e',
        pickings: state is AttachDocumentsLoaded
            ? (state as AttachDocumentsLoaded).pickings
            : state is AttachDocumentsFileUploaded
            ? (state as AttachDocumentsFileUploaded).pickings
            : state is AttachDocumentsError
            ? (state as AttachDocumentsError).pickings
            : [],
        isFetchingMore: false,
        currentPage: event.page,
        displayedCount: state is AttachDocumentsLoaded
            ? (state as AttachDocumentsLoaded).displayedCount
            : state is AttachDocumentsFileUploaded
            ? (state as AttachDocumentsFileUploaded).displayedCount
            : state is AttachDocumentsError
            ? (state as AttachDocumentsError).displayedCount
            : 0,
        totalCount: state is AttachDocumentsLoaded
            ? (state as AttachDocumentsLoaded).totalCount
            : state is AttachDocumentsFileUploaded
            ? (state as AttachDocumentsFileUploaded).totalCount
            : state is AttachDocumentsError
            ? (state as AttachDocumentsError).totalCount
            : 0,
      ));
    }
  }

  /// Handles file/signature upload to Odoo chatter/attachment system.
  ///
  /// Preserves current list state during upload.
  /// On success → emits FileUploaded state with success flag
  /// On failure → emits Error state with preserved list
  /// Also tracks the event via ReviewService for analytics.
  Future<void> _onUploadFile(
      UploadFile event,
      Emitter<AttachDocumentsState> emit,
      ) async {
    final currentState = state;
    final isFetchingMore = currentState is AttachDocumentsLoaded
        ? currentState.isFetchingMore
        : currentState is AttachDocumentsFileUploaded
        ? currentState.isFetchingMore
        : currentState is AttachDocumentsError
        ? currentState.isFetchingMore
        : false;
    final pickings = currentState is AttachDocumentsLoaded
        ? (currentState as AttachDocumentsLoaded).pickings
        : currentState is AttachDocumentsFileUploaded
        ? (currentState as AttachDocumentsFileUploaded).pickings
        : currentState is AttachDocumentsError
        ? (currentState as AttachDocumentsError).pickings
        : <Map<String, dynamic>>[];
    final displayedCount = currentState is AttachDocumentsLoaded
        ? currentState.displayedCount
        : currentState is AttachDocumentsFileUploaded
        ? currentState.displayedCount
        : currentState is AttachDocumentsError
        ? currentState.displayedCount
        : 0;
    final totalCount = currentState is AttachDocumentsLoaded
        ? currentState.totalCount
        : currentState is AttachDocumentsFileUploaded
        ? currentState.totalCount
        : currentState is AttachDocumentsError
        ? currentState.totalCount
        : 0;
    final currentPage = currentState is AttachDocumentsLoaded
        ? currentState.currentPage
        : currentState is AttachDocumentsFileUploaded
        ? currentState.currentPage
        : currentState is AttachDocumentsError
        ? currentState.currentPage
        : 0;

    try {
      await _odooService.uploadFileToChatter(
        event.mimeType,
        event.base64File,
        event.pickingId,
        event.fileName,
      );
      emit(AttachDocumentsFileUploaded(
        success: true,
        message: 'File uploaded successfully',
        pickings: pickings,
        isFetchingMore: isFetchingMore,
        currentPage: currentPage,
        displayedCount: displayedCount,
        totalCount: totalCount,
      ));
    } catch (e) {
      emit(AttachDocumentsError(
        'Failed to upload file: $e',
        pickings: pickings,
        isFetchingMore: isFetchingMore,
        currentPage: currentPage,
        displayedCount: displayedCount,
        totalCount: totalCount,
      ));
    }
  }
}