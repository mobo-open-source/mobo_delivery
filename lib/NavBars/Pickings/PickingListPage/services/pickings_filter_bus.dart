import 'dart:async';

/// Global bus used by the Home screen to request the Pickings list to apply
/// a preset filter chip before showing itself.
///
/// Mirrors the [CompanyRefreshBus] pattern: broadcast stream, static publisher.
/// The chip name is one of the existing keys understood by
/// `PickingService.buildFilterDomain` (e.g. `'ready'`, `'waiting'`, `'late'`,
/// `'donetoday'`). `null` clears any previously applied Home-driven filter.
///
/// This is intentionally a tiny signal — no filter-configured "new screen"
/// is created; the existing `PickingsGroupedPage` listens and applies the
/// chip through its regular `_selectedFilters` flow.
class PickingsFilterBus {
  static final _controller = StreamController<String?>.broadcast();

  /// Stream of chip names to apply. Emits `null` to clear.
  static Stream<String?> get stream => _controller.stream;

  /// Publish a chip to apply on the Pickings list.
  static void request(String? chip) {
    _controller.add(chip);
  }
}
