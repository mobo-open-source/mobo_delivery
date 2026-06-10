import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/motion_provider.dart';
import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/loaders/loading_widget.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../Pickings/PickingFormPage/pages/picking_details_page.dart';
import '../../Pickings/PickingFormPage/services/odoo_picking_form_service.dart';
import '../bloc/return_management_bloc.dart';
import '../bloc/return_management_event.dart';
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
///   navigates to `PickingDetailsPage` for the source picking
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

  @override
  void initState() {
    super.initState();
    _fetchMoveItems();
  }

  /// Fetches the returnable moves for the picking via Odoo's
  /// `stock.return.picking` wizard. The wizard's compute pre-fills each
  /// line's `quantity` with the correct returnable amount — accounting
  /// for previously-returned units — so the qty fields match what Odoo's
  /// web UI shows.
  Future<void> _fetchMoveItems() async {
    try {
      await widget.odooService.initializeClient();
      final items = await widget.odooService.fetchReturnableMoves(_pickingId);
      if (!mounted) return;
      setState(() {
        moveItems = items.map((item) {
          final qty = item['quantity'];
          final text = qty is num ? qty.toString() : (qty?.toString() ?? '0');
          item['qtyController'] = TextEditingController(text: text);
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
    final motionProvider = Provider.of<MotionProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Return Items',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppStyle.primaryColor,
            ),
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
              : ListView.builder(
            shrinkWrap: true,
            itemCount: moveItems.length,
            itemBuilder: (context, index) {
              final move = moveItems[index];
              final controller = move['qtyController'] as TextEditingController;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        move['product_id'] is List
                            ? move['product_id'][1] ?? 'Unnamed'
                            : 'Unnamed',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    Expanded(
                      child: TextFormField(
                        controller: controller,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) {
                          if (_inlineError != null) {
                            setState(() => _inlineError = null);
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Qty',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),

          if (_inlineError != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
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
                    Icons.error_outline,
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
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _isSubmitting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDark ? Colors.black : Colors.white,
                        ),
                      ),
                    )
                  : const Icon(HugeIcons.strokeRoundedDeliveryReturn02),
              label: Text(
                _isSubmitting ? 'Creating return...' : 'Return',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.black : Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white : AppStyle.primaryColor,
                foregroundColor: isDark ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: isDark ? Colors.white : AppStyle.primaryColor,
                  ),
                ),
              ),
              onPressed: _isSubmitting
                  ? null
                  : () => _submitReturn(motionProvider),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the wizard line payload from the user-entered quantities.
  /// Each line is the Odoo One2many `(0, 0, values)` create command.
  ///
  /// Source data now comes from `stock.return.picking.line` records (via
  /// `fetchReturnableMoves`), so `move_id` arrives as a Many2one tuple
  /// `[id, name]` — unwrap to the bare int.
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
            {
              'product_id': productId,
              'quantity': quantity,
              'move_id': moveId,
            },
          ];
        })
        .toList();
  }

  /// Submits the return wizard. Navigates and shows success only on real
  /// success; errors are surfaced via snackbar.
  Future<void> _submitReturn(MotionProvider motionProvider) async {
    if (_isSubmitting) return;

    final returnLines = _buildReturnLines();
    if (returnLines.isEmpty) {
      setState(() {
        _inlineError =
            'Enter a quantity greater than 0 for at least one product.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _inlineError = null;
    });

    final odooPickingFormService = OdooPickingFormService();
    try {
      await odooPickingFormService.initializeOdooClient();
      await widget.odooService.createReturn(_pickingId, returnLines);
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
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              PickingDetailsPage(
                picking: widget.picking,
                odooService: odooPickingFormService,
                isPickingForm: false,
                isReturnPicking: false,
                isReturnCreate: true,
              ),
          transitionDuration: motionProvider.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 300),
          reverseTransitionDuration: motionProvider.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 300),
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) {
            if (motionProvider.reduceMotion) return child;
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      Navigator.of(context).pop();
      widget.onReturnCreated?.call();
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
    if (raw.contains('Session expired') ||
        raw.contains('SessionExpired')) {
      return 'Session expired. Please log in again to create a return.';
    }
    return 'Failed to create return. Please try again.';
  }
}