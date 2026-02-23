import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:lottie/lottie.dart';
import '../../../Dashboard/infrastructure/profile_refresh_bus.dart';
import '../../../Dashboard/services/odoo_dashboard_service.dart';
import '../../../Dashboard/services/storage_service.dart';
import '../../../core/company/infrastructure/company_refresh_bus.dart';
import '../../../core/company/providers/company_provider.dart';
import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../Pickings/PickingFormPage/services/hive_service.dart';
import '../../shimmer_loading.dart';
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
  bool isOnline = true;
  late OdooDashboardService _odooService;
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

  @override
  void initState() {
    super.initState();
    storageService = DashboardStorageService();
    _initAll();
  }

  @override
  void dispose() {
    _companySub?.cancel();
    super.dispose();
  }

  Future<void> _initAll() async {
    await _initializeServices();
  }

  Future<void> _initializeServices() async {
    isOnline = await _odooService.checkNetworkConnectivity();
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
                            ? Color(0xFF2A2A2A)
                            : AppStyle.primaryColor,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: isDark
                                ? Color(0xFF2A2A2A).withOpacity(0.3)
                                : AppStyle.primaryColor.withOpacity(0.3),
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
                                    ? Color(0xFF131313)
                                    : AppStyle.primaryColor,
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
                                                    : AppStyle.primaryColor)
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
                                  : AppStyle.primaryColor,
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
        itemCount: state.groupedPickings.length,
        itemBuilder: (context, index) {
          final groupKey = state.groupedPickings.keys.elementAt(index);
          final items = state.groupedPickings[groupKey]!;
          final isExpanded = _groupExpanded[groupKey] ?? true;

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.black.withOpacity(0.06),
                ),
                boxShadow: [
                  if (!isDark)
                    BoxShadow(
                      blurRadius: 16,
                      spreadRadius: 2,
                      offset: const Offset(0, 6),
                      color: Colors.black.withOpacity(0.08),
                    ),
                ],
              ),
              child: Column(
                children: [
                  ListTile(
                    title: Text(
                      groupKey,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    subtitle: Text(
                      "${items.length} returns",
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[700],
                      ),
                    ),
                    trailing: Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    onTap: () {
                      setState(() {
                        _groupExpanded[groupKey] = !isExpanded;
                      });
                    },
                  ),
                  if (isExpanded)
                    ...items.map(
                      (picking) => Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: _buildReturnTile(picking, isDark, context),
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
  //  Individual Return Tile
  // ───────────────────────────────────────────────

  Widget _buildReturnTile(
    Map<String, dynamic> picking,
    bool isDark,
    BuildContext context,
  ) {
    final dateInfo = _getFormattedDateInfo(picking['scheduled_date']);
    final rawState = picking['state'] ?? 'unknown';
    final readableState = stateLabels[rawState] ?? rawState;
    final statusColor = stateColors[rawState] ?? Colors.grey;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[850]! : Colors.grey[200]!,
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withOpacity(0.05),
            offset: const Offset(0, 6),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ListTile(
        title: Text(
          picking['name'] ?? 'Return #${picking['id']}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : AppStyle.primaryColor,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (picking['partner_id'] is List &&
                picking['partner_id'].length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  "Partner: ${picking['partner_id'][1]}",
                  style: TextStyle(
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                "Scheduled: ${dateInfo['label']}",
                style: TextStyle(
                  color: dateInfo['color'] as Color? ?? Colors.grey,
                ),
              ),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            readableState,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
        onTap: () async {
          final odooService = OdooReturnManagementService();
          final bloc = context.read<ReturnManagementBloc>();

          final result = await showModalBottomSheet<int>(
            context: context,
            backgroundColor:
            Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[900]
                : Colors.grey[50],
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
      ),
    );
  }

  // ───────────────────────────────────────────────
  //  Empty & Error States
  // ───────────────────────────────────────────────

  Widget _buildCenteredLottie({
    required String lottie,
    required String title,
    String? subtitle,
    Widget? button,
    required bool isDark,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Lottie.asset(lottie, width: 260),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                  if (button != null) ...[const SizedBox(height: 12), button],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(bool isDark, hasFilters, BuildContext context) {
    return _buildCenteredLottie(
      lottie: 'assets/empty_ghost.json',
      title: 'No return items found',
      subtitle: hasFilters ? 'Try adjusting your filter' : null,
      isDark: isDark,
      button: hasFilters
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? Colors.white : AppStyle.primaryColor,
                side: BorderSide(
                  color: isDark
                      ? Colors.grey[600]!
                      : AppStyle.primaryColor.withOpacity(0.3),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                setState(() {
                  _selectedFilters.clear();
                  _selectedGroupBy = null;
                  hasFilters = false;
                  hasGroupBy = false;
                  _groupExpanded.clear();
                });
                context.read<ReturnManagementBloc>().add(FetchStockPickings(0));
              },
              child: Text(
                'Clear All Filters',
                style: TextStyle(
                  color: isDark ? Colors.white : AppStyle.primaryColor,
                  fontWeight: FontWeight.w400,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildErrorState(bool isDark, BuildContext context) {
    return _buildCenteredLottie(
      lottie: 'assets/Error_404.json',
      title: 'Something went wrong',
      subtitle: 'Pull to refresh or tap retry',
      isDark: isDark,
      button: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? Colors.white : AppStyle.primaryColor,
          side: BorderSide(
            color: isDark
                ? Colors.grey[600]!
                : AppStyle.primaryColor.withOpacity(0.3),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () async {
          await context.read<CompanyProvider>().initialize();
          ProfileRefreshBus.notifyProfileRefresh();
          CompanyRefreshBus.notify();
        },
        child: Text(
          'Retry',
          style: TextStyle(
            color: isDark ? Colors.white : AppStyle.primaryColor,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────
  //  Main Build Method
  // ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final odooService = OdooReturnManagementService();
    final hiveService = HiveService();

    return BlocProvider(
      create: (context) =>
          ReturnManagementBloc(odooService, hiveService)
            ..add(InitializeReturnManagement()),
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

          final bloc = innerContext.read<ReturnManagementBloc>();

          return Scaffold(
            backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
            body: BlocListener<ReturnManagementBloc, ReturnManagementState>(
              listener: (context, state) {
                if (state.error != null) {
                  Expanded(
                    child: Center(child: _buildErrorState(isDark, context)),
                  );
                }
              },
              child: BlocBuilder<ReturnManagementBloc, ReturnManagementState>(
                builder: (context, state) {
                  final displayedPickings = state.searchText?.isNotEmpty == true
                      ? state.filteredPickings
                      : state.pickings;

                  return Stack(
                    children: [
                      Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 17.0,
                              vertical: 10.0,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: isDark
                                          ? const Color(0xFF2A2A2A)
                                          : Colors.white,
                                      border: Border.all(
                                        color: Colors.transparent,
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          spreadRadius: 1,
                                          blurRadius: 6,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: TextField(
                                      controller: _searchController,
                                      decoration: InputDecoration(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                        hintText: 'Search by Item name',
                                        hintStyle: TextStyle(
                                          color: isDark
                                              ? Colors.white
                                              : Color(0xff1E1E1E),
                                          fontWeight: FontWeight.w400,
                                          fontStyle: FontStyle.normal,
                                          fontSize: 15,
                                          height: 1.0,
                                          letterSpacing: 0.0,
                                        ),
                                        prefixIcon: IconButton(
                                          icon: Icon(
                                            HugeIcons
                                                .strokeRoundedFilterHorizontal,
                                            color: isDark
                                                ? Colors.grey[400]
                                                : Colors.grey[600],
                                            size: 18,
                                          ),
                                          tooltip: 'Filter & Group By',
                                          onPressed: () {
                                            openFilterGroupBySheet(context);
                                          },
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide(
                                            color: AppStyle.primaryColor,
                                          ),
                                        ),
                                      ),
                                      onChanged: (value) {
                                        context
                                            .read<ReturnManagementBloc>()
                                            .add(SearchPickings(value));
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (state.isLoading) ...[
                            Expanded(
                              child:
                                  const GridViewShimmer(),
                            ),
                          ] else ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Builder(
                                  builder: (context) {
                                    hasFilters = _selectedFilters.isNotEmpty;
                                    hasGroupBy =
                                        (_selectedGroupBy?.isNotEmpty ?? false);

                                    if (!hasFilters && !hasGroupBy) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 6,
                                        ),
                                        child: Text(
                                          "No filters applied",
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.black54,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      );
                                    }

                                    String? groupDisplayName;
                                    if (hasGroupBy) {
                                      final groupMap = {
                                        "Status": "state",
                                        "Source Document": "origin",
                                        "Operation Type": "picking_type",
                                      };

                                      groupDisplayName = groupMap.keys
                                          .firstWhere(
                                            (key) =>
                                                groupMap[key] ==
                                                _selectedGroupBy,
                                            orElse: () => _selectedGroupBy!
                                                .replaceAll('_', ' '),
                                          );
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.all(24.0),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (hasFilters)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? Colors.white70
                                                    : Colors.black,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    _selectedFilters.length
                                                        .toString(),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: isDark
                                                          ? Colors.black
                                                          : Colors.white,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    "Active",
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: isDark
                                                          ? Colors.black
                                                          : Colors.white,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (hasGroupBy) ...[
                                            if (hasFilters)
                                              const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? Colors.white70
                                                    : Colors.black,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    HugeIcons
                                                        .strokeRoundedLayer,
                                                    size: 16,
                                                    color: isDark
                                                        ? Colors.black
                                                        : Colors.white,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    groupDisplayName ?? "Group",
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: isDark
                                                          ? Colors.black
                                                          : Colors.white,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white10
                                            : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: isDark
                                              ? Colors.white24
                                              : Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            state.pageRange,
                                            style: TextStyle(
                                              color: isDark
                                                  ? Colors.white70
                                                  : Colors.black87,
                                              fontSize: 14,
                                              fontWeight: FontWeight.normal,
                                            ),
                                          ),
                                          Text(
                                            '/',
                                            style: TextStyle(
                                              color: isDark
                                                  ? Colors.white70
                                                  : Colors.black87,
                                              fontSize: 14,
                                              fontWeight: FontWeight.normal,
                                            ),
                                          ),
                                          Text(
                                            '${state.totalCount}',
                                            style: TextStyle(
                                              color: isDark
                                                  ? Colors.white70
                                                  : Colors.black87,
                                              fontSize: 14,
                                              fontWeight: FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: Icon(
                                        HugeIcons.strokeRoundedArrowLeft01,
                                        size: 25,
                                        color: state.currentPage > 0
                                            ? (isDark
                                                  ? Colors.white70
                                                  : Colors.black87)
                                            : (isDark
                                                  ? Colors.grey[800]
                                                  : Colors.grey.withOpacity(
                                                      0.7,
                                                    )),
                                      ),
                                      onPressed: state.currentPage > 0
                                          ? () {
                                              context
                                                  .read<ReturnManagementBloc>()
                                                  .add(
                                                    FetchStockPickings(
                                                      state.currentPage - 1,
                                                      searchText:
                                                          state.searchText,
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
                                        color:
                                            (state.currentPage + 1) *
                                                    OdooReturnManagementService
                                                        .itemsPerPage <
                                                state.totalCount
                                            ? (isDark
                                                  ? Colors.white70
                                                  : Colors.black87)
                                            : (isDark
                                                  ? Colors.grey[800]
                                                  : Colors.grey.withOpacity(
                                                      0.7,
                                                    )),
                                      ),
                                      onPressed:
                                          (state.currentPage + 1) *
                                                  OdooReturnManagementService
                                                      .itemsPerPage <
                                              state.totalCount
                                          ? () {
                                              context
                                                  .read<ReturnManagementBloc>()
                                                  .add(
                                                    FetchStockPickings(
                                                      state.currentPage + 1,
                                                      searchText:
                                                          state.searchText,
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
                            if (displayedPickings.isEmpty) ...[
                              Expanded(
                                child: _buildEmptyState(
                                  isDark,
                                  hasFilters,
                                  context,
                                ),
                              ),
                            ] else ...[
                              hasGroupBy && state.groupedPickings.isNotEmpty
                                  ? Expanded(
                                      child: _buildGroupedView(state, isDark),
                                    )
                                  : Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: RefreshIndicator(
                                          onRefresh: () async {
                                            context
                                                .read<ReturnManagementBloc>()
                                                .add(
                                                  FetchStockPickings(
                                                    0,
                                                    searchText:
                                                        _searchController.text
                                                            .trim()
                                                            .isNotEmpty
                                                        ? _searchController.text
                                                              .trim()
                                                        : null,
                                                    filters: _selectedFilters,
                                                    groupBy: _selectedGroupBy,
                                                  ),
                                                );
                                          },
                                          child: ListView.builder(
                                            itemCount: displayedPickings.length,
                                            itemBuilder: (context, index) {
                                              final picking =
                                                  displayedPickings[index];
                                              final dateInfo =
                                                  _getFormattedDateInfo(
                                                    picking['scheduled_date'],
                                                  );
                                              final String label =
                                                  dateInfo['label'];
                                              final Color? color =
                                                  dateInfo['color'];
                                              final String rawState =
                                                  picking['state'] ?? 'unknown';
                                              final String readableState =
                                                  stateLabels[rawState] ??
                                                  rawState;
                                              final Color statusColor =
                                                  stateColors[rawState] ??
                                                  Colors.black;

                                              return AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 600,
                                                ),
                                                curve: Curves.easeInOut,
                                                decoration: BoxDecoration(
                                                  color: isDark ? Colors.grey[850] : Colors.white,
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: isDark ? Colors.grey[850]! : Colors.grey[200]!,
                                                    width: 0.5,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: const Color(0xFF000000).withOpacity(0.05),
                                                      offset: const Offset(0, 6),
                                                      blurRadius: 16,
                                                      spreadRadius: 2,
                                                    ),
                                                  ],
                                                ),
                                                margin: const EdgeInsets.only(bottom: 16),
                                                child: ListTile(
                                                  title: Text(
                                                    picking['name'] ??
                                                        'Unnamed Picking',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      color: isDark
                                                          ? Colors.white
                                                          : AppStyle.primaryColor,
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                  subtitle: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      if (picking['partner_id'] !=
                                                              null &&
                                                          picking['partner_id']
                                                              is List &&
                                                          picking['partner_id']
                                                                  .length >
                                                              1) ...[
                                                        Text(
                                                          "Delivery Address: ${picking['partner_id'][1]}",
                                                          style: TextStyle(
                                                            color: isDark
                                                                ? Colors.white60
                                                                : Colors.black54,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 4),
                                                      ],
                                                      if (picking['origin']
                                                              ?.toString()
                                                              .toLowerCase()
                                                              .contains(
                                                                'return',
                                                              ) ??
                                                          false)
                                                        Text(
                                                          '${picking['origin']}',
                                                          style: TextStyle(
                                                            color: Colors
                                                                .orange[700]!,
                                                          ),
                                                        )
                                                      else
                                                        Text(
                                                          'Scheduled: $label',
                                                          style: TextStyle(
                                                            color: isDark
                                                                ? Colors.white54
                                                                : (color ??
                                                                      Colors
                                                                          .black),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  trailing: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: statusColor
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      readableState,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: statusColor,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                  onTap: () async {
                                                    if (isOnline) {
                                                      final result =
                                                          await showModalBottomSheet<
                                                            int
                                                          >(
                                                            context: context,
                                                            backgroundColor:
                                                            Theme.of(context).brightness == Brightness.dark
                                                                ? Colors.grey[900]
                                                                : Colors.grey[50],
                                                            shape: const RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.vertical(
                                                                    top:
                                                                        Radius.circular(
                                                                          16,
                                                                        ),
                                                                  ),
                                                            ),
                                                            builder: (context) =>
                                                                PickingBottomSheet(
                                                                  picking:
                                                                      picking,
                                                                  odooService:
                                                                      odooService,
                                                                  bloc: bloc,
                                                                ),
                                                          );
                                                      if (result != null) {
                                                        context
                                                            .read<
                                                              ReturnManagementBloc
                                                            >()
                                                            .add(
                                                              HighlightPicking(
                                                                result,
                                                              ),
                                                            );
                                                      }
                                                    } else {
                                                      CustomSnackbar.showError(
                                                        context,
                                                        'Cannot return while offline. Please try again later.',
                                                      );
                                                    }
                                                  },
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                            ],
                          ],
                        ],
                      ),
                      if (!state.isLoading) ...[
                        if (state.isFetchingMore)
                          Container(
                            child: Center(
                              child: LoadingAnimationWidget.staggeredDotsWave(
                                color: AppStyle.primaryColor,
                                size: 50,
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
  //  Static helpers (colors, labels, date formatting)
  // ───────────────────────────────────────────────

  static const Map<String, Color> stateColors = {
    'draft': Colors.grey,
    'confirmed': Colors.orange,
    'assigned': Colors.blue,
    'done': Colors.green,
    'waiting': Colors.purple,
    'cancel': Colors.red,
  };

  static const Map<String, String> stateLabels = {
    'draft': 'Draft',
    'confirmed': 'Waiting',
    'assigned': 'Ready',
    'done': 'Done',
    'waiting': 'Waiting Another Op.',
    'cancel': 'Cancelled',
  };

  Map<String, dynamic> _getFormattedDateInfo(String? dateStr) {
    if (dateStr == null) return {'label': 'Unknown', 'color': Colors.grey};
    try {
      final scheduled = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final scheduledDay = DateTime(
        scheduled.year,
        scheduled.month,
        scheduled.day,
      );
      final diff = scheduledDay.difference(today).inDays;
      if (diff == 0) {
        return {'label': 'Today', 'color': Colors.amber[900]};
      } else if (diff > 0) {
        return {
          'label': 'in $diff day${diff > 1 ? 's' : ''}',
          'color': Colors.black,
        };
      } else {
        return {
          'label': '${diff.abs()} day${diff.abs() > 1 ? 's' : ''} ago',
          'color': Colors.red[300],
        };
      }
    } catch (_) {
      return {'label': dateStr, 'color': Colors.grey};
    }
  }
}
