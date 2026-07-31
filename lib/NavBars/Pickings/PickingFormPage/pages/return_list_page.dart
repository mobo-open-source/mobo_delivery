import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:odoo_delivery_app/NavBars/Pickings/PickingFormPage/pages/picking_details_page.dart';
import '../../../../shared/utils/globals.dart';
import '../../../../shared/widgets/empty_state.dart';
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
/// • Refreshes the list from Odoo when the user pops back from the
///   detail view — keeps state cells (Draft / Ready / Done / Cancelled)
///   in sync after the user validates or cancels a return.
///
/// Data is passed pre-loaded from `PickingDetailsPage` (either from Odoo or Hive cache).
/// The `sourcePickingId` is used to re-fetch the linked returns when the
/// user returns from a detail view, so the list mirrors backend state.
class ReturnListPage extends StatefulWidget {
  /// Initial list of return picking data maps (usually from `stock.picking`).
  /// Expected keys: 'id', 'name', 'partner_id' (List), 'scheduled_date',
  /// 'origin', 'state'.
  final List<Map<String, dynamic>> returnDataList;

  final OdooPickingFormService odooService;

  /// Source picking ID whose return linkage drives this list. Used to
  /// re-fetch returns when the user comes back from a detail view so
  /// state changes (e.g. Validate → Done) propagate to the list cells.
  final int sourcePickingId;

  const ReturnListPage({
    Key? key,
    required this.returnDataList,
    required this.odooService,
    required this.sourcePickingId,
  }) : super(key: key);

  @override
  State<ReturnListPage> createState() => _ReturnListPageState();
}

class _ReturnListPageState extends State<ReturnListPage> {
  late List<Map<String, dynamic>> _returnDataList;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _returnDataList = List<Map<String, dynamic>>.from(widget.returnDataList);
  }

  /// Returns color matching the picking/return state (used for visual distinction)
  Color _getStateColor(String state) {
    switch (state) {
      case 'draft':
        return Colors.grey;
      case 'done':
        return Colors.green;
      case 'cancel':
        return Colors.red;
      case 'waiting':
      case 'confirmed':
        return Colors.orange;
      case 'assigned':
        return Colors.blue;
      default:
        return Colors.grey;
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

  /// Re-fetches the returns linked to the source picking. Called after the
  /// detail-view pop so any state transition (Validate → Done, Cancel,
  /// add/remove product) is reflected immediately in the list cells.
  Future<void> _refreshReturns() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final fresh = await widget.odooService
          .loadReturnPickings(widget.sourcePickingId);
      if (!mounted) return;
      setState(() {
        _returnDataList = fresh;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  /// Navigates to PickingDetailsPage for the selected return picking.
  ///
  /// After the detail page pops we re-fetch the returns from Odoo so the
  /// list reflects whatever was changed inside the detail view (state,
  /// added/removed products, validation outcome). Without this hook the
  /// list shows pre-edit data until the user backs all the way out and
  /// re-enters — that's the "state not updating in real time" bug.
  void _navigateToPickingDetails(
    BuildContext context,
    Map<String, dynamic> picking,
  ) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            PickingDetailsPage(
              picking: {
                ...picking,
                'item': picking['name'] ?? 'Return Picking',
              },
              odooService: widget.odooService,
              isPickingForm: false,
              isReturnCreate: false,
              isReturnPicking: true,
            ),
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
return FadeTransition(opacity: animation, child: child);
        },
      ),
    ).then((_) => _refreshReturns());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return WillPopScope(
      onWillPop: () async => true,
      child: Scaffold(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],

        appBar: AppBar(
          forceMaterialTransparency: true,
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
        body: RefreshIndicator(
          onRefresh: _refreshReturns,
          child: _returnDataList.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.7,
                      child: const EmptyState(
                        title: 'No Return Pickings Found',
                        subtitle: 'There are no return pickings available.',
                      ),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
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
                            fontWeight: FontWeight.w600,
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
                          rows: _returnDataList.map((data) {
                            final state = (data['state'] ?? '').toString();
                            final stateColor = _getStateColor(state);
                            return DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    cleanOdooValue(data['name']),
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
                                    cleanOdooValue(data['partner_id']),
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
                                    cleanOdooValue(data['scheduled_date']),
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
                                    cleanOdooValue(data['origin']),
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
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600
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
      ),
    );
  }
}
