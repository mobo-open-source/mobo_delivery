import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:odoo_rpc/odoo_rpc.dart';

import '../../../../shared/utils/globals.dart';
import '../../../../shared/utils/odoo_error_message.dart';
import '../../../../shared/widgets/buttons/mobo_button.dart';
import '../../../../shared/widgets/dialogs/common_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/inputs/mobo_text_field.dart';
import '../../../../shared/widgets/loaders/loading_widget.dart';
import '../models/detailed_operations.dart';
import '../services/odoo_picking_form_service.dart';

/// Odoo's "Detailed Operations" for a picking: one row per `stock.move.line`
/// — which stock each product is picked from, its lot/serial, and the
/// quantity.
///
/// While the picking is not done or cancelled the lines can be changed the
/// way Odoo allows: tap a line to change where it is picked from (and so its
/// lot/serial) or its quantity, delete it, or add a line — for example to
/// deliver 3 from one lot and 2 from another. Odoo itself moves the
/// reservations and enforces its rules (serial numbers, stock, lot/product
/// match); the app adds none of its own.
///
/// Pops with `true` when anything was changed, so the picking screen can
/// re-read its Lot/Serial column.
class StockMoveLineListPage extends StatefulWidget {
  /// The picking whose move lines are shown.
  final int pickingId;

  const StockMoveLineListPage({super.key, required this.pickingId});

  @override
  State<StockMoveLineListPage> createState() => _StockMoveLineListPageState();
}

class _StockMoveLineListPageState extends State<StockMoveLineListPage> {
  final _service = OdooPickingFormService();
  late Future<DetailedOperations?> _future;
  bool _changed = false;
  final Map<int, List<PickFromOption>> _pickFromCache = {};
  final Map<int, List<MapEntry<int, String>>> _lotsCache = {};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// Reads the lines, then warms the "Pick From" / lot choices for every
  /// product in the background so the edit dialog opens without a wait.
  /// Done once per load here rather than from `build`, which can run many
  /// times before a request returns.
  Future<DetailedOperations?> _load() async {
    final ops = await _service.loadDetailedOperations(widget.pickingId);
    if (ops != null && mounted) _prefetchOptions(ops);
    return ops;
  }

  void _prefetchOptions(DetailedOperations ops) {
    for (final move in ops.moves) {
      if (move.showQuant && !_pickFromCache.containsKey(move.id)) {
        _service
            .loadPickFromOptions(move)
            .then((opts) {
              if (mounted) _pickFromCache[move.id] = opts;
            })
            .catchError((_) {});
      } else if (move.showLotPicker && !_lotsCache.containsKey(move.id)) {
        _service
            .loadLots(move, ops.companyId)
            .then((lots) {
              if (mounted) _lotsCache[move.id] = lots;
            })
            .catchError((_) {});
      }
    }
  }

  /// Re-reads from the server. Opening this screen is how the user checks what
  /// actually happened to the stock, so it reads live every time rather than
  /// from a cache that can disagree with Odoo.
  void _reload() {
    setState(() {
      _pickFromCache.clear();
      _lotsCache.clear();
      _future = _load();
    });
  }

  Future<void> _openLine(DetailedOperations ops, {DetailedLine? line}) async {
    final move = line != null
        ? ops.moveOf(line)
        : (ops.moves.length == 1 ? ops.moves.first : null);

    List<PickFromOption>? initialPickFrom;
    List<MapEntry<int, String>>? initialLots;

    if (move != null) {
      if (move.showQuant) {
        if (_pickFromCache.containsKey(move.id)) {
          initialPickFrom = _pickFromCache[move.id];
        } else {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(
              child: LoadingWidget(
                size: 40,
                variant: LoadingVariant.staggeredDots,
              ),
            ),
          );
          try {
            initialPickFrom = await _service.loadPickFromOptions(move);
            _pickFromCache[move.id] = initialPickFrom;
          } catch (_) {}
          if (mounted) Navigator.of(context, rootNavigator: true).pop();
          if (!mounted) return;
        }
      } else if (move.showLotPicker) {
        if (_lotsCache.containsKey(move.id)) {
          initialLots = _lotsCache[move.id];
        } else {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(
              child: LoadingWidget(
                size: 40,
                variant: LoadingVariant.staggeredDots,
              ),
            ),
          );
          try {
            initialLots = await _service.loadLots(move, ops.companyId);
            _lotsCache[move.id] = initialLots;
          } catch (_) {}
          if (mounted) Navigator.of(context, rootNavigator: true).pop();
          if (!mounted) return;
        }
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _MoveLineDialog(
        service: _service,
        ops: ops,
        pickingId: widget.pickingId,
        line: line,
        initialPickFrom: initialPickFrom,
        initialLots: initialLots,
        cachePickFrom: _pickFromCache,
        cacheLots: _lotsCache,
      ),
    );
    if (saved == true && mounted) {
      _changed = true;
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        appBar: AppBar(
          forceMaterialTransparency: true,
          backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
          title: Text(
            'Stock Move Lines',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
              fontSize: 22,
            ),
          ),
          leading: IconButton(
            icon: Icon(
              HugeIcons.strokeRoundedArrowLeft01,
              color: isDark ? Colors.white : Colors.black,
              size: 28,
            ),
            onPressed: () => Navigator.pop(context, _changed),
          ),
        ),
        body: FutureBuilder<DetailedOperations?>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final ops = snapshot.data;

            /// null means the read failed. Showing the empty state here would
            /// tell the user this picking has no move lines, which is a
            /// different and misleading claim.
            if (ops == null) {
              return _errorState(isDark);
            }
            final canAdd = ops.isEditable && ops.moves.isNotEmpty;
            if (ops.lines.isEmpty) {
              return EmptyState(
                title: 'No Stock Move Lines Found',
                subtitle: 'There are no stock move lines available.',
                actionLabel: canAdd ? 'Add Line' : null,
                onAction: canAdd ? () => _openLine(ops) : null,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (ops.isEditable)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Text(
                      'Tap a line to change where it is picked from, its '
                      'lot/serial or its quantity.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.grey[600],
                      ),
                    ),
                  ),
                Expanded(child: _buildTable(context, isDark, ops)),
                if (canAdd)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: MoboButton.secondary(
                        label: 'Add Line',
                        icon: HugeIcons.strokeRoundedAdd01,
                        borderRadius: 10,
                        onPressed: () => _openLine(ops),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _errorState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: isDark ? Colors.grey[500] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load move lines',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: _reload,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppStyle.primaryColor,
                  side: const BorderSide(
                    color: AppStyle.primaryColor,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(
    BuildContext context,
    bool isDark,
    DetailedOperations ops,
  ) {
    final verticalController = ScrollController();
    final horizontalController = ScrollController();
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey[300]!;

    /// A whole row is the tap target while the picking can still change.
    TableCell cell(DetailedLine line, Widget child) => _cell(
      child: child,
      onTap: ops.isEditable ? () => _openLine(ops, line: line) : null,
    );

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Scrollbar(
        controller: verticalController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: verticalController,
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            controller: horizontalController,
            scrollDirection: Axis.horizontal,
            child: Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: borderColor, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Table(
                border: TableBorder(
                  horizontalInside: BorderSide(color: borderColor, width: 1),
                ),
                columnWidths: const {
                  0: FixedColumnWidth(200),
                  1: FixedColumnWidth(150),
                  2: FixedColumnWidth(160),
                  3: FixedColumnWidth(120),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF3A3A3A)
                          : const Color(0xFFF8F9FA),
                    ),
                    children: [
                      _headerCell('Product', isDark),
                      _headerCell('Pick From', isDark),
                      _headerCell('Lot/Serial', isDark),
                      _headerCell('Quantity', isDark),
                    ],
                  ),
                  ...ops.lines.asMap().entries.map((entry) {
                    final index = entry.key;
                    final line = entry.value;
                    return TableRow(
                      children: [
                        cell(
                          line,
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 22,
                                child: Text(
                                  '${index + 1}.',
                                  style: _rowStyle(isDark),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  line.productName,
                                  style: _rowStyle(isDark),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        cell(
                          line,
                          Text(
                            line.locationName ?? '—',
                            style: _rowStyle(isDark),
                          ),
                        ),
                        cell(
                          line,
                          Text(line.lotName ?? '—', style: _rowStyle(isDark)),
                        ),
                        cell(
                          line,
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppStyle.primaryColor,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                formatQuantity(line.quantity),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  TableCell _headerCell(String text, bool isDark) {
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.grey[800],
          ),
        ),
      ),
    );
  }

  TableCell _cell({required Widget child, VoidCallback? onTap}) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: child,
    );
    // `intrinsicHeight` makes every cell as tall as the row's tallest, so with
    // TableRowInkWell the whole row is the tap target with one ripple across
    // it. Not `fill`: a row whose cells are all `fill` has zero height.
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
      child: onTap == null
          ? Align(alignment: Alignment.centerLeft, child: content)
          : TableRowInkWell(
              onTap: onTap,
              child: Align(alignment: Alignment.centerLeft, child: content),
            ),
    );
  }

  TextStyle _rowStyle(bool isDark) => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: isDark ? Colors.grey[300] : Colors.grey[700],
  );
}

/// `5.0` → `5`, `2.5` → `2.5`.
String formatQuantity(double q) =>
    q == q.roundToDouble() ? q.toInt().toString() : q.toString();

/// Edit or add one move line — uses the existing dialog UI from
/// `_editProductLine` / `_addProductLine` in `picking_details_page.dart`.
/// Pops `true` once Odoo has accepted a change.
class _MoveLineDialog extends StatefulWidget {
  final OdooPickingFormService service;
  final DetailedOperations ops;
  final int pickingId;

  /// The line being edited, or null to add one.
  final DetailedLine? line;
  final List<PickFromOption>? initialPickFrom;
  final List<MapEntry<int, String>>? initialLots;
  final Map<int, List<PickFromOption>>? cachePickFrom;
  final Map<int, List<MapEntry<int, String>>>? cacheLots;

  const _MoveLineDialog({
    required this.service,
    required this.ops,
    required this.pickingId,
    this.line,
    this.initialPickFrom,
    this.initialLots,
    this.cachePickFrom,
    this.cacheLots,
  });

  @override
  State<_MoveLineDialog> createState() => _MoveLineDialogState();
}

class _MoveLineDialogState extends State<_MoveLineDialog> {
  final _qtyController = TextEditingController();
  DetailedMove? _move;
  List<PickFromOption>? _pickFrom;
  List<MapEntry<int, String>>? _lots;
  PickFromOption? _selectedPick;
  MapEntry<int, String>? _selectedLot;
  bool _loadingOptions = false;
  bool _saving = false;
  bool _deleting = false;
  String _error = '';

  bool get _isEdit => widget.line != null;

  @override
  void initState() {
    super.initState();
    final line = widget.line;
    if (line != null) {
      _qtyController.text = formatQuantity(line.quantity);
      if (line.lotId != null) {
        _selectedLot = MapEntry(line.lotId!, line.lotName ?? '');
      }
      final move = widget.ops.moveOf(line);
      _move = move;
      if (widget.initialPickFrom != null) {
        _pickFrom = widget.initialPickFrom;
        for (final o in widget.initialPickFrom!) {
          if (o.matches(line)) {
            _selectedPick = o;
            break;
          }
        }
      }
      if (widget.initialLots != null) {
        _lots = widget.initialLots;
      }
      if (move != null && _pickFrom == null && _lots == null) {
        _selectMove(move);
      }
    } else if (widget.ops.moves.length == 1) {
      final move = widget.ops.moves.first;
      _move = move;
      _pickFrom = widget.initialPickFrom;
      _lots = widget.initialLots;
      if (_pickFrom == null && _lots == null) {
        _selectMove(move);
      }
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  /// Loads the choices Odoo offers for [move]'s lines: "Pick From" stock, or
  /// lots when Odoo shows the Lot/Serial column instead.
  Future<void> _selectMove(DetailedMove move) async {
    // Check cache first to avoid async loading twitch
    if (move.showQuant && widget.cachePickFrom?.containsKey(move.id) == true) {
      setState(() {
        _move = move;
        _pickFrom = widget.cachePickFrom![move.id];
        _lots = null;
        _selectedPick = null;
        if (!_isEdit) _selectedLot = null;
        _error = '';
        _loadingOptions = false;
        final line = widget.line;
        if (line != null && _pickFrom != null) {
          for (final o in _pickFrom!) {
            if (o.matches(line)) {
              _selectedPick = o;
              break;
            }
          }
        }
      });
      return;
    }

    if (move.showLotPicker && widget.cacheLots?.containsKey(move.id) == true) {
      setState(() {
        _move = move;
        _pickFrom = null;
        _lots = widget.cacheLots![move.id];
        _selectedPick = null;
        if (!_isEdit) _selectedLot = null;
        _error = '';
        _loadingOptions = false;
      });
      return;
    }

    setState(() {
      _move = move;
      _pickFrom = null;
      _lots = null;
      _selectedPick = null;
      if (!_isEdit) _selectedLot = null;
      _error = '';
      _loadingOptions = move.showQuant || move.showLotPicker;
    });
    try {
      if (move.showQuant) {
        final options = await widget.service.loadPickFromOptions(move);
        widget.cachePickFrom?[move.id] = options;
        if (!mounted || _move != move) return;
        final line = widget.line;
        setState(() {
          _pickFrom = options;
          if (line != null) {
            for (final o in options) {
              if (o.matches(line)) {
                _selectedPick = o;
                break;
              }
            }
          }
        });
      } else if (move.showLotPicker) {
        final lots = await widget.service.loadLots(move, widget.ops.companyId);
        widget.cacheLots?[move.id] = lots;
        if (!mounted || _move != move) return;
        setState(() => _lots = lots);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorText(e, 'Couldn\'t load the stock.'));
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  void _onPickFromChanged(PickFromOption? option) {
    setState(() {
      _selectedPick = option;
      _error = '';
    });
    final move = _move;
    if (option == null || move == null) return;
    // Odoo fills the quantity only on a line that has none yet.
    final current = double.tryParse(_qtyController.text.trim()) ?? 0;
    if (current <= 0) {
      _qtyController.text = formatQuantity(
        defaultLineQuantity(
          demand: move.demand,
          done: move.done,
          available: option.available,
        ),
      );
    }
  }

  String _errorText(Object e, String action) {
    if (e is OdooSessionExpiredException) {
      return 'Your session has expired. Please log in again.';
    }
    if (e is OdooException) return '$action ${briefOdooMessage(e)}';
    return '$action Check your connection and try again.';
  }

  Future<void> _save() async {
    final move = _move;
    if (move == null) {
      setState(() => _error = 'Please select a product.');
      return;
    }
    final qty = double.tryParse(
      _qtyController.text.trim().replaceAll(',', '.'),
    );
    if (qty == null || qty <= 0) {
      setState(() => _error = 'Quantity must be greater than zero.');
      return;
    }
    if (!_isEdit && move.showQuant && _selectedPick == null) {
      setState(() => _error = 'Please choose where to pick it from.');
      return;
    }
    if (!_isEdit && move.showLotPicker && _selectedLot == null) {
      setState(() => _error = 'Please select a lot/serial number.');
      return;
    }

    final values = <String, dynamic>{};
    final line = widget.line;
    final pick = _selectedPick;
    if (pick != null && (line == null || !pick.matches(line))) {
      values.addAll(pick.lineValues);
    }
    final lot = _selectedLot;
    if (move.showLotPicker && lot != null && lot.key != line?.lotId) {
      values['lot_id'] = lot.key;
    }

    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await widget.service.initializeOdooClient();
      if (line == null) {
        await widget.service.createMoveLine(
          move: move,
          pickingId: widget.pickingId,
          quantity: qty,
          values: values,
        );
      } else {
        if (qty != line.quantity) values['quantity'] = qty;
        if (values.isEmpty) {
          if (mounted) Navigator.of(context).pop(false);
          return;
        }
        await widget.service.updateMoveLine(line.id, values);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _errorText(e, 'Couldn\'t save the line.');
      });
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await CommonDialog.confirm(
      context,
      title: 'Delete Line?',
      message: 'Are you sure you want to delete this move line?',
      confirmText: 'Delete',
      cancelText: 'Cancel',
      icon: HugeIcons.strokeRoundedDelete02,
      centered: true,
    );
    if (confirmed == true && mounted) {
      await _delete();
    }
  }

  Future<void> _delete() async {
    final line = widget.line;
    if (line == null) return;
    setState(() {
      _saving = true;
      _deleting = true;
      _error = '';
    });
    try {
      await widget.service.initializeOdooClient();
      await widget.service.deleteMoveLine(line.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _deleting = false;
        _error = _errorText(e, 'Couldn\'t delete the line.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final move = _move;
    final labelColor = isDark ? Colors.white60 : Colors.black87;

    // Closing mid-save would drop the result: Odoo would keep the change but
    // the list and the picking screen would never hear about it.
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        backgroundColor: isDark ? Colors.grey[850] : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _isEdit ? 'Edit Line' : 'Add Line',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            if (_isEdit && _deleting)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppStyle.primaryColor,
                ),
              )
            else if (_isEdit)
              IconButton(
                icon: Icon(
                  HugeIcons.strokeRoundedDelete02,
                  size: 20,
                  color: isDark ? Colors.red[300] : Colors.red[700],
                ),
                tooltip: 'Delete Line',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _saving ? null : _confirmDelete,
              ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.95,
          child: Stack(
            children: [
              SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RequiredLabel(
                      'Product',
                      isRequired: !_isEdit,
                      fontWeight: FontWeight.w500,
                      color: labelColor,
                    ),
                    const SizedBox(height: 8),
                    if (_isEdit || widget.ops.moves.length == 1)
                      _readOnlyBox(isDark, move?.productName ?? '—')
                    else
                      _select<DetailedMove>(
                        isDark: isDark,
                        items: widget.ops.moves,
                        selected: move,
                        label: (m) => m.productName,
                        hint: 'Select a product',
                        icon: HugeIcons.strokeRoundedPackage,
                        compare: (a, b) => a.id == b.id,
                        onChanged: (m) {
                          if (m != null) _selectMove(m);
                        },
                      ),
                    if (move != null && move.showQuant) ...[
                      const SizedBox(height: 16),
                      RequiredLabel(
                        'Pick From',
                        isRequired: true,
                        fontWeight: FontWeight.w500,
                        color: labelColor,
                      ),
                      const SizedBox(height: 8),
                      _select<PickFromOption>(
                        isDark: isDark,
                        items: _pickFrom ?? const [],
                        selected: _selectedPick,
                        label: _pickFromTitle,
                        subtitle: _pickFromSubtitle,
                        hint: _loadingOptions
                            ? 'Loading stock…'
                            : (_pickFrom?.isEmpty ?? false)
                            ? 'No stock of this product here'
                            : (_isEdit && widget.line?.locationName != null)
                            ? _currentPickLabel(widget.line!)
                            : 'Select where to pick from',
                        icon: HugeIcons.strokeRoundedLocation01,
                        compare: (a, b) => a.id == b.id,
                        onChanged: _onPickFromChanged,
                      ),
                    ],
                    if (move != null && move.showLotPicker) ...[
                      const SizedBox(height: 16),
                      RequiredLabel(
                        'Lot/Serial Number',
                        isRequired: true,
                        fontWeight: FontWeight.w500,
                        color: labelColor,
                      ),
                      const SizedBox(height: 8),
                      _select<MapEntry<int, String>>(
                        isDark: isDark,
                        items: _lots ?? const [],
                        selected: _selectedLot,
                        label: (l) => l.value,
                        hint: _loadingOptions
                            ? 'Loading lots…'
                            : 'Select a lot/serial number',
                        icon: HugeIcons.strokeRoundedBarCode01,
                        compare: (a, b) => a.key == b.key,
                        onChanged: (l) => setState(() {
                          _selectedLot = l;
                          _error = '';
                        }),
                      ),
                    ],
                    const SizedBox(height: 16),
                    RequiredLabel(
                      'Quantity',
                      isRequired: true,
                      fontWeight: FontWeight.w500,
                      color: labelColor,
                    ),
                    const SizedBox(height: 8),
                    MoboTextField(
                      controller: _qtyController,
                      hintText: 'Enter quantity',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      prefixIcon: Icon(
                        HugeIcons.strokeRoundedPinCode,
                        size: 20,
                        color: isDark ? Colors.grey[400] : Colors.grey[500],
                      ),
                    ),
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error,
                        style: GoogleFonts.manrope(
                          color: Colors.red,
                          fontWeight: FontWeight.w400,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: MoboButton.secondary(
                  label: 'CANCEL',
                  borderRadius: 8,
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MoboButton.primary(
                  label: _isEdit ? 'SAVE' : 'ADD',
                  icon: _isEdit
                      ? HugeIcons.strokeRoundedDocumentValidation
                      : HugeIcons.strokeRoundedAdd01,
                  borderRadius: 10,
                  isLoading: _saving && !_deleting,
                  loadingLabel: _isEdit ? 'Saving...' : 'Adding...',
                  onPressed: _saving || _loadingOptions ? null : _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _pickFromTitle(PickFromOption o) =>
      [o.locationName ?? '—', if (o.lotName != null) o.lotName!].join(' · ');

  String _pickFromSubtitle(PickFromOption o) => [
    if (o.packageName != null) o.packageName!,
    '${formatQuantity(o.available)} available',
  ].join(' · ');

  String _currentPickLabel(DetailedLine line) => [
    line.locationName ?? '—',
    if (line.lotName != null) line.lotName!,
  ].join(' · ');

  Widget _readOnlyBox(bool isDark, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8FAFB),
      ),
      child: Text(
        text,
        style: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : Colors.black87,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// A searchable select styled like the product field of "Edit Product
  /// Line".
  Widget _select<T>({
    required bool isDark,
    required List<T> items,
    required T? selected,
    required String Function(T) label,
    String Function(T)? subtitle,
    required String hint,
    required IconData icon,
    required bool Function(T, T) compare,
    required ValueChanged<T?> onChanged,
  }) {
    final hintStyle = GoogleFonts.manrope(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.italic,
      color: isDark ? Colors.white54 : Colors.grey[500],
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8FAFB),
      ),
      child: DropdownSearch<T>(
        enabled: !_loadingOptions && items.isNotEmpty,
        items: items,
        selectedItem: selected,
        itemAsString: label,
        compareFn: compare,
        onChanged: onChanged,
        popupProps: PopupProps.menu(
          // dropdown_search's menu defaults to FlexFit.tight, which stretches
          // it to its 350 max even for three options. Loose fits the items.
          fit: FlexFit.loose,
          showSearchBox: items.length > 6,
          menuProps: MenuProps(
            backgroundColor: isDark ? Colors.grey[900] : Colors.white,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          searchFieldProps: TextFieldProps(
            decoration: InputDecoration(
              hintText: 'Search...',
              hintStyle: hintStyle,
              prefixIcon: Icon(
                HugeIcons.strokeRoundedSearch01,
                size: 20,
                color: isDark ? Colors.white54 : Colors.grey[500],
              ),
              filled: true,
              fillColor: isDark
                  ? const Color(0xFF2A2A2A)
                  : const Color(0xffF8FAFB),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppStyle.primaryColor,
                  width: 1.5,
                ),
              ),
            ),
          ),
          itemBuilder: (context, item, isSelected) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label(item),
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isSelected
                              ? AppStyle.primaryColor
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle(item),
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: AppStyle.primaryColor,
                  ),
              ],
            ),
          ),
        ),
        dropdownBuilder: (context, item) => item == null
            ? Text(hint, style: hintStyle)
            : Text(
                label(item),
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
        dropdownDecoratorProps: DropDownDecoratorProps(
          dropdownSearchDecoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            prefixIcon: Icon(
              icon,
              size: 20,
              color: isDark ? Colors.grey[400] : Colors.grey[500],
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
        ),
      ),
    );
  }
}
