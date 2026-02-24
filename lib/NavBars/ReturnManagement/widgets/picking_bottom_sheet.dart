import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/motion_provider.dart';
import '../../../shared/utils/globals.dart';
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
/// • Dispatches `CreateReturn` event to `ReturnManagementBloc`
/// • Navigates to `PickingDetailsPage` for the new return picking
/// • Shows success/error snackbar
///
/// Features:
/// • Offline-aware error handling
/// • Motion-reduced page transition
/// • Dark/light theme support
/// • Quantity validation (only positive values submitted)
class PickingBottomSheet extends StatefulWidget {
  final Map<String, dynamic> picking;
  final OdooReturnManagementService odooService;
  final ReturnManagementBloc bloc;

  const PickingBottomSheet({
    super.key,
    required this.picking,
    required this.odooService,
    required this.bloc,
  });

  @override
  State<PickingBottomSheet> createState() => _PickingBottomSheetState();
}

class _PickingBottomSheetState extends State<PickingBottomSheet> {
  /// List of move items fetched from Odoo
  /// Each map contains product info + `qtyController` added in code
  List<Map<String, dynamic>> moveItems = [];

  @override
  void initState() {
    super.initState();
    _fetchMoveItems();
  }

  /// Fetches move lines for the given picking ID from Odoo
  ///
  /// On success: attaches a `TextEditingController` to each item for quantity editing
  /// On failure: shows error snackbar
  Future<void> _fetchMoveItems() async {
    try {
      await widget.odooService.initializeClient();
      final items = await widget.odooService.fetchMoveItems(
        widget.picking['id'],
      );
      setState(() {
        moveItems = items.map((item) {
          item['qtyController'] = TextEditingController(
            text: item['product_uom_qty'].toString(),
          );
          return item;
        }).toList();
      });
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(context, 'Something went wrong, please try again later');
      }
    }
  }

  @override
  void dispose() {
    // Clean up all quantity controllers to prevent memory leaks
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
          // Header
          Text(
            'Return Items',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppStyle.primaryColor,
            ),
          ),
          const SizedBox(height: 12),

          // Loading or content
          moveItems.isEmpty
              ? const Center(child: CircularProgressIndicator())
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
                    // Product name (takes most space)
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

                    // Quantity input
                    Expanded(
                      child: TextFormField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Qty',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                        onChanged: (value) {
                          final newQty = int.tryParse(value);
                          if (newQty != null) {
                            moveItems[index]['product_uom_qty'] = newQty;
                          }
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),

          // Return Action Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(HugeIcons.strokeRoundedDeliveryReturn02),
              label: Text(
                'Return',
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
              onPressed: () async {
                try {
                  final odooPickingFormService = OdooPickingFormService();
                  await odooPickingFormService.initializeOdooClient();
                  final returnLines = moveItems
                      .asMap()
                      .entries
                      .where((entry) {
                    final controller = entry.value['qtyController'] as TextEditingController?;
                    final quantity = double.tryParse(controller?.text ?? '0') ?? 0;
                    return quantity > 0;
                  })
                      .map((entry) {
                    final item = entry.value;
                    final controller = item['qtyController'] as TextEditingController?;
                    final quantity = double.tryParse(controller?.text ?? '0') ?? 0;
                    return [
                      0,
                      0,
                      {
                        'product_id': item['product_id']?[0],
                        'quantity': quantity,
                        'move_id': item['id'],
                      },
                    ];
                  })
                      .toList();

                  widget.bloc.add(
                    CreateReturn(widget.picking['id'], returnLines),
                  );

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
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        if (motionProvider.reduceMotion) return child;
                        return FadeTransition(
                          opacity: animation,
                          child: child,
                        );
                      },
                    ),
                  );
                  CustomSnackbar.showSuccess(context, 'Return created successfully.');
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(context, null);
                    CustomSnackbar.showError(context, 'Nothing to check the availability for.');
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}