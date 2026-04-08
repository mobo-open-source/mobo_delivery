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
import 'package:shimmer/shimmer.dart';
import '../bloc/return_management_bloc.dart';
import '../bloc/return_management_event.dart';
import '../bloc/return_management_state.dart';
import '../services/odoo_return_service.dart';
import '../widgets/picking_bottom_sheet.dart';

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
  // ───────────────────────────────────────────────
  //  State & Controllers
  // ───────────────────────────────────────────────
  late ReturnManagementBloc _bloc;
  bool isOnline = true;
  late DashboardStorageService storageService;
  int? userId;
  bool? isSystem;
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription? _companySub;

  // Filter & Group state
  List<String> _selectedFilters = [];
  String? _selectedGroupBy;
  Map<String, bool> _groupExpanded = {};

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

    // Listen to profile/account changes → reload data
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

  // ───────────────────────────────────────────────
  //  Filter & Group Bottom Sheet
  // ───────────────────────────────────────────────

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
                  // Header
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
                            Icons.close,
                            color: isDark ? Colors.white : Colors.black54,
                          ),
                          splashRadius: 20,
                        ),
                      ],
                    ),
                  ),

                  // Tabs
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
                        boxShadow: [
                          BoxShadow(
                            color: isDark
                                ? const Color(0xFF2A2A2A).withValues(alpha: 0.3)
                                : Theme.of(
                                    sheetContext,
                                  ).primaryColor.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      indicatorPadding: const EdgeInsets.all(4),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: Colors.white,
                      unselectedLabelColor: isDark
                          ? Colors.grey[400]
                          : Colors.grey[600],
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      unselectedLabelStyle: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      tabs: [
                        Tab(height: 48, text: "Filter"),
                        Tab(height: 48, text: "Group By"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Expanded(
                    child: TabBarView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: filterTechnicalNames.keys.map((label) {
                              final tech = filterTechnicalNames[label]!;
                              final selected = tempFilters.contains(tech);

                              return FilterChip(
                                label: Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: selected
                                        ? Colors.white
                                        : (isDark
                                              ? Colors.white70
                                              : Colors.black87),
                                  ),
                                ),
                                selected: selected,
                                selectedColor: isDark
                                    ? const Color(0xFF131313)
                                    : Theme.of(sheetContext).primaryColor,
                                backgroundColor: isDark
                                    ? const Color(0xFF2A2A2A)
                                    : Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                checkmarkColor: Colors.white,
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
                        ),

                        ListView(
                          padding: const EdgeInsets.all(20),
                          children: groupMap.keys.map((label) {
                            final tech = groupMap[label]!;
                            final isSelected = tempGroupBy == tech;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    setDialogState(() {
                                      tempGroupBy = tech;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    margin: const EdgeInsets.only(
                                      bottom: 6,
                                      left: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isSelected
                                              ? Icons.radio_button_checked
                                              : Icons.radio_button_unchecked,
                                          color: isSelected
                                              ? (isDark
                                                    ? Colors.white
                                                    : Theme.of(
                                                        sheetContext,
                                                      ).primaryColor)
                                              : Colors.grey,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          label,
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.black87,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),

                  // Action bar
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[850] : Colors.grey[50],
                      border: Border(
                        top: BorderSide(
                          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
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
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark
                                  ? Colors.white
                                  : Colors.black87,
                              side: BorderSide(
                                color: isDark
                                    ? Colors.grey[600]!
                                    : Colors.grey[300]!,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Clear All',
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
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
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark
                                  ? Colors.white
                                  : Theme.of(sheetContext).primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Apply',
                              style: TextStyle(
                                color: isDark ? Colors.black : Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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

  // ───────────────────────────────────────────────
  //  Grouped View (when grouping is active)
  // ───────────────────────────────────────────────

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
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: state.groupedPickings.length,
        itemBuilder: (context, index) {
          final groupNameRaw = state.groupedPickings.keys.elementAt(index);
          final groupName = (groupNameRaw == 'false' || groupNameRaw == 'None' || groupNameRaw.isEmpty) ? 'None' : groupNameRaw;
          final groupPickings = state.groupedPickings[groupNameRaw]!;
          final isExpanded = _groupExpanded[groupNameRaw] ?? true;

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
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
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

  // ───────────────────────────────────────────────
  //  Individual Return Tile
  // ───────────────────────────────────────────────

  Widget _buildReturnTile(
    Map<String, dynamic> picking,
    bool isDark,
    BuildContext context,
  ) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;
    final reference = picking['name'] ?? 'Return #${picking['id']}';
    final state = picking['state'] ?? 'unknown';
    final origin = (picking['origin'] == null || picking['origin'] == false)
        ? 'None'
        : picking['origin'].toString();
    String partnerName = 'None';
    if (picking['partner_id'] is List && picking['partner_id'].length > 1) {
      partnerName = picking['partner_id'][1].toString();
    }
    final scheduledDate = (picking['scheduled_date'] == null ||
            picking['scheduled_date'] == false)
        ? 'None'
        : picking['scheduled_date'].toString();
    final statusColor = _getStatusColor(state);
    final labelColor = isDark ? Colors.grey[500]! : Colors.grey[600]!;
    final valueColor = isDark ? Colors.grey[300]! : Colors.grey[800]!;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        if (!isOnline) {
          CustomSnackbar.showError(
            context,
            'Cannot return while offline. Please try again later.',
          );
          return;
        }
        final odooService = OdooReturnManagementService();
        final bloc = context.read<ReturnManagementBloc>();

        final result = await showModalBottomSheet<int>(
          context: context,
          backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => PickingBottomSheet(
            picking: picking,
            odooService: odooService,
            bloc: bloc,
          ),
        );

        if (result != null && mounted) {
          bloc.add(HighlightPicking(result));
        }
      },
      child: Container(
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Row 1: Reference + Status Badge ──
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

              // ── Row 2: Origin ──
              _buildDetailRow(
                'Origin:',
                origin,
                labelColor,
                valueColor,
              ),
              const SizedBox(height: 4),

              // ── Row 3: Partner ──
              _buildDetailRow(
                'Partner:',
                partnerName,
                labelColor,
                valueColor,
              ),
              const SizedBox(height: 6),

              // ── Row 4: Scheduled Date ──
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
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
                ],
              ),
            ],
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
        return Colors.green;
      case 'assigned':
        return Colors.blue;
      case 'waiting':
      case 'confirmed':
        return Colors.orange;
      case 'cancel':
        return Colors.red;
      default:
        return Colors.grey;
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
          fontWeight: isDark ? FontWeight.bold : FontWeight.w600,
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

  // ───────────────────────────────────────────────
  //  Empty & Error States
  // ───────────────────────────────────────────────

  Widget _buildEmptyState(bool isDark, BuildContext context) {
    final hasAnyFilter = hasFilters || hasGroupBy || _searchController.text.isNotEmpty;
    return EmptyState(
      title: 'No returns found',
      subtitle: hasAnyFilter
          ? 'Try adjusting your filters or search term'
          : 'There are no return items available.',
      lottieAsset: 'assets/lotties/no_data.json',
      actionLabel: hasAnyFilter ? 'Clear All Filters' : null,
      onAction: hasAnyFilter
          ? () {
              setState(() {
                _selectedFilters.clear();
                _selectedGroupBy = null;
                hasFilters = false;
                hasGroupBy = false;
                _groupExpanded.clear();
                _searchController.clear();
              });
              context.read<ReturnManagementBloc>().add(
                FetchStockPickings(0, searchText: null, filters: const [], groupBy: null),
              );
            }
          : null,
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

  // ───────────────────────────────────────────────
  //  Main Build Method
  // ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocProvider.value(
      value: _bloc,
      child: Builder(
        builder: (innerContext) {
          // Listen to company refresh events
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
              listener: (context, state) {},
              child: BlocBuilder<ReturnManagementBloc, ReturnManagementState>(
                builder: (context, state) {
                  final displayedPickings = state.searchText?.isNotEmpty == true
                      ? state.filteredPickings
                      : state.pickings;

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

                      // ── Pagination Bar ──
                      if (!state.isLoading && state.error == null)
                        _buildPaginationBar(state, isDark, context),

                      if (state.isLoading)
                        Expanded(child: _buildListShimmer(isDark))
                      else if (state.error != null)
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
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
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

  // ───────────────────────────────────────────────
  //  Pagination Bar (filter indicator + page range + arrows)
  // ───────────────────────────────────────────────

  Widget _buildPaginationBar(
    ReturnManagementState state,
    bool isDark,
    BuildContext context,
  ) {
    final filterCount = _selectedFilters.length + (hasGroupBy ? 1 : 0);
    final canGoPrev = state.currentPage > 0;
    final canGoNext =
        (state.currentPage + 1) * ReturnManagementState.itemsPerPage <
        state.totalCount;
    final hasPagination = state.totalCount > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ── Filter indicator ──
          _buildFilterIndicator(isDark, filterCount),

          if (hasPagination)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Page range pill ──
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
                // ── Navigation arrows ──
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    HugeIcons.strokeRoundedArrowLeft01,
                    size: 25,
                    color: canGoPrev
                        ? (isDark ? Colors.white70 : Colors.black87)
                        : (isDark ? Colors.grey[800] : Colors.grey.withValues(alpha: 0.7)),
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
                        : (isDark ? Colors.grey[800] : Colors.grey.withValues(alpha: 0.7)),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$count active',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.black : Colors.white,
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────
  //  Shimmer Loading (card-shaped, matches tile layout)
  // ───────────────────────────────────────────────

  Widget _buildListShimmer(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 6,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Shimmer.fromColors(
          baseColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[300]!,
          highlightColor: isDark ? const Color(0xFF3A3A3A) : Colors.grey[100]!,
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Reference + badge row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 140,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Container(
                      width: 52,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Origin row
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 100,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Partner row
                Row(
                  children: [
                    Container(
                      width: 60,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 160,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Scheduled row
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 200,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────
  //  Static helpers (colors, labels, date formatting)
  // ───────────────────────────────────────────────

  static const Map<String, String> stateLabels = {
    'draft': 'Draft',
    'confirmed': 'Waiting',
    'assigned': 'Ready',
    'done': 'Done',
    'waiting': 'Waiting Another Op.',
    'cancel': 'Cancelled',
  };
}
