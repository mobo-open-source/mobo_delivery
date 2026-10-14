import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/company/session/company_session_manager.dart';
import '../../../shared/utils/odoo_version.dart';
import '../models/home_attention_row.dart';

/// Read-only Odoo queries powering the Home screen.
///
/// Two RPCs per load:
///   1. `read_group` on `stock.picking` grouped by `state` — one round-trip
///      yielding the Ready and Waiting counts, in whichever dialect the
///      server speaks (Odoo 20 changed both its parameters and its return
///      type), falling back to one `search_count` per state. The Late count
///      is a separate `search_count` since "late" is a derived predicate,
///      not a state.
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
    int doneToday = 0;
    final byState = await _countsByState();
    final ready = byState['assigned'] ?? 0;
    final waiting = (byState['waiting'] ?? 0) + (byState['confirmed'] ?? 0);

    final now = DateTime.now().toUtc();
    final nowTs = _odooTs(now);
    final lateDomain = <dynamic>[
      ..._outgoingDomain,
      '&',
      [
        'state',
        'in',
        ['assigned', 'waiting', 'confirmed'],
      ],
      '|',
      '|',
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

  /// Picking counts per state for the Home tiles.
  ///
  /// One `read_group` round-trip, in whichever dialect this server speaks,
  /// falling back to one `search_count` per state if anything about the
  /// answer is not what was expected.
  ///
  /// Odoo 20 kept the name `read_group` for a method with different
  /// parameters and a different return type, so the two dialects are not
  /// interchangeable. Verified against both servers: each raises on the
  /// other's call — Odoo 19 answers `Invalid field '__count'`, Odoo 20
  /// answers `Aggregate method is mandatory for 'state'`.
  ///
  /// Because those are raised rather than silently mis-answered, the version
  /// only has to be right for the screen to stay fast. If it is wrong, or the
  /// reply is a shape neither parser recognises, the counts are gathered one
  /// state at a time instead, which is slower but cannot report a wrong
  /// number.
  Future<Map<String, int>> _countsByState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final major = prefs.getInt('version') ?? 0;
      final counts = odooReadGroupReturnsTuples(major)
          ? await _countsByStateTuples()
          : await _countsByStateDicts();
      if (counts != null) return counts;
    } catch (_) {
      // Fall through to the per-state counts below.
    }
    return _countsByStateIndividually();
  }

  /// Odoo 20+: `read_group(domain, groupby, aggregates)` returning a list of
  /// `(group_value, aggregate_value)` tuples — here `('assigned', 12)`.
  /// Returns null if the shape is not that, so the caller can fall back.
  Future<Map<String, int>?> _countsByStateTuples() async {
    final grouped = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'read_group',
      'args': [
        _outgoingDomain,
        ['state'],
        ['__count'],
      ],
      'kwargs': {},
    });
    if (grouped is! List) return null;
    final counts = <String, int>{};
    for (final row in grouped) {
      if (row is! List || row.length < 2) return null;
      final state = row[0];
      final count = row[1];
      if (state is! String || count is! num) return null;
      counts[state] = count.toInt();
    }
    return counts;
  }

  /// Odoo 19 and earlier: `read_group(domain, fields, groupby)` returning a
  /// list of dicts carrying `state` and the `state_count` aggregate.
  /// Returns null if the shape is not that, so the caller can fall back.
  Future<Map<String, int>?> _countsByStateDicts() async {
    final grouped = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'read_group',
      'args': [
        _outgoingDomain,
        ['state'],
        ['state'],
      ],
      'kwargs': {},
    });
    if (grouped is! List) return null;
    final counts = <String, int>{};
    for (final row in grouped) {
      if (row is! Map) return null;
      final state = row['state'];
      final count = row['state_count'];
      if (state is! String || count is! num) return null;
      counts[state] = count.toInt();
    }
    return counts;
  }

  /// Counts each state with its own `search_count`. Slower, but the call has
  /// been stable across every Odoo release the app supports.
  Future<Map<String, int>> _countsByStateIndividually() async {
    const states = ['assigned', 'waiting', 'confirmed'];
    final counts = <String, int>{};
    for (final state in states) {
      final raw = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'search_count',
        'args': [
          [
            ..._outgoingDomain,
            ['state', '=', state],
          ],
        ],
        'kwargs': {},
      });
      counts[state] = raw is num ? raw.toInt() : 0;
    }
    return counts;
  }

  /// Top attention rows, sorted late-first then by earliest deadline, then
  /// earliest scheduled date. Not-done/cancel outgoing pickings only. Only
  /// the fields the row card renders are fetched.
  Future<List<HomeAttentionRow>> fetchAttentionRows({int limit = 5}) async {
    final now = DateTime.now().toUtc();

    final domain = <dynamic>[
      ..._outgoingDomain,
      [
        'state',
        'in',
        ['assigned', 'waiting', 'confirmed'],
      ],
    ];

    final raw = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'search_read',
      'args': [
        domain,
        [
          'id',
          'name',
          'partner_id',
          'state',
          'scheduled_date',
          'date_deadline',
        ],
      ],
      'kwargs': {'limit': limit * 4, 'order': 'scheduled_date asc'},
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

      rows.add(
        HomeAttentionRow(
          id: id,
          reference: name,
          partner: partner,
          state: state,
          isLate: isLate,
          dueAt: due,
          dueFromDeadline: deadline != null,
        ),
      );
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

  const HomeCounts.zero() : ready = 0, waiting = 0, late = 0, doneToday = 0;
}
