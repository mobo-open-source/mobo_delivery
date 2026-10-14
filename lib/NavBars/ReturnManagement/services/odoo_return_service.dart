import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/company/session/company_session_manager.dart';
import '../../../shared/utils/odoo_domain_error.dart';
import '../../../shared/utils/odoo_version.dart';

/// Service layer for managing **return pickings** (reverse transfers / customer returns) in Odoo.
///
/// Handles:
/// • Counting & fetching paginated return-eligible pickings
/// • Building filter domains for presets ("My Transfer", "Already Returned", etc.)
/// • Fetching move lines from a picking
/// • Creating return pickings — through the `stock.return.picking` wizard up
///   to Odoo 19, and through `stock.picking.action_return()` from Odoo 20,
///   which deleted that wizard and moved returns onto the picking itself
///
/// Version-aware logic included (different return creation methods before/after
/// Odoo 18, and a different mechanism entirely from Odoo 20).
/// Throws meaningful exceptions on failure for UI error handling.
class OdooReturnManagementService {
  static const int itemsPerPage = 40;
  int? userId;
  String url = '';

  /// Ensures Odoo session is active — must be called before any RPC
  Future<void> initializeClient() async {
    final session = await CompanySessionManager.getCurrentSession();
    if (session == null) throw Exception("No active session");
  }

  /// Major Odoo version of the connected server, or 0 when unknown.
  Future<int> _serverMajorVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('version') ?? 0;
  }

  /// Builds Odoo domain clauses from user-friendly filter presets
  ///
  /// The presets offered here — operation type, ownership, return status and
  /// date range — are the ones that stay meaningful across every row the list
  /// shows (see [_returnsDomain]), which is dominated by completed transfers.
  /// Used for both count and search_read operations.
  List<dynamic> buildFilterDomain(List<String> filters, int uid) {
    final List<dynamic> domain = [];

    for (final filter in filters) {
      switch (filter) {
        case 'my_transfer':
          domain.add(['user_id', '=', uid]);
          break;

        case 'receipt':
          domain.add(['picking_type_code', '=', 'incoming']);
          break;

        case 'deliveries':
          domain.add(['picking_type_code', '=', 'outgoing']);
          break;

        case 'internal':
          domain.add(['picking_type_code', '=', 'internal']);
          break;

        case 'has_return':
          domain.add(['return_ids', '!=', false]);
          break;

        case 'no_return':
          domain.add(['return_ids', '=', false]);
          break;

        case 'this_week':
          domain.add(['scheduled_date', '>=', _formatDate(_startOfWeek())]);
          break;

        case 'this_month':
          domain.add(['scheduled_date', '>=', _formatDate(_startOfMonth())]);
          break;

        case 'warning':
          domain.add(['activity_exception_decoration', '!=', false]);
          break;
      }
    }

    return domain;
  }

  DateTime _startOfWeek() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - 1));
  }

  DateTime _startOfMonth() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  String _formatDate(DateTime date) {
    return date.toUtc().toString().replaceFirst('Z', '').trim();
  }

  /// Completed transfers (the ones a return can be created *from*) plus every
  /// actual return record regardless of state. The second clause matters:
  /// Odoo's return wizard creates the return in `confirmed`/`assigned`, never
  /// `done`, so a `state = 'done'` domain alone can never show a return that
  /// was just created.
  ///
  /// `return_id` ("Return of") is the field Odoo itself sets on a return
  /// picking to point back at the picking it returns — present on
  /// `stock.picking` in 17, 18 and 19 alike (verified against Odoo's own
  /// source, not assumed). An earlier version of this domain used
  /// `origin_returned_picking_id`, a field that does not exist anywhere in
  /// stock's model — every query silently fell back to [_doneOnlyDomain]
  /// below, so returns never actually showed before they were validated.
  static const List<dynamic> _returnsDomain = [
    '|',
    ['state', '=', 'done'],
    ['return_id', '!=', false],
  ];

  /// Fallback for a deployment where `return_id` has been removed or
  /// renamed by a customization; preserves the original done-only
  /// behaviour rather than failing the list outright.
  static const List<dynamic> _doneOnlyDomain = [
    ['state', '=', 'done'],
  ];

  bool _isMissingReturnField(Object e) =>
      e.toString().toLowerCase().contains('return_id');

  /// Filters the server refused to search on during the last fetch.
  ///
  /// Populated when Odoo rejects the domain itself (see
  /// [isUnsupportedDomainError]) and the query is retried without filters,
  /// so the UI can say which filter this server does not support instead of
  /// reporting that the whole list failed.
  List<String> unsupportedFilters = [];

  /// Runs [attempt] with the chosen filters, and again without them if this
  /// server rejects the domain they produce.
  Future<T> _withFilterFallback<T>(
    List<String>? filters,
    Future<T> Function(List<String>? filters) attempt,
  ) async {
    try {
      final result = await attempt(filters);
      unsupportedFilters = [];
      return result;
    } catch (e) {
      if (!isUnsupportedDomainError(e) || filters == null || filters.isEmpty) {
        rethrow;
      }
      unsupportedFilters = List<String>.from(filters);
      return await attempt(null);
    }
  }

  List<dynamic> _buildDomain(
    List<dynamic> base,
    String? searchText,
    List<String>? filters,
    int? uid,
  ) {
    final domain = List<dynamic>.from(base);
    if (searchText != null && searchText.isNotEmpty) {
      domain.add(['name', 'ilike', searchText]);
    }
    if (filters != null && filters.isNotEmpty) {
      domain.addAll(buildFilterDomain(filters, uid!));
    }
    return domain;
  }

  /// Counts the rows the returns list shows (see [_returnsDomain]) matching filters/search
  ///
  /// Used for pagination total count and progress indicators.
  /// Throws exception on RPC failure for UI error handling.
  Future<int> StockCount({String? searchText, List<String>? filters}) async {
    try {
      final session = await CompanySessionManager.getCurrentSession();
      final uid = session!.userId;

      Future<dynamic> count(List<dynamic> base, List<String>? active) {
        return CompanySessionManager.callKwWithCompany({
          'model': 'stock.picking',
          'method': 'search_count',
          'args': [_buildDomain(base, searchText, active, uid)],
          'kwargs': {},
        });
      }

      final pickingCount = await _withFilterFallback(filters, (active) async {
        try {
          return await count(_returnsDomain, active);
        } catch (e) {
          if (_isMissingReturnField(e)) {
            return await count(_doneOnlyDomain, active);
          }
          rethrow;
        }
      });
      return pickingCount ?? 0;
    } catch (e) {
      throw Exception('Failed to count stock pickings: $e');
    }
  }

  /// Fetches the paginated returns list (see [_returnsDomain])
  ///
  /// Supports search, custom filters, and pagination via offset/limit.
  /// Returns flattened list of maps ready for UI display.
  /// Throws exception on failure.
  Future<List<Map<String, dynamic>>> fetchStockPickings(
    int currentPage, {
    String? searchText,
    List<String>? filters,
  }) async {
    try {
      final offset = currentPage * itemsPerPage;
      final session = await CompanySessionManager.getCurrentSession();
      final uid = session!.userId;

      const baseFields = [
        'id',
        'name',
        'state',
        'origin',
        'partner_id',
        'scheduled_date',
        'picking_type_id',
        'picking_type_code',
        'return_count',
      ];

      Future<dynamic> search(
        List<dynamic> base,
        List<String> fields,
        List<String>? active,
      ) {
        return CompanySessionManager.callKwWithCompany({
          'model': 'stock.picking',
          'method': 'search_read',
          'args': [_buildDomain(base, searchText, active, uid)],
          'kwargs': {'fields': fields, 'limit': itemsPerPage, 'offset': offset},
        });
      }

      final pickingItems = await _withFilterFallback(filters, (active) async {
        try {
          return await search(_returnsDomain, [
            ...baseFields,
            'return_id',
          ], active);
        } catch (e) {
          if (_isMissingReturnField(e)) {
            return await search(_doneOnlyDomain, baseFields, active);
          }
          rethrow;
        }
      });
      return List<Map<String, dynamic>>.from(pickingItems ?? []);
    } catch (e) {
      throw Exception('Failed to fetch stock pickings: $e');
    }
  }

  /// Fetches the returnable moves for a picking using Odoo's
  /// `stock.return.picking` wizard as the calculator. The wizard's
  /// onchange/compute on `picking_id` populates `product_return_moves`
  /// with the correct returnable quantity per line — already accounting
  /// for previously-returned units, pending reservations, cancelled
  /// moves, etc. — so the bottom sheet pre-fills match Odoo's web UI.
  ///
  /// Returns line maps shaped as `{id, product_id, quantity, move_id, uom_id}`.
  /// Throws on failure.
  Future<List<Map<String, dynamic>>> fetchReturnableMoves(int pickingId) async {
    // Computed from the moves on every version, not read from the wizard.
    //
    // Odoo's wizard deliberately starts each line at zero — the operator is
    // meant to count what actually came back rather than accept a prefilled
    // number — but it also never says how much *may* be returned, so nothing
    // stopped someone entering five against a line with three left. Odoo's
    // own web wizard shows that limit in a "Move Quantity" column beside the
    // field; this is the equivalent, and it keeps the figure identical
    // whether the server still has the wizard or not.
    return _returnableMovesFromMoves(pickingId);
  }

  /// Creates a new return picking via Odoo's `stock.return.picking`
  /// wizard. Replaces the wizard's auto-populated lines with the
  /// user-supplied ones, then triggers return creation (method differs
  /// pre/post Odoo 18). Returns the new return picking's id — both
  /// `create_returns` (17) and `action_create_returns` (18/19) hand back an
  /// `ir.actions.act_window` with `res_id` set to it (verified against
  /// Odoo's own source) — or `null` if that id could not be determined.
  /// Throws on RPC / wizard failure.
  Future<int?> createReturn(
    int pickingId,
    List<List<Object>> returnLines,
  ) async {
    if (returnLines.isEmpty) {
      throw Exception('No quantity specified for return.');
    }

    final prefs = await SharedPreferences.getInstance();
    final int version = prefs.getInt('version') ?? 0;

    if (!odooUsesReturnWizard(version)) {
      return _createReturnV20(pickingId, returnLines);
    }

    final createResult = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.return.picking',
      'method': 'create',
      'args': [
        {'picking_id': pickingId},
      ],
      'kwargs': {
        'context': {'active_id': pickingId, 'active_model': 'stock.picking'},
      },
    });

    final int wizardId;
    if (createResult is int) {
      wizardId = createResult;
    } else if (createResult is List && createResult.isNotEmpty) {
      final first = createResult.first;
      if (first is int) {
        wizardId = first;
      } else if (first is Map) {
        wizardId = first['id'] as int;
      } else {
        throw Exception('Unexpected wizard id type: ${first.runtimeType}');
      }
    } else {
      throw Exception('Failed to create return wizard.');
    }

    final List<dynamic> replacementLines = [
      [5, 0, 0],
      ...returnLines,
    ];

    await CompanySessionManager.callKwWithCompany({
      'model': 'stock.return.picking',
      'method': 'write',
      'args': [
        [wizardId],
        {'product_return_moves': replacementLines},
      ],
      'kwargs': {},
    });

    final method = version < 18 ? 'create_returns' : 'action_create_returns';
    final actionResult = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.return.picking',
      'method': method,
      'args': [
        [wizardId],
      ],
      'kwargs': {},
    });

    if (actionResult is Map) {
      final resId = actionResult['res_id'];
      if (resId is int) return resId;
    }
    return null;
  }

  /// How much of each line may still be returned, on any Odoo version.
  ///
  /// Mirrors what `stock.picking.action_return_all()` does on the server
  /// (`addons/stock/models/stock_picking.py`): a line's returnable quantity
  /// is the quantity actually moved, less whatever has already been returned
  /// against it. Odoo finds the latter by looking at the move's destination
  /// moves and keeping those whose `origin_returned_move_id` points back at
  /// it.
  ///
  /// Read-only, and required to stay that way. Odoo 20 has no transient
  /// wizard to ask, and its replacement creates a *real* draft picking —
  /// doing that merely to populate a sheet the user may well cancel would
  /// leave stray returns behind.
  ///
  /// Lines with nothing left are omitted, so a fully returned picking opens
  /// the sheet on its "No returnable items" state instead of offering a line
  /// that cannot be acted on.
  ///
  /// Shape: `{id, product_id, quantity, move_id, uom_id}`, where `quantity`
  /// is the remaining amount — shown to the operator as a limit, never
  /// prefilled into the field.
  Future<List<Map<String, dynamic>>> _returnableMovesFromMoves(
    int pickingId,
  ) async {
    final uomField = stockMoveUomField(await _serverMajorVersion());

    final movesRaw = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.move',
      'method': 'search_read',
      'args': [
        [
          ['picking_id', '=', pickingId],
          // Done moves only, which is Odoo's own rule — its wizard refuses
          // outright with "You may only return Done pickings". Without this
          // the sheet would offer to return goods that have not been
          // delivered yet, since the Return action is reachable from a
          // picking that is merely Ready.
          ['state', '=', 'done'],
        ],
      ],
      'kwargs': {
        'fields': ['id', 'product_id', 'quantity', uomField, 'move_dest_ids'],
      },
    });
    if (movesRaw is! List || movesRaw.isEmpty) return const [];

    final moves = movesRaw.whereType<Map>().toList();

    // Everything these moves feed into, so already-returned quantities can be
    // subtracted. One read for all of them rather than one per line.
    final destIds = <int>{
      for (final move in moves)
        ...(move['move_dest_ids'] as List? ?? const []).whereType<int>(),
    }.toList();

    List<Map> destMoves = const [];
    if (destIds.isNotEmpty) {
      final destRaw = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.move',
        'method': 'read',
        'args': [
          destIds,
          ['origin_returned_move_id', 'quantity', 'product_uom_qty', 'state'],
        ],
        'kwargs': {},
      });
      if (destRaw is List) destMoves = destRaw.whereType<Map>().toList();
    }

    return returnableLinesFromMoves(
      moves: moves,
      destinationMoves: destMoves,
      uomField: uomField,
    );
  }

  /// Creates a return on Odoo 20, where `stock.return.picking` no longer
  /// exists.
  ///
  /// `stock.picking.action_return()` copies the picking into a draft return
  /// whose moves each carry `origin_returned_move_id` back to the line they
  /// came from. Those links are what lets the user's quantities be matched to
  /// the right new move. Lines the user left blank are set to zero rather
  /// than deleted, which is how Odoo's own screen leaves them.
  ///
  /// If anything after the return is created fails, the draft is removed
  /// again — leaving a half-filled return behind would be worse than
  /// reporting the failure, because the user would have no way to tell it
  /// apart from a real one.
  Future<int?> _createReturnV20(
    int pickingId,
    List<List<Object>> returnLines,
  ) async {
    final wanted = returnQuantitiesByMoveId(returnLines);
    if (wanted.isEmpty) {
      throw Exception('No quantity specified for return.');
    }

    final action = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'action_return',
      'args': [
        [pickingId],
      ],
      'kwargs': {
        'context': {'active_id': pickingId, 'active_model': 'stock.picking'},
      },
    });

    final newPickingId = action is Map ? firstOdooId(action['res_id']) : null;
    if (newPickingId == null) {
      throw Exception('Odoo did not return the new return picking.');
    }

    try {
      final movesRaw = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.move',
        'method': 'search_read',
        'args': [
          [
            ['picking_id', '=', newPickingId],
          ],
        ],
        'kwargs': {
          'fields': ['id', 'origin_returned_move_id'],
        },
      });
      if (movesRaw is! List) {
        throw Exception('Could not read the new return picking lines.');
      }

      var matched = 0;
      for (final move in movesRaw.whereType<Map>()) {
        final moveId = firstOdooId(move['id']);
        if (moveId == null) continue;
        final origin = firstOdooId(move['origin_returned_move_id']);
        final qty = origin == null ? null : wanted[origin];
        if (qty != null) matched++;
        await CompanySessionManager.callKwWithCompany({
          'model': 'stock.move',
          'method': 'write',
          'args': [
            [moveId],
            {'product_uom_qty': qty ?? 0},
          ],
          'kwargs': {},
        });
      }

      if (matched == 0) {
        throw Exception(
          'None of the selected lines could be matched on the return.',
        );
      }
      return newPickingId;
    } catch (_) {
      await _discardDraftReturn(newPickingId);
      rethrow;
    }
  }

  /// Removes a draft return that could not be completed. Best effort: the
  /// original failure is what the user needs to hear, so a cleanup that
  /// itself fails must not replace it.
  Future<void> _discardDraftReturn(int pickingId) async {
    try {
      await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'unlink',
        'args': [
          [pickingId],
        ],
        'kwargs': {},
      });
    } catch (_) {}
  }
}

/// Returnable quantity per line, given a picking's moves and everything those
/// moves feed into.
///
/// Extracted so the arithmetic can be tested without a server. It follows
/// `stock.picking.action_return_all()` in Odoo 20: a line can be returned to
/// the extent it was moved, less what has already come back against it, which
/// Odoo identifies by `origin_returned_move_id` pointing at the original move.
///
/// Lines with nothing left to return are omitted rather than shown as zero,
/// matching what the wizard produced on earlier versions.
List<Map<String, dynamic>> returnableLinesFromMoves({
  required List<Map> moves,
  required List<Map> destinationMoves,
  required String uomField,
}) {
  final returnedByOrigin = <int, double>{};
  for (final dest in destinationMoves) {
    final origin = firstOdooId(dest['origin_returned_move_id']);
    if (origin == null) continue;
    final claimed = claimedByReturnMove(dest);
    if (claimed <= 0) continue;
    returnedByOrigin[origin] = (returnedByOrigin[origin] ?? 0) + claimed;
  }

  final lines = <Map<String, dynamic>>[];
  for (final move in moves) {
    final moveId = firstOdooId(move['id']);
    if (moveId == null) continue;
    final moved = (move['quantity'] as num?)?.toDouble() ?? 0;
    final returnable = moved - (returnedByOrigin[moveId] ?? 0);
    if (returnable <= 0) continue;
    lines.add({
      // The wizard path keys lines by their own line id; with no wizard the
      // move id is the stable identifier, and the sheet only ever reads it
      // back out of `move_id`.
      'id': moveId,
      'product_id': move['product_id'],
      'quantity': returnable,
      'move_id': moveId,
      'uom_id': move[uomField],
    });
  }
  return lines;
}

/// The quantity wanted per original move id, from the sheet's Odoo
/// `(0, 0, {...})` create commands.
///
/// Lines without a positive quantity, or without a usable move id, are
/// dropped; repeats for one move are summed.
Map<int, double> returnQuantitiesByMoveId(List<List<Object>> returnLines) {
  final wanted = <int, double>{};
  for (final line in returnLines) {
    if (line.length < 3) continue;
    final values = line[2];
    if (values is! Map) continue;
    final moveId = firstOdooId(values['move_id']);
    final qty = (values['quantity'] as num?)?.toDouble();
    if (moveId == null || qty == null || qty <= 0) continue;
    wanted[moveId] = (wanted[moveId] ?? 0) + qty;
  }
  return wanted;
}

/// Reads an id Odoo may send bare or as the `[id, name]` pair it uses for
/// Many2one fields, and which is `false` when unset.
int? firstOdooId(dynamic value) {
  if (value is List) {
    return value.isEmpty ? null : firstOdooId(value.first);
  }
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

/// How much of the original line a return move accounts for.
///
/// A finished return is measured by what actually came back (`quantity`); one
/// still in progress by what it is committed to bring back
/// (`product_uom_qty`), and a cancelled one by nothing.
///
/// Reading `quantity` for a pending return is the trap. Odoo's
/// `_create_return` unreserves every sibling return that is not yet done, so
/// creating a second return silently resets the first one's `quantity` to
/// zero. Counting that field alone made each new return erase the ones before
/// it, so the amount still returnable climbed back up and a delivery of five
/// could be returned several times over.
double claimedByReturnMove(Map<dynamic, dynamic> move) {
  final state = move['state']?.toString();
  if (state == 'cancel') return 0;
  if (state == 'done') return (move['quantity'] as num?)?.toDouble() ?? 0;
  final demand = (move['product_uom_qty'] as num?)?.toDouble();
  if (demand != null && demand > 0) return demand;
  return (move['quantity'] as num?)?.toDouble() ?? 0;
}
