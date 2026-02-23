import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:odoo_delivery_app/NavBars/Pickings/PickingFormPage/pages/picking_details_page.dart';
import 'package:provider/provider.dart';
import '../../../../core/providers/motion_provider.dart';
import '../../../../shared/utils/globals.dart';
import '../services/odoo_picking_form_service.dart';

/// Displays a list of return pickings (reverse transfers) related to a source picking.
///
/// This page shows return documents in a scrollable DataTable with columns:
/// - Reference (name)
/// - Contact (partner)
/// - Scheduled Date
/// - Source Document (origin)
/// - State
///
/// Features:
/// • Tapping any cell navigates to the detailed view of that return picking
/// • Dark/light theme support
/// • Motion-reduced page transitions (respects user accessibility preference)
/// • Shows "No Return Pickings Found" placeholder when list is empty
///
/// Data is passed pre-loaded from `PickingDetailsPage` (either from Odoo or Hive cache).
class ReturnListPage extends StatelessWidget {
  /// List of return picking data maps (usually from `stock.picking` records)
  /// Expected keys: 'name', 'partner_id' (List), 'scheduled_date', 'origin', 'state', ...
  final List<Map<String, dynamic>> returnDataList;

  final OdooPickingFormService odooService;

  const ReturnListPage({
    Key? key,
    required this.returnDataList,
    required this.odooService,
  }) : super(key: key);

  /// Returns color matching the picking/return state (used for visual distinction)
  Color _getStateColor(String state) {
    switch (state) {
      case 'draft':
        return Colors.blue;
      case 'done':
        return Colors.green;
      case 'cancel':
        return Colors.red;
      case 'waiting':
        return Colors.orange;
      case 'assigned':
        return Colors.purple;
      case 'confirmed':
        return Colors.teal;
      default:
        return Colors.black;
    }
  }

  /// Human-readable state labels (used in UI instead of raw backend values)
  static const Map<String, String> stateMap = {
    'draft': 'Draft',
    'confirmed': 'Waiting',
    'waiting': 'Waiting Another Operations',
    'assigned': 'Ready',
    'done': 'Done',
    'cancel': 'Cancelled',
  };

  /// Navigates to PickingDetailsPage for the selected return picking
  ///
  /// Passes the return data as the `picking` map, with some adjustments:
  /// • Adds 'item' key for title fallback
  /// • Sets `isReturnPicking: true` flag to customize behavior if needed
  /// Uses fade transition with motion reduction support.
  void _navigateToPickingDetails(
    BuildContext context,
    Map<String, dynamic> picking,
  ) {
    final motionProvider = Provider.of<MotionProvider>(context, listen: false);

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            PickingDetailsPage(
              picking: {
                ...picking,
                'item': picking['name'] ?? 'Return Picking',
              },
              odooService: odooService,
              isPickingForm: false,
              isReturnCreate: false,
              isReturnPicking: true,
            ),
        transitionDuration: motionProvider.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 300),
        reverseTransitionDuration: motionProvider.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (motionProvider.reduceMotion) return child;
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return WillPopScope(
      onWillPop: () async => true,
      child: Scaffold(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],

        appBar: AppBar(
          backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
          title: Text(
            'Return Pickings',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
              fontSize: 22
            ),
          ),
          leading: IconButton(
            icon: Icon(
              HugeIcons.strokeRoundedArrowLeft01,
              color: isDark ? Colors.white : Colors.black,
              size: 28,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: returnDataList.isEmpty
            ? Center(
                child: Text(
                  'No Return Pickings Found',
                  style: TextStyle(
                    fontSize: 18,
                    color: isDark ? Colors.white : Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.all(12.0),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[850] : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withOpacity(0.18)
                            : Colors.black.withOpacity(0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12.0),
                      child: DataTable(
                        headingRowColor: MaterialStateProperty.all(
                          isDark ? Color(0x66757575) : Colors.grey.shade200,
                        ),
                        headingTextStyle: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppStyle.primaryColor,
                        ),
                        columnSpacing: 28,
                        dataRowHeight: 56,
                        columns: const [
                          DataColumn(label: Text('Reference')),
                          DataColumn(label: Text('Contact')),
                          DataColumn(label: Text('Scheduled')),
                          DataColumn(label: Text('Source Document')),
                          DataColumn(label: Text('State')),
                        ],
                        rows: returnDataList.map((data) {
                          final state = (data['state'] ?? '').toString();
                          final stateColor = _getStateColor(state);
                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  data['name'] ?? '',
                                  style: TextStyle(
                                      color: isDark ? Colors.white70 : Colors.black87,
                                      fontWeight: FontWeight.normal
                                  ),
                                ),
                                onTap: () =>
                                    _navigateToPickingDetails(context, data),
                              ),
                              DataCell(
                                Text(
                                  (data['partner_id'] is List &&
                                          data['partner_id'].length > 1)
                                      ? data['partner_id'][1].toString()
                                      : '',
                                  style: TextStyle(
                                      color: isDark ? Colors.white70 : Colors.black87,
                                      fontWeight: FontWeight.normal
                                  ),
                                ),
                                onTap: () =>
                                    _navigateToPickingDetails(context, data),
                              ),
                              DataCell(
                                Text(
                                  data['scheduled_date'] ?? '',
                                  style: TextStyle(
                                      color: isDark ? Colors.white70 : Colors.black87,
                                      fontWeight: FontWeight.normal
                                  ),
                                ),
                                onTap: () =>
                                    _navigateToPickingDetails(context, data),
                              ),
                              DataCell(
                                Text(
                                  data['origin'] ?? '',
                                  style: TextStyle(
                                      color: isDark ? Colors.white70 : Colors.black87,
                                      fontWeight: FontWeight.normal
                                  ),
                                ),
                                onTap: () =>
                                    _navigateToPickingDetails(context, data),
                              ),
                              DataCell(
                                Text(
                                  stateMap[state]?.toUpperCase() ?? 'Unknown',
                                  style: TextStyle(
                                      color: isDark ? Colors.white70 : stateColor,
                                      fontWeight: FontWeight.normal
                                  ),
                                ),
                                onTap: () =>
                                    _navigateToPickingDetails(context, data),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
