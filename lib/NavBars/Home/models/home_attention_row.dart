/// A single row in the Home screen's "Needs attention" list.
///
/// Populated from a light `search_read` of `stock.picking` (just the fields
/// needed for display + navigation). Not the same as the full `Picking` Hive
/// model used by the Pickings list — this is a minimal DTO for Home only.
class HomeAttentionRow {
  /// Odoo id of the `stock.picking`.
  final int id;

  /// Display reference, e.g. `My Co/OUT/00042`.
  final String reference;

  /// Partner display name.
  final String partner;

  /// Odoo state — one of `assigned`, `waiting`, `confirmed`.
  final String state;

  /// True if the picking is late by either `date_deadline` or `scheduled_date`.
  final bool isLate;

  /// Best-effort due timestamp for display — `date_deadline` if set,
  /// otherwise `scheduled_date`.
  final DateTime? dueAt;

  /// Whether `dueAt` came from `date_deadline` (`true`) or from
  /// `scheduled_date` (`false`).
  final bool dueFromDeadline;

  const HomeAttentionRow({
    required this.id,
    required this.reference,
    required this.partner,
    required this.state,
    required this.isLate,
    required this.dueAt,
    required this.dueFromDeadline,
  });

  /// Display label for the status chip.
  String get statusLabel {
    if (isLate) return 'Late';
    if (state == 'assigned') return 'Ready';
    return 'Waiting';
  }
}
