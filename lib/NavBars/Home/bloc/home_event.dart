import 'package:equatable/equatable.dart';

/// Events accepted by [HomeBloc]. All events are triggered by the Home screen
/// itself — either from a lifecycle hook (initial load), from a user gesture
/// (pull-to-refresh, sync now), or from listeners on shared buses
/// (`CompanyRefreshBus` on company switch, connectivity stream).
abstract class HomeEvent extends Equatable {
  const HomeEvent();
  @override
  List<Object?> get props => const [];
}

/// Initial or forced load — fires counts + attention list from Odoo.
class LoadHome extends HomeEvent {
  /// When `true`, ignores any Hive cache and forces an Odoo hit. Used by
  /// pull-to-refresh.
  final bool forceRefresh;
  const LoadHome({this.forceRefresh = false});
  @override
  List<Object?> get props => [forceRefresh];
}

/// Internal — fired by the bloc when connectivity flips so the header banner
/// can swap its "online / offline" subtitle.
class ConnectivityChanged extends HomeEvent {
  final bool online;
  const ConnectivityChanged(this.online);
  @override
  List<Object?> get props => [online];
}
