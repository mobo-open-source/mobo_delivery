import 'dart:async';

/// A simple event bus (broadcast stream) used to notify parts of the app
/// when the user profile has been updated or refreshed.
///
/// Typical use cases:
/// - After editing profile (name, image, address, etc.)
/// - After syncing profile from server
/// - When user logs in/out or switches company
///
/// Listeners can subscribe to [onProfileRefresh] to react to changes.
///
/// Example:
/// ```dart
///
/// ProfileRefreshBus.onProfileRefresh.listen((_) {
///
/// });
///
///
/// ProfileRefreshBus.notifyProfileRefresh();
/// ```
class ProfileRefreshBus {
  static final _profileController = StreamController<void>.broadcast();

  /// Stream that emits an event whenever the profile should be refreshed.
  static Stream<void> get onProfileRefresh => _profileController.stream;

  /// Notify all subscribers that the profile should be refreshed.
  ///
  /// Adds a `null` event to the stream, which triggers all listeners.
  static void notifyProfileRefresh() {
    _profileController.add(null);
  }
}
