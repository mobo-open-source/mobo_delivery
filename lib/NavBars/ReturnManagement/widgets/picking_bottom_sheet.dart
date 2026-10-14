import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/buttons/mobo_button.dart';
import '../../../shared/widgets/inputs/mobo_text_field.dart';
import '../../../shared/widgets/loaders/loading_widget.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../Pickings/PickingFormPage/services/odoo_picking_form_service.dart';
import '../bloc/return_management_bloc.dart';
import '../bloc/return_management_event.dart';
import '../infrastructure/return_refresh_bus.dart';
import '../services/odoo_return_service.dart';

/// Bottom sheet dialog for creating a return (reverse picking) from an existing picking.
///
/// Displays a list of move lines from the original picking with editable quantity fields.
/// User can set how many units to return for each product (qty > 0).
///
/// On "Return" button press:
/// • Collects lines with positive return quantities
/// • Awaits the wizard RPCs directly via `OdooReturnManagementService`
/// • On success, dispatches `FetchStockPickings` to refresh the list and
///   closes — invoked from the Return Management list, this pops with the
///   new return's id so the list can highlight it; invoked from a picking's
///   own detail page, it pops plain and lets that page refresh itself
/// • Shows success/error snackbar based on the actual result
///
/// Features:
/// • Offline-aware error handling
/// • Motion-reduced page transition
/// • Dark/light theme support
/// • Quantity validation (only positive values submitted)
class PickingBottomSheet extends StatefulWidget {
  final Map<String, dynamic> picking;
  final OdooReturnManagementService odooService;

  /// Provided when invoked from the Return Management tab so the list can
  /// be refreshed after success. Null when called from the picking detail
  /// page, where the host handles its own reload via [onReturnCreated].
  final ReturnManagementBloc? bloc;

  /// Optional callback fired after a return picking is successfully
  /// created. Lets the host (e.g. picking detail page) refresh its own
  /// state and update the "Return (count)" badge.
  final VoidCallback? onReturnCreated;

  const PickingBottomSheet({
    super.key,
    required this.picking,
    required this.odooService,
    this.bloc,
    this.onReturnCreated,
  });

  @override
  State<PickingBottomSheet> createState() => _PickingBottomSheetState();
}

class _PickingBottomSheetState extends State<PickingBottomSheet> {
  /// List of move items fetched from Odoo
  /// Each map contains product info + `qtyController` added in code
  List<Map<String, dynamic>> moveItems = [];

  bool _isSubmitting = false;
  bool _moveItemsLoaded = false;
  String? _inlineError;

  int get _pickingId {
    final raw = widget.picking['id'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  /// True when at least one line has a return quantity > 0. The Return
  /// button stays disabled until then.
  bool get _hasReturnQty => moveItems.any((item) {
    final c = item['qtyController'] as TextEditingController?;
    final qty = double.tryParse(c?.text ?? '0') ?? 0;
    return qty > 0;
  });

  @override
  void initState() {
    super.initState();
    _fetchMoveItems();
  }

  /// Fetches the returnable moves for the picking. Each line's `quantity`
  /// arrives pre-filled with the correct returnable amount — accounting for
  /// previously-returned units — so the qty fields match what Odoo's web UI
  /// shows. Up to Odoo 19 that figure comes from the `stock.return.picking`
  /// wizard's own compute; on Odoo 20, which has no such wizard, the service
  /// derives it the same way Odoo does.
  Future<void> _fetchMoveItems() async {
    try {
      await widget.odooService.initializeClient();
      final items = await widget.odooService.fetchReturnableMoves(_pickingId);
      if (!mounted) return;
      setState(() {
        moveItems = items.map((item) {
          final qty = item['quantity'];
          // Kept as a number so the quantity entered can be checked against
          // it. Deliberately not written into the controller: Odoo starts
          // these lines at zero on purpose, so the operator counts what came
          // back instead of confirming a figure the app guessed.
          item['returnable'] = qty is num ? qty.toDouble() : null;
          item['qtyController'] = TextEditingController();
          return item;
        }).toList();
        _moveItemsLoaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _moveItemsLoaded = true);
      CustomSnackbar.showError(
        context,
        'Something went wrong, please try again later',
      );
    }
  }

  @override
  void dispose() {
    for (var item in moveItems) {
      (item['qtyController'] as TextEditingController?)?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Return Items',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    HugeIcons.strokeRoundedCancel01,
                    size: 22,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          !_moveItemsLoaded
              ? const Center(
                  child: LoadingWidget(
                    size: 40,
                    variant: LoadingVariant.staggeredDots,
                  ),
                )
              : moveItems.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No returnable items found for this picking.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                )
              : Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: moveItems.length,
                    itemBuilder: (context, index) {
                      final move = moveItems[index];
                      final controller =
                          move['qtyController'] as TextEditingController;
                      final returnable = move['returnable'] as double?;
                      final productName = move['product_id'] is List
                          ? (move['product_id'][1] ?? 'Unnamed')
                          : 'Unnamed';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _productField(
                              productName,
                              move['image'] as String?,
                              isDark,
                            ),
                            const SizedBox(height: 12),
                            if (returnable != null) ...[
                              Text(
                                'Can return: ${_trimZeros(returnable)}'
                                '${_uomName(move)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
                            MoboTextField(
                              controller: controller,
                              label: 'Qty',
                              hintText: '0',
                              showShadow: false,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (_) {
                                setState(() => _inlineError = null);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
          const SizedBox(height: 20),

          if (_inlineError != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.red.withOpacity(0.15)
                    : Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.red[300]! : Colors.red[400]!,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    HugeIcons.strokeRoundedAlert02,
                    color: isDark ? Colors.red[300] : Colors.red[700],
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _inlineError!,
                      style: TextStyle(
                        color: isDark ? Colors.red[200] : Colors.red[800],
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          MoboButton.primary(
            label: 'Return',
            icon: HugeIcons.strokeRoundedDeliveryReturn02,
            borderRadius: 8,
            isLoading: _isSubmitting,
            loadingLabel: 'Creating return...',
            onPressed: (_isSubmitting || !_hasReturnQty)
                ? null
                : () => _submitReturn(),
          ),
        ],
      ),
    );
  }

  /// A read-only, non-clickable display of the product name styled like the
  /// app's gray-filled [MoboTextField] (soft fill, rounded corners, no extra
  /// shadow), with the real product image as its prefix (falling back to a
  /// package icon). Used as the top layer of each return line
  /// (name → quantity → button).
  Widget _productField(String name, String? imageBase64, bool isDark) {
    final Color fillColor = isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xffF8FAFB);
    final Color textColor = isDark ? Colors.white : const Color(0xff000000);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RequiredLabel(
          'Product',
          color: isDark ? Colors.white70 : const Color(0xff7F7F7F),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _productThumbnail(imageBase64, isDark),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Renders the product's [image_128] thumbnail when available, otherwise a
  /// package icon placeholder.
  Widget _productThumbnail(String? imageBase64, bool isDark) {
    final border = Border.all(
      color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
    );

    Widget fallback() => Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppStyle.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: border,
      ),
      child: const Icon(
        HugeIcons.strokeRoundedPackage,
        color: AppStyle.primaryColor,
        size: 22,
      ),
    );

    if (imageBase64 == null || imageBase64.isEmpty || imageBase64 == 'false') {
      return fallback();
    }

    try {
      final bytes = base64Decode(imageBase64);
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: border,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Image.memory(
            bytes,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback(),
          ),
        ),
      );
    } catch (_) {
      return fallback();
    }
  }

  /// Builds the wizard line payload from the user-entered quantities.
  /// Each line is the Odoo One2many `(0, 0, values)` create command.
  ///
  /// Source data comes from `fetchReturnableMoves`, where `move_id` arrives
  /// as a Many2one tuple `[id, name]` from the `stock.return.picking.line`
  /// records used up to Odoo 19, and as a bare int from the moves read
  /// directly on Odoo 20 — unwrap either to the bare int.
  List<List<Object>> _buildReturnLines() {
    return moveItems
        .where((item) {
          final controller = item['qtyController'] as TextEditingController?;
          final quantity = double.tryParse(controller?.text ?? '0') ?? 0;
          return quantity > 0;
        })
        .map<List<Object>>((item) {
          final controller = item['qtyController'] as TextEditingController?;
          final quantity = double.tryParse(controller?.text ?? '0') ?? 0;
          final productId = (item['product_id'] is List)
              ? item['product_id'][0] as Object
              : item['product_id'] as Object;
          final rawMoveId = item['move_id'];
          final moveId = (rawMoveId is List && rawMoveId.isNotEmpty)
              ? rawMoveId[0] as Object
              : (rawMoveId as Object);
          return [
            0,
            0,
            {'product_id': productId, 'quantity': quantity, 'move_id': moveId},
          ];
        })
        .toList();
  }

  /// The first line asking for more than is left, described for the user, or
  /// null when every line is within its limit.
  ///
  /// Checked here rather than left to the server: Odoo does not always refuse
  /// an over-return, and a return of five against three delivered is a stock
  /// error nobody notices until the counts drift.
  String? _firstOverReturn() {
    for (final item in moveItems) {
      final returnable = item['returnable'] as double?;
      if (returnable == null) continue;
      final controller = item['qtyController'] as TextEditingController?;
      final entered = double.tryParse(controller?.text.trim() ?? '');
      if (entered == null || entered <= 0) continue;
      if (entered > returnable) {
        final name = item['product_id'] is List
            ? (item['product_id'][1] ?? 'this product')
            : 'this product';
        return 'Only ${_trimZeros(returnable)} of $name can be returned.';
      }
    }
    return null;
  }

  /// Drops a trailing `.0` so a whole number reads as "3", not "3.0".
  static String _trimZeros(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  /// The unit name, as a trailing " Units", or empty when unknown.
  static String _uomName(Map<String, dynamic> move) {
    final uom = move['uom_id'];
    if (uom is List && uom.length > 1 && uom[1] is String) {
      return ' ${uom[1]}';
    }
    return '';
  }

  /// Submits the return wizard. Navigates and shows success only on real
  /// success; errors are surfaced via snackbar.
  Future<void> _submitReturn() async {
    if (_isSubmitting) return;

    final returnLines = _buildReturnLines();
    if (returnLines.isEmpty) {
      setState(() {
        _inlineError =
            'Enter a quantity greater than 0 for at least one product.';
      });
      return;
    }

    final tooMany = _firstOverReturn();
    if (tooMany != null) {
      setState(() => _inlineError = tooMany);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _inlineError = null;
    });

    final odooPickingFormService = OdooPickingFormService();
    int? newPickingId;
    try {
      await odooPickingFormService.initializeOdooClient();
      newPickingId = await widget.odooService.createReturn(
        _pickingId,
        returnLines,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _inlineError = _formatError(e);
      });
      return;
    }

    if (!mounted) return;

    final bloc = widget.bloc;
    if (bloc != null) {
      bloc.add(FetchStockPickings(bloc.state.currentPage));
      Navigator.of(context).pop(newPickingId);
    } else {
      Navigator.of(context).pop();
      widget.onReturnCreated?.call();
      ReturnRefreshBus.notifyReturnCreated(newPickingId);
    }
    CustomSnackbar.showSuccess(context, 'Return created successfully.');
  }

  /// Translates raw RPC / wizard exceptions into user-friendly messages.
  String _formatError(Object e) {
    final raw = e.toString();
    if (raw.contains('404')) {
      return 'This picking can no longer be returned. It may already have a return in progress, or the source moves are no longer available.';
    }
    if (raw.contains('No quantity specified')) {
      return 'Enter a quantity greater than 0 for at least one product.';
    }
    if (raw.contains('Session expired') || raw.contains('SessionExpired')) {
      return 'Session expired. Please log in again to create a return.';
    }
    return 'Failed to create return. Please try again.';
  }
}
