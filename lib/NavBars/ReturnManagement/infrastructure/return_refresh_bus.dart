import 'dart:async';

/// Broadcast event bus notifying the Return Management list when a return
/// has been created elsewhere in the app (e.g. from a picking's own detail
/// page, which never touches the list's own bloc and would otherwise leave
/// it stale). Carries the new picking's id, when known, so the list can
/// highlight it.
class ReturnRefreshBus {
  static final _controller = StreamController<int?>.broadcast();

  /// Stream that emits an event whenever a return has just been created,
  /// carrying its id when the caller has one.
  static Stream<int?> get onReturnCreated => _controller.stream;

  /// Notify all subscribers that a return was just created.
  static void notifyReturnCreated([int? pickingId]) {
    _controller.add(pickingId);
  }
}
