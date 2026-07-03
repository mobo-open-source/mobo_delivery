import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/list_search_bar.dart';
import '../../../shared/widgets/error_state_widget.dart';
import '../../../Dashboard/infrastructure/profile_refresh_bus.dart';
import '../../../Dashboard/services/storage_service.dart';
import '../../../core/company/infrastructure/company_refresh_bus.dart';
import '../../../core/company/providers/company_provider.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../../shared/widgets/loaders/delivery_shimmers.dart';
import '../bloc/return_management_bloc.dart';
import '../bloc/return_management_event.dart';
import '../bloc/return_management_state.dart';
import '../services/odoo_return_service.dart';
import '../widgets/picking_bottom_sheet.dart';
import '../../../shared/widgets/buttons/mobo_button.dart';

/// Main screen for managing return pickings (reverse transfers / customer returns).
///
/// Features:
/// • Paginated list of return pickings grouped by status/origin/type
/// • Search by item/reference
/// • Advanced filters (status, type, date range, presets like "Late", "Backorders")
/// • Grouping (by status, source document, operation type)
/// • Offline support via Hive cache
/// • Pull-to-refresh & company change auto-reload
/// • Bottom sheet detail view for each return
/// • Loading/error/empty states with shimmer & Lottie animations
class ReturnManagementPage extends StatefulWidget {
  const ReturnManagementPage({super.key});

  @override
  State<ReturnManagementPage> createState() => _ReturnManagementPageState();
}

class _ReturnManagementPageState extends State<ReturnManagementPage> {
  late ReturnManagementBloc _bloc;
  bool isOnline = true;
  late DashboardStorageService storageService;
  int? userId;
  bool? isSystem;
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription? _companySub;

  List<String> _selectedFilters = [];
  String? _selectedGroupBy;
  Map<String, bool> _groupExpanded = {};
  bool _allGroupsExpanded = true;

  bool hasFilters = false;
  bool hasGroupBy = false;

  final Map<String, String> filterTechnicalNames = {
    "To Do": "to_do",
    "My Transfer": "my_transfer",
    "Draft": "draft",
    "Waiting": "waiting",
    "Ready": "ready",
    "Receipts": "receipt",
    "Deliveries": "deliveries",
    "Internal": "internal",
    "Late": "late",
    "Planning Issues": "planning_issue",
    "Backorders": "backorder",
    "Warning": "warning",
  };

  final Map<String, String> groupTechnicalNames = {
    "Status": "state",
    "Source Document": "origin",
    "Operation Type": "picking_type_id",
  };

  StreamSubscription? _profileSub;

  @override
  void initState() {
    super.initState();
    _bloc = ReturnManagementBloc(OdooReturnManagementService());
    storageService = DashboardStorageService();
    _initAll();

    _profileSub = ProfileRefreshBus.onProfileRefresh.listen((_) {
      if (!mounted) return;
      _initAll(forceRefresh: true);
    });
  }

  @override
  void dispose() {
    _companySub?.cancel();
    _profileSub?.cancel();
    _bloc.close();
    super.dispose();
  }

  Future<void> _initAll({bool forceRefresh = false}) async {
    await _initializeServices();
    if (mounted) {
      _bloc.add(InitializeReturnManagement(forceRefresh: forceRefresh));
    }
  }

  Future<void> _initializeServices() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    isOnline = !connectivityResult.contains(ConnectivityResult.none);
    setState(() {});
  }


  /// Opens bottom sheet for selecting filters and grouping options
  void openFilterGroupBySheet(BuildContext pageContext) {
    List<String> tempFilters = [];
    String? tempGroupBy;
    tempFilters = List.from(_selectedFilters);
    tempGroupBy = _selectedGroupBy;

    showModalBottomSheet(
      context: pageContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (sheetContext, setDialogState) {
          final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
          final groupMap = groupTechnicalNames;

          return Container(
            height: MediaQuery.of(sheetContext).size.height * 0.8,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF232323) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Filter & Group By',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: Icon(
                            HugeIcons.strokeRoundedCancel01,
                            color: isDark ? Colors.white : Colors.black54,
                          ),
                          splashRadius: 20,
                        ),
                      ],
                    ),
                  ),

                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      indicator: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF2A2A2A)
                            : Theme.of(sheetContext).primaryColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      indicatorPadding: const EdgeInsets.all(4),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      overlayColor: WidgetStateProperty.all(Colors.transparent),
                      splashFactory: NoSplash.splashFactory,
                      labelColor: Colors.white,
                      unselectedLabelColor: isDark
                          ? Colors.grey[400]
                          : Colors.grey[600],
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      tabs: const [
                        Tab(height: 48, text: "Filter"),
                        Tab(height: 48, text: "Group By"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Expanded(
                    child: TabBarView(
                      children: [
                        SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (tempFilters.isNotEmpty) ...[
                                Text(
                                  'Active Filters',
                                  style: TextStyle(
                                    color: Theme.of(sheetContext).primaryColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: filterTechnicalNames.entries
                                      .where((e) =>
                                          tempFilters.contains(e.value))
                                      .map(
                                        (e) => _buildActiveFilterChip(
                                          isDark,
                                          e.key,
                                          () => setDialogState(
                                            () => tempFilters.remove(e.value),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                                const SizedBox(height: 18),
                              ],
                              Text(
                                'Filters',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: filterTechnicalNames.keys.map((label) {
                                  final tech = filterTechnicalNames[label]!;
                                  final selected = tempFilters.contains(tech);

                                  return ChoiceChip(
                                label: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: selected
                                        ? Colors.white
                                        : (isDark
                                              ? Colors.white
                                              : Colors.black87),
                                  ),
                                ),
                                selected: selected,
                                selectedColor:
                                    Theme.of(sheetContext).primaryColor,
                                backgroundColor: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Theme.of(sheetContext)
                                        .primaryColor
                                        .withValues(alpha: 0.08),
                                elevation: 0,
                                pressElevation: 0,
                                shadowColor: Colors.transparent,
                                surfaceTintColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: isDark
                                        ? Colors.grey[600]!
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                onSelected: (val) {
                                  setDialogState(() {
                                    if (val) {
                                      tempFilters.add(tech);
                                    } else {
                                      tempFilters.remove(tech);
                                    }
                                  });
                                },
                              );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),

                        ListView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                'Group returns by',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            _buildGroupOption(
                              isDark: isDark,
                              label: 'None',
                              subtitle: 'Display as a simple list',
                              isSelected: tempGroupBy == null,
                              onTap: () =>
                                  setDialogState(() => tempGroupBy = null),
                            ),
                            Divider(
                              height: 1,
                              color: isDark
                                  ? Colors.grey[800]
                                  : Colors.grey[200],
                            ),
                            for (final entry in groupMap.entries)
                              _buildGroupOption(
                                isDark: isDark,
                                label: entry.key,
                                subtitle: 'Group by ${entry.key.toLowerCase()}',
                                isSelected: tempGroupBy == entry.value,
                                onTap: () => setDialogState(
                                  () => tempGroupBy = entry.value,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF232323) : Colors.white,
                      border: Border(
                        top: BorderSide(
                          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: MoboButton.secondary(
                            label: 'Clear All',
                            borderRadius: 8,
                            onPressed: () {
                              setState(() {
                                _selectedFilters.clear();
                                _selectedGroupBy = null;
                                hasFilters = false;
                                hasGroupBy = false;
                                _groupExpanded.clear();
                              });
                              pageContext.read<ReturnManagementBloc>().add(
                                FetchStockPickings(0),
                              );
                              Navigator.pop(sheetContext);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MoboButton.primary(
                            label: 'Apply',
                            borderRadius: 8,
                            onPressed: () {
                              setState(() {
                                _selectedFilters = List.from(tempFilters);
                                _selectedGroupBy = tempGroupBy;
                                hasFilters = _selectedFilters.isNotEmpty;
                                hasGroupBy = _selectedGroupBy != null;
                                _groupExpanded.clear();
                              });
                              pageContext.read<ReturnManagementBloc>().add(
                                FetchStockPickings(
                                  0,
                                  searchText:
                                      _searchController.text.trim().isNotEmpty
                                      ? _searchController.text.trim()
                                      : null,
                                  filters: _selectedFilters,
                                  groupBy: _selectedGroupBy,
                                ),
                              );
                              Navigator.pop(sheetContext);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }


  /// A removable "Active Filters" pill (mobo tint + border, with an ✕).
  Widget _buildActiveFilterChip(
    bool isDark,
    String label,
    VoidCallback onRemove,
  ) {
    final primary = Theme.of(context).primaryColor;
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 8, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primary.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: primary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Icon(HugeIcons.strokeRoundedCancel01, size: 16, color: primary),
          ),
        ],
      ),
    );
  }

  /// A single "Group By" radio option (title + description).
  Widget _buildGroupOption({
    required bool isDark,
    required String label,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Radio<bool>(
              value: true,
              groupValue: isSelected,
              onChanged: (_) => onTap(),
              activeColor: Theme.of(context).primaryColor,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedView(ReturnManagementState state, bool isDark) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<ReturnManagementBloc>().add(
          FetchStockPickings(
            0,
            searchText: _searchController.text.trim().isNotEmpty
                ? _searchController.text.trim()
                : null,
            filters: _selectedFilters,
            groupBy: _selectedGroupBy,
          ),
        );
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: state.groupedPickings.length,
        itemBuilder: (context, index) {
          final groupNameRaw = state.groupedPickings.keys.elementAt(index);
          final groupName = (groupNameRaw == 'false' || groupNameRaw == 'None' || groupNameRaw.isEmpty) ? 'None' : groupNameRaw;
          final groupPickings = state.groupedPickings[groupNameRaw]!;
          final isExpanded = _groupExpanded[groupName] ?? true;

          return Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[900] : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
              boxShadow: [
                if (!isDark)
                  BoxShadow(
                    blurRadius: 16,
                    spreadRadius: 2,
                    offset: const Offset(0, 6),
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
              ],
            ),
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                InkWell(
                  onTap: () {
                    setState(() {
                      _groupExpanded[groupName] = !isExpanded;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedGroupBy == 'state'
                                    ? capitalizeFirstLetter(groupName)
                                    : groupName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${groupPickings.length} return${groupPickings.length != 1 ? 's' : ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          isExpanded ? HugeIcons.strokeRoundedArrowUp01 : HugeIcons.strokeRoundedArrowDown01,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ],
                    ),
                  ),
                ),
                if (isExpanded)
                  ...groupPickings.map(
                    (picking) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: _buildReturnTile(picking, isDark, context),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }


  Widget _buildReturnTile(
    Map<String, dynamic> picking,
    bool isDark,
    BuildContext context,
  ) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;
    final reference = picking['name'] ?? 'Return #${picking['id']}';
    final state = picking['state'] ?? 'unknown';
    final rawOrigin = picking['origin'];
    final hasOrigin =
        rawOrigin != null && rawOrigin != false && rawOrigin.toString().trim().isNotEmpty;
    final origin = hasOrigin ? rawOrigin.toString() : 'None';
    String partnerName = 'None';
    if (picking['partner_id'] is List && picking['partner_id'].length > 1) {
      partnerName = picking['partner_id'][1].toString();
    }
    final scheduledDate = (picking['scheduled_date'] == null ||
            picking['scheduled_date'] == false ||
            picking['scheduled_date'].toString() == 'false' ||
            picking['scheduled_date'].toString().trim().isEmpty)
        ? 'None'
        : picking['scheduled_date'].toString();
    final statusColor = _getStatusColor(state);
    final labelColor = isDark ? Colors.grey[500]! : Colors.grey[600]!;
    final valueColor = isDark ? Colors.grey[300]! : Colors.grey[800]!;

    Future<void> handleTap() async {
      if (!isOnline) {
        CustomSnackbar.showError(
          context,
          'Cannot return while offline. Please try again later.',
        );
        return;
      }
      final odooService = OdooReturnManagementService();
      final bloc = context.read<ReturnManagementBloc>();

      final result = await showDialog<int>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          surfaceTintColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: PickingBottomSheet(
              picking: picking,
              odooService: odooService,
              bloc: bloc,
            ),
          ),
        ),
      );

      if (result != null && mounted) {
        bloc.add(HighlightPicking(result));
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.05),
            offset: const Offset(0, 6),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: handleTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      reference,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : primaryColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusBadge(state, isDark, statusColor),
                ],
              ),
              const SizedBox(height: 8),

              _buildDetailRow(
                hasOrigin ? 'Return of:' : 'Origin:',
                origin,
                labelColor,
                valueColor,
              ),
              const SizedBox(height: 4),

              _buildDetailRow(
                'Partner:',
                partnerName,
                labelColor,
                valueColor,
              ),
              const SizedBox(height: 6),

              Row(
                children: [
                  Icon(
                    HugeIcons.strokeRoundedCalendar03,
                    size: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[500],
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Scheduled: $scheduledDate',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasOrigin) ...[
                    const SizedBox(width: 8),
                    Icon(
                      HugeIcons.strokeRoundedArrowTurnBackward,
                      size: 13,
                      color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Return',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  /// Builds a label : value row for the card, matching the screenshot layout.
  Widget _buildDetailRow(
    String label,
    String value,
    Color labelColor,
    Color valueColor,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: labelColor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            (value.isEmpty || value == 'false' || value == 'None')
                ? 'None'
                : value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: valueColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String state) {
    switch (state) {
      case 'done':
        return const Color(0xFF00A63E);
      case 'assigned':
        return const Color(0xFF3B82F6);
      case 'waiting':
      case 'confirmed':
        return const Color(0xFFF97316);
      case 'cancel':
        return const Color(0xFFEF4444);
      case 'draft':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFF6B7280);
    }
  }

  Widget _buildStatusBadge(String state, bool isDark, Color statusColor) {
    final String label = capitalizeFirstLetter(stateLabels[state] ?? state);
    final textColor = isDark ? Colors.white : statusColor;
    final backgroundColor = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : statusColor.withValues(alpha: 0.10);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  String capitalizeFirstLetter(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }


  /// Compact toggle rendered in the filter-indicator row's right slot when
  /// grouping is active — swaps the count text and the range badge for a
  /// single "Expand/Collapse All (N)" pill matching the pickings list style.
  Widget _buildGroupToggle(bool isDark, List<String> groupKeys) {
    // Derive label from actual state so the button label always tells the
    // truth (in case the user manually collapsed a single group).
    final expanded = groupKeys.every((k) => _groupExpanded[k] ?? true);
    return TextButton.icon(
      onPressed: () {
        setState(() {
          final target = !expanded;
          for (final key in groupKeys) {
            _groupExpanded[key] = target;
          }
          _allGroupsExpanded = target;
        });
      },
      icon: Icon(
        expanded
            ? HugeIcons.strokeRoundedArrowUp01
            : HugeIcons.strokeRoundedArrowDown01,
        size: 16,
      ),
      label: Text(
        '${expanded ? 'Collapse' : 'Expand'} All (${groupKeys.length})',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      style: TextButton.styleFrom(
        foregroundColor: isDark ? Colors.white : Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, BuildContext context) {
    final searchTerm = _searchController.text.trim();
    final hasSearch = searchTerm.isNotEmpty;
    final hasActiveFilters = hasFilters || hasGroupBy;
    final bool searchOnly = hasSearch && !hasActiveFilters;

    String title;
    String subtitle;
    String? actionLabel;
    VoidCallback? onAction;

    if (searchOnly) {
      title = 'No results for "$searchTerm"';
      subtitle = 'Try a different search term.';
      actionLabel = 'Clear Search';
      onAction = () {
        setState(() => _searchController.clear());
        context.read<ReturnManagementBloc>().add(
              FetchStockPickings(
                0,
                searchText: null,
                filters: _selectedFilters,
                groupBy: _selectedGroupBy,
              ),
            );
      };
    } else if (hasActiveFilters) {
      title = 'No returns found';
      subtitle = 'Try adjusting your filters or search term.';
      actionLabel = 'Clear All Filters';
      onAction = () {
        setState(() {
          _selectedFilters.clear();
          _selectedGroupBy = null;
          hasFilters = false;
          hasGroupBy = false;
          _groupExpanded.clear();
          _searchController.clear();
        });
        context.read<ReturnManagementBloc>().add(
              FetchStockPickings(0,
                  searchText: null, filters: const [], groupBy: null),
            );
      };
    } else {
      title = 'No returns found';
      subtitle = 'There are no return items available.';
    }

    return EmptyState(
      title: title,
      subtitle: subtitle,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  Widget _buildErrorState(bool isDark, BuildContext context) {
    return ErrorStateWidget(
      title: 'Something went wrong',
      message:
          'Unable to load returns. Please check your connection or try again.',
      errorType: ErrorType.general,
      onRetry: () async {
        await context.read<CompanyProvider>().initialize();
        ProfileRefreshBus.notifyProfileRefresh();
        CompanyRefreshBus.notify();
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocProvider.value(
      value: _bloc,
      child: Builder(
        builder: (innerContext) {
          _companySub?.cancel();
          _companySub = CompanyRefreshBus.stream.listen((_) {
            if (!mounted) return;
            innerContext.read<ReturnManagementBloc>().add(
              InitializeReturnManagement(),
            );
          });

          return Scaffold(
            backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
            body: BlocListener<ReturnManagementBloc, ReturnManagementState>(
              listenWhen: (prev, curr) =>
                  prev.error != curr.error &&
                  curr.error != null &&
                  curr.pickings.isNotEmpty,
              listener: (context, state) {
                CustomSnackbar.showError(context, state.error!);
              },
              child: BlocBuilder<ReturnManagementBloc, ReturnManagementState>(
                builder: (context, state) {
                  final displayedPickings = state.searchText?.isNotEmpty == true
                      ? state.filteredPickings
                      : state.pickings;

                  final showFullPageError =
                      state.error != null && state.pickings.isEmpty;

                  return Column(
                    children: [
                      ListSearchBar(
                        controller: _searchController,
                        hintText: 'Search by location or item...',
                        hasActiveFilters: hasFilters || hasGroupBy,
                        onFilterTap: () => openFilterGroupBySheet(context),
                        onChanged: (value) {
                          context.read<ReturnManagementBloc>().add(
                            SearchPickings(value),
                          );
                          setState(() {});
                        },
                      ),

                      if (state.isLoading)
                        const PaginationBarShimmer()
                      else if (!showFullPageError)
                        _buildPaginationBar(state, isDark, context),

                      if (state.isLoading)
                        const Expanded(child: ReturnListShimmer(itemCount: 6))
                      else if (showFullPageError)
                        Expanded(child: _buildErrorState(isDark, context))
                      else if (displayedPickings.isEmpty)
                        Expanded(
                          child: _buildEmptyState(isDark, context),
                        )
                      else ...[
                        hasGroupBy && state.groupedPickings.isNotEmpty
                            ? Expanded(child: _buildGroupedView(state, isDark))
                            : Expanded(
                                child: RefreshIndicator(
                                  onRefresh: () async {
                                    context.read<ReturnManagementBloc>().add(
                                      FetchStockPickings(
                                        0,
                                        searchText:
                                            _searchController.text
                                                .trim()
                                                .isNotEmpty
                                            ? _searchController.text.trim()
                                            : null,
                                        filters: _selectedFilters,
                                        groupBy: _selectedGroupBy,
                                      ),
                                    );
                                  },
                                  child: ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      4,
                                      16,
                                      16,
                                    ),
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    itemCount: displayedPickings.length,
                                    itemBuilder: (context, index) {
                                      final picking = displayedPickings[index];
                                      return _buildReturnTile(
                                        picking,
                                        isDark,
                                        context,
                                      );
                                    },
                                  ),
                                ),
                              ),
                      ],
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }


  Widget _buildPaginationBar(
    ReturnManagementState state,
    bool isDark,
    BuildContext context,
  ) {
    // Group-by is surfaced via the "Expand/Collapse All (N)" toggle on the
    // right; count only actual filters here so the pill doesn't say
    // "1 active" when only a group-by is set.
    final filterCount = _selectedFilters.length;
    final canGoPrev = state.currentPage > 0;
    final canGoNext =
        (state.currentPage + 1) * ReturnManagementState.itemsPerPage <
        state.totalCount;
    final hasPagination = state.totalCount > 0;
    // Show the prev/next arrows only when the data actually spans more than
    // one page; a single-page list gets the range badge alone.
    final needsPageArrows =
        state.totalCount > ReturnManagementState.itemsPerPage;

    final grouped =
        hasGroupBy && state.groupedPickings.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildFilterIndicator(isDark, filterCount),

          if (grouped)
            _buildGroupToggle(isDark, state.groupedPickings.keys.toList())
          else if (hasPagination)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? Colors.white24 : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state.pageRange,
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      Text(
                        '/',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      Text(
                        '${state.totalCount}',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (needsPageArrows) ...[
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    HugeIcons.strokeRoundedArrowLeft01,
                    size: 25,
                    color: canGoPrev
                        ? (isDark ? Colors.white70 : Colors.black87)
                        : (isDark ? Colors.grey[800] : Colors.grey.withValues(alpha: 0.4)),
                  ),
                  onPressed: canGoPrev
                      ? () {
                          context.read<ReturnManagementBloc>().add(
                            FetchStockPickings(
                              state.currentPage - 1,
                              searchText: _searchController.text.trim().isNotEmpty
                                  ? _searchController.text.trim()
                                  : null,
                              filters: _selectedFilters,
                              groupBy: _selectedGroupBy,
                            ),
                          );
                        }
                      : null,
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    HugeIcons.strokeRoundedArrowRight01,
                    size: 25,
                    color: canGoNext
                        ? (isDark ? Colors.white70 : Colors.black87)
                        : (isDark ? Colors.grey[800] : Colors.grey.withValues(alpha: 0.4)),
                  ),
                  onPressed: canGoNext
                      ? () {
                          context.read<ReturnManagementBloc>().add(
                            FetchStockPickings(
                              state.currentPage + 1,
                              searchText: _searchController.text.trim().isNotEmpty
                                  ? _searchController.text.trim()
                                  : null,
                              filters: _selectedFilters,
                              groupBy: _selectedGroupBy,
                            ),
                          );
                        }
                      : null,
                ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFilterIndicator(bool isDark, int count) {
    if (count == 0) {
      return Text(
        'No filters applied',
        style: TextStyle(
          color: isDark ? Colors.white : const Color(0xff1E1E1E),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      );
    }
    final accent = isDark ? Colors.white : Colors.black;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent, width: 1.2),
      ),
      child: Text(
        '$count active',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: accent,
        ),
      ),
    );
  }




  static const Map<String, String> stateLabels = {
    'draft': 'Draft',
    'confirmed': 'Waiting',
    'assigned': 'Ready',
    'done': 'Done',
    'waiting': 'Waiting Another Op.',
    'cancel': 'Cancelled',
  };
}
