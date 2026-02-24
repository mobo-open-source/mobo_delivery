import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// Base class for all events in the DashboardBloc.
///
/// All events must extend this class to ensure proper equality comparison
/// (via Equatable) which is required for correct Bloc behavior.
abstract class DashboardEvent extends Equatable {
  const DashboardEvent();

  @override
  List<Object?> get props => [];
}

/// Triggered when the dashboard is first opened or needs full initialization.
///
/// Usually dispatched right after the Dashboard widget is created.
/// Carries the desired starting tab index.
class InitializeDashboard extends DashboardEvent {
  /// The index of the tab that should be shown initially
  /// (0 = first tab, usually "Pickings")
  final int initialIndex;
  const InitializeDashboard(this.initialIndex);
}

/// Event to change the currently active bottom navigation tab.
class ChangeTab extends DashboardEvent {
  /// The new tab index to switch to
  final int index;
  const ChangeTab(this.index);
}

/// Load the user profile (usually from cache/storage).
///
/// This event is typically used when the UI needs to display profile data
/// but doesn't necessarily require a fresh network fetch.
class LoadUserProfile extends DashboardEvent {}

/// Force a refresh of the user profile data.
///
/// Usually dispatched after:
///   • Company switch
///   • Profile/configuration screen changes
///   • Manual pull-to-refresh (if implemented)
class RefreshUserProfile extends DashboardEvent {}

/// Update the profile picture in the dashboard state.
///
/// This event is useful when:
///   • User uploads/changes their avatar in the configuration screen
///   • Profile picture is refreshed from a different source
class UpdateProfilePicture extends DashboardEvent {
  /// The new profile picture as raw bytes (usually PNG/JPEG)
  final Uint8List bytes;
  const UpdateProfilePicture(this.bytes);
}
