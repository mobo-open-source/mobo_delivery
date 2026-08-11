import 'package:equatable/equatable.dart';

import '../models/home_attention_row.dart';
import '../services/home_service.dart';

/// Loading phase of the Home screen. `loading` shows skeletons; `loaded`
/// paints the real data; `error` shows whatever cached data we have plus a
/// snackbar/error banner.
enum HomeStatus { loading, loaded, error }

/// Immutable state of the Home screen.
class HomeState extends Equatable {
  final HomeStatus status;
  final HomeCounts counts;
  final List<HomeAttentionRow> attention;
  final bool online;

  /// Human-friendly error message when [status] == error. `null` otherwise.
  final String? errorMessage;

  const HomeState({
    required this.status,
    required this.counts,
    required this.attention,
    required this.online,
    required this.errorMessage,
  });

  const HomeState.initial()
    : status = HomeStatus.loading,
      counts = const HomeCounts.zero(),
      attention = const [],
      online = true,
      errorMessage = null;

  HomeState copyWith({
    HomeStatus? status,
    HomeCounts? counts,
    List<HomeAttentionRow>? attention,
    bool? online,
    String? errorMessage,
    bool clearError = false,
  }) {
    return HomeState(
      status: status ?? this.status,
      counts: counts ?? this.counts,
      attention: attention ?? this.attention,
      online: online ?? this.online,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, counts, attention, online, errorMessage];
}
