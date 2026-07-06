import 'package:flutter/foundation.dart';

/// Reactive flag exposing whether live route navigation is active on the
/// Route tab.
///
/// [RouteVisualizationPage] mirrors its private `_isNavigationStarted` state
/// into this notifier every time it flips. The Dashboard shell listens via
/// `ValueListenableBuilder` and hides the shared AppBar while navigation is
/// running — the page's own `NavigationHeader` overlay takes over the top
/// slot, so no duplicate top bar and ~56px more map viewport.
///
/// Same broadcast-static pattern used by [PickingsFilterBus], [RoutePlanBus],
/// [CompanyRefreshBus] — no new global-state framework.
class RouteNavigationBus {
  static final ValueNotifier<bool> isNavigating = ValueNotifier<bool>(false);

  /// Publish the current nav state. Called from within
  /// `RouteVisualizationPage` alongside every write to `_isNavigationStarted`.
  static void set(bool value) {
    if (isNavigating.value == value) return;
    isNavigating.value = value;
  }
}
