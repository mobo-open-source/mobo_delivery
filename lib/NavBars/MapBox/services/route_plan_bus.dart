import 'dart:async';

/// Global bus used by the Home screen (and any future entry point) to ask the
/// Route Visualization page to open its "Enter Route" bottom sheet.
///
/// Mirrors the [PickingsFilterBus] / [CompanyRefreshBus] pattern:
/// broadcast stream, static publisher. Home publishes AFTER the tab switch's
/// first frame, so `RouteVisualizationPage` is on-screen when its listener
/// fires and calls `_showEnterRootPopup()` through its existing flow — no new
/// screen, no restyled sheet.
class RoutePlanBus {
  static final _controller = StreamController<void>.broadcast();

  /// Stream of "open Enter Route" requests.
  static Stream<void> get stream => _controller.stream;

  /// Publish an "open Enter Route" request.
  static void request() {
    _controller.add(null);
  }
}
