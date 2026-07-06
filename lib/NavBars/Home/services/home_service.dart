import '../../../core/company/session/company_session_manager.dart';
import '../models/home_attention_row.dart';

/// Read-only Odoo queries powering the Home screen.
///
/// Two RPCs per load:
///   1. `read_group` on `stock.picking` grouped by `state` — one round-trip
///      yielding all four tile counts. The Late count is a separate
///      `search_count` since "late" is a derived predicate, not a state.
///   2. `search_read` for the top 5 attention rows (late first, scheduled
///      ascending) — display fields only.
///
/// This service does not touch the pickings list, its bloc, or Hive. It
/// reuses `CompanySessionManager.callKwWithCompany` so every call is scoped
/// to the currently selected company just like the rest of the app.
class HomeService {
  /// Domain shared by every Home query — restrict to outgoing deliveries,
  /// matching the Pickings tab default. Filter chips from the list are NOT
  /// applied; Home always shows the full outgoing picture for the company.
  static const List<List<dynamic>> _outgoingDomain = [
    ['picking_type_code', '=', 'outgoing'],
  ];

  /// Returns counts for the four Home tiles:
  /// - `ready`     → `state = 'assigned'`
  /// - `waiting`   → `state in ('waiting', 'confirmed')`
  /// - `late`      → not-done/cancel AND overdue by deadline or scheduled
  /// - `doneToday` → `state = 'done' AND date_done within today (UTC)`
  Future<HomeCounts> fetchCounts() async {
    final grouped = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'read_group',
      'args': [_outgoingDomain, ['state'], ['state']],
      'kwargs': {},
    });

    int ready = 0, waiting = 0, doneToday = 0;
    if (grouped is List) {
      for (final row in grouped) {
        if (row is! Map) continue;
        final state = row['state']?.toString();
        final count = (row['state_count'] as num?)?.toInt() ?? 0;
        switch (state) {
          case 'assigned':
            ready += count;
            break;
          case 'waiting':
          case 'confirmed':
            waiting += count;
            break;
        }
      }
    }

    // Late — reuse the same predicate the Pickings 'late' chip uses so
    // Home and the filtered list stay consistent.
    final now = DateTime.now().toUtc();
    final nowTs = _odooTs(now);
    final lateDomain = <dynamic>[
      ..._outgoingDomain,
      '&',
      ['state', 'in', ['assigned', 'waiting', 'confirmed']],
      '|', '|',
      ['has_deadline_issue', '=', true],
      ['date_deadline', '<', nowTs],
      ['scheduled_date', '<', nowTs],
    ];
    final lateRaw = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'search_count',
      'args': [lateDomain],
      'kwargs': {},
    });
    final late = (lateRaw as int?) ?? 0;

    // Done today — same domain the Pickings 'donetoday' chip resolves to.
    final startOfDay = DateTime.utc(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final doneRaw = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'search_count',
      'args': [
        [
          ..._outgoingDomain,
          ['state', '=', 'done'],
          ['date_done', '>=', _odooTs(startOfDay)],
          ['date_done', '<', _odooTs(endOfDay)],
        ],
      ],
      'kwargs': {},
    });
    doneToday = (doneRaw as int?) ?? 0;

    return HomeCounts(
      ready: ready,
      waiting: waiting,
      late: late,
      doneToday: doneToday,
    );
  }

  /// Top attention rows, sorted late-first then by earliest deadline, then
  /// earliest scheduled date. Not-done/cancel outgoing pickings only. Only
  /// the fields the row card renders are fetched.
  Future<List<HomeAttentionRow>> fetchAttentionRows({int limit = 5}) async {
    final now = DateTime.now().toUtc();

    final domain = <dynamic>[
      ..._outgoingDomain,
      ['state', 'in', ['assigned', 'waiting', 'confirmed']],
    ];

    // Odoo ordering: single field, ascending — `scheduled_date` is always
    // populated on stock.picking, while `date_deadline` can be null and
    // some Odoo builds handle compound-order-with-nulls inconsistently.
    // We over-fetch and sort late-first client-side.
    final raw = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'search_read',
      'args': [domain, ['id', 'name', 'partner_id', 'state', 'scheduled_date', 'date_deadline']],
      'kwargs': {
        'limit': limit * 4,
        'order': 'scheduled_date asc',
      },
    });

    if (raw is! List) return const [];

    final rows = <HomeAttentionRow>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final id = (item['id'] as num?)?.toInt() ?? 0;
      final name = item['name']?.toString() ?? '';
      final partnerRaw = item['partner_id'];
      final partner = (partnerRaw is List && partnerRaw.length > 1)
          ? partnerRaw[1].toString()
          : '';
      final state = item['state']?.toString() ?? '';

      final deadlineRaw = item['date_deadline'];
      final scheduledRaw = item['scheduled_date'];
      final deadline = _parseOdoo(deadlineRaw);
      final scheduled = _parseOdoo(scheduledRaw);
      final due = deadline ?? scheduled;
      final isLate = due != null && due.isBefore(now);

      rows.add(HomeAttentionRow(
        id: id,
        reference: name,
        partner: partner,
        state: state,
        isLate: isLate,
        dueAt: due,
        dueFromDeadline: deadline != null,
      ));
    }

    rows.sort((a, b) {
      if (a.isLate != b.isLate) return a.isLate ? -1 : 1;
      final ad = a.dueAt;
      final bd = b.dueAt;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });

    return rows.take(limit).toList();
  }

  static String _odooTs(DateTime d) =>
      d.toIso8601String().replaceFirst('T', ' ').split('.').first;

  static DateTime? _parseOdoo(dynamic raw) {
    if (raw == null || raw == false) return null;
    final s = raw.toString();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse('${s.replaceFirst(' ', 'T')}Z');
    } catch (_) {
      return null;
    }
  }
}

/// Tile counts returned by [HomeService.fetchCounts].
class HomeCounts {
  final int ready;
  final int waiting;
  final int late;
  final int doneToday;

  const HomeCounts({
    required this.ready,
    required this.waiting,
    required this.late,
    required this.doneToday,
  });

  const HomeCounts.zero()
      : ready = 0,
        waiting = 0,
        late = 0,
        doneToday = 0;
}
