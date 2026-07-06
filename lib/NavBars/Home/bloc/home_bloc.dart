import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/company/infrastructure/company_refresh_bus.dart';
import '../../../core/company/services/connectivity_service.dart';
import '../services/home_service.dart';
import 'home_event.dart';
import 'home_state.dart';

/// Bloc powering the Home screen.
///
/// Owns: tile counts, attention list, connectivity flag. Wires into two
/// existing streams:
///   - [ConnectivityService.instance.onInternetChanged] — flips the header
///     banner subtitle between "clear today's deliveries" / "working offline".
///   - [CompanyRefreshBus.stream] — reloads when the operator switches
///     company via the AppBar selector.
///
/// Only reads Odoo. Sync (pending count + "Sync now") lives in the Dashboard
/// AppBar's cloud-upload badge; Home no longer duplicates it.
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final HomeService _service;

  StreamSubscription<bool>? _internetSub;
  StreamSubscription<void>? _companySub;

  HomeBloc({HomeService? service})
      : _service = service ?? HomeService(),
        super(const HomeState.initial()) {
    on<LoadHome>(_onLoad);
    on<ConnectivityChanged>(_onConnectivityChanged);

    _internetSub = ConnectivityService.instance.onInternetChanged.listen((up) {
      add(ConnectivityChanged(up));
    });
    _companySub = CompanyRefreshBus.stream.listen((_) {
      add(const LoadHome(forceRefresh: true));
    });
  }

  Future<void> _onLoad(LoadHome event, Emitter<HomeState> emit) async {
    emit(state.copyWith(status: HomeStatus.loading, clearError: true));
    try {
      final results = await Future.wait([
        _service.fetchCounts(),
        _service.fetchAttentionRows(limit: 5),
      ]);
      final counts = results[0] as HomeCounts;
      final rows = results[1] as List;

      emit(state.copyWith(
        status: HomeStatus.loaded,
        counts: counts,
        attention: rows.cast(),
        clearError: true,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: HomeStatus.error,
        errorMessage: 'Could not load dashboard: $e',
      ));
    }
  }

  void _onConnectivityChanged(
      ConnectivityChanged event, Emitter<HomeState> emit) {
    if (state.online == event.online) return;
    emit(state.copyWith(online: event.online));
    // Coming back online → refresh data.
    if (event.online) add(const LoadHome(forceRefresh: true));
  }

  @override
  Future<void> close() {
    _internetSub?.cancel();
    _companySub?.cancel();
    return super.close();
  }
}
