import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:provider/provider.dart';
import '../../../../core/company/session/company_session_manager.dart';
import '../../../../Dashboard/infrastructure/profile_refresh_bus.dart';
import '../../../../core/company/infrastructure/company_refresh_bus.dart';
import '../../../../core/company/providers/company_provider.dart';
import '../../../../core/providers/motion_provider.dart';
import '../../../../shared/utils/globals.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/list_search_bar.dart';
import '../../../../shared/widgets/error_state_widget.dart';
import '../../../../shared/widgets/loaders/list_shimmer.dart';
import '../../../../shared/widgets/loading_overlay.dart';
import '../../CreateNewPicking/pages/create_picking_page.dart';
import '../../PickingFormPage/pages/picking_details_page.dart';
import '../../PickingFormPage/services/odoo_picking_form_service.dart';
import '../services/picking_service.dart';

/// Main grouped/list view of all stock pickings / transfers, with support for:
/// • Search by location/item
/// • Filtering (status, type, date, custom filters like "My Transfer", "Late", "Backorders")
/// • Grouping (by status, source document, operation type)
/// • Pagination per location
/// • Offline-aware loading via `PickingService`
/// • Pull-to-refresh & company change refresh
///
/// This is the central "Pickings" screen in the app.
class PickingsGroupedPage extends StatefulWidget {
  const PickingsGroupedPage({super.key});

  @override
  State<PickingsGroupedPage> createState() => _PickingsGroupedPageState();
}

class _PickingsGroupedPageState extends State<PickingsGroupedPage> {
  // ───────────────────────────────────────────────
  //  Controllers & State
  // ───────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  final PickingService _service = PickingService();

  String? selectedStateLabel;
  String? selectedStateValue;
  DateTime? selectedScheduleDate;
  DateTime? selectedDeadlineDate;
  String selectedType = '';
  final Map<String, String> stateMap = {
    'draft': 'Draft',
    'confirmed': 'Waiting',
    'waiting': 'Waiting Another Operations',
    'assigned': 'Ready',
    'done': 'Done',
    'cancel': 'Cancelled',
  };

  bool isFilterApplied = false;
  String _searchTerm = '';
  bool isLoading = true;
  bool isPageLoading = false;
  bool _isFreshFetch = false;
  final Set<String> _isFetchingMore = {};
  int initialCount = 0;

  // ───────────────────────────────────────────────
  //  Lifecycle & Subscriptions
  // ───────────────────────────────────────────────
  StreamSubscription? _profileSub;
  late final StreamSubscription _companySub;

  List<String> _selectedFilters = [];
  String? _selectedGroupBy;
  Map<String, List<Map<String, dynamic>>> _groupedPickings = {};
  Map<String, bool> _groupExpanded = {};
  bool hasFilters = false;
  bool hasGroupBy = false;
  Timer? _searchDebounce;
  bool catchError = false;
  bool _allGroupsExpanded = true;

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
    "Operation Type": "picking_type",
  };

  @override
  void initState() {
    super.initState();
    initializeAndFetch();

    // Listen to company changes (e.g. switch company) → reload data
    _companySub = CompanyRefreshBus.stream.listen((_) async {
      if (!mounted) return;
      _onCompanyRefresh();
    });

    // Listen to profile/account changes (e.g. switch account) → reload data
    _profileSub = ProfileRefreshBus.onProfileRefresh.listen((_) {
      if (!mounted) return;
      _onCompanyRefresh();
    });
  }

  @override
  void dispose() {
    _companySub.cancel();
    _profileSub?.cancel();
    super.dispose();
  }

  void _onCompanyRefresh() {
    _isFreshFetch = true;
    reloadPickingList();
  }

  Future<void> initializeAndFetch() async {
    await _service.initializeOdooClient();
    await _fetchData();
  }

  // ───────────────────────────────────────────────
  //  Data Loading & Refresh
  // ───────────────────────────────────────────────

  /// Main data fetch method — calls service with current filters/search
  Future<void> _fetchData() async {
    setState(() => isLoading = true);
    try {
      await _service.fetchData(
        scheduledDate: selectedScheduleDate,
        deadlineDate: selectedDeadlineDate,
        state: selectedStateValue,
        type: selectedType,
        searchTerm: _searchTerm,
        filters: _selectedFilters,
        forceRefresh: _isFreshFetch,
      );
      _isFreshFetch = false;
      final allPickings = _service.allPickingsByLocation.values
          .expand((e) => e)
          .toList();

      _buildGroupedPickings(allPickings);
      if (mounted) {
        setState(() => isLoading = false);
      }
    } on OdooSessionExpiredException {
      if (mounted) {
        CompanySessionManager.logout(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          catchError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  /// Rebuilds grouped data structure when grouping is active
  void _buildGroupedPickings(List<Map<String, dynamic>> allPickings) {
    _groupedPickings.clear();

    if (_selectedGroupBy == null || _selectedGroupBy!.isEmpty) {
      return;
    }

    for (final picking in allPickings) {
      final groupKey = picking[_selectedGroupBy] ?? "Unknown";

      final groupName = groupKey.toString().isEmpty
          ? "Unknown"
          : groupKey.toString();

      if (!_groupedPickings.containsKey(groupName)) {
        _groupedPickings[groupName] = [];
        _groupExpanded[groupName] = true;
      }

      _groupedPickings[groupName]!.add(picking);
    }
  }

  /// Full reset & reload — called on pull-to-refresh, company change, clear filters
  Future<void> reloadPickingList() async {
    _searchController.clear();
    _searchTerm = '';
    selectedScheduleDate = null;
    selectedDeadlineDate = null;
    selectedStateLabel = null;
    selectedStateValue = null;
    selectedType = 'outgoing';
    isFilterApplied = false;
    _service.clearPaginationState();
    await _fetchData();
  }

  // ───────────────────────────────────────────────
  //  UI Helpers
  // ───────────────────────────────────────────────

  Color getStateColor(String? state) {
    switch (state) {
      case 'draft':
        return Colors.grey;
      case 'confirmed':
        return Colors.orange;
      case 'assigned':
        return Colors.blue;
      case 'done':
        return Colors.green;
      case 'cancel':
        return Colors.red;
      default:
        return Colors.black;
    }
  }

  String capitalizeFirstLetter(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  Map<String, dynamic> getFormattedDateInfo(String dateStr) {
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
          'color': Colors.red,
        };
      }
    } catch (_) {
      return {'label': dateStr, 'color': Colors.grey};
    }
  }

  // ───────────────────────────────────────────────
  //  Pagination per location
  // ───────────────────────────────────────────────

  Future<void> _loadNextPage(String location) async {
    final nextPage = (_service.currentPage[location] ?? 0) + 1;
    await _fetchPageForLocation(location, nextPage);
  }

  Future<void> _loadPrevPage(String location) async {
    final prevPage = (_service.currentPage[location] ?? 0) - 1;
    if (prevPage >= 0) {
      await _fetchPageForLocation(location, prevPage);
    }
  }

  Future<void> _fetchPageForLocation(String location, int page) async {
    if (_isFetchingMore.contains(location)) return;

    _isFetchingMore.add(location);
    setState(() => isPageLoading = true);

    try {
      await _service.fetchData(pageOverrides: {location: page});

      _service.currentPage[location] = page;
      final newPickings = _service.allPickingsByLocation[location] ?? [];
      _service.previousPickingsByLocation[location] = newPickings;
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
    } finally {
      _isFetchingMore.remove(location);
      if (mounted) {
        setState(() => isPageLoading = false);
      }
    }
  }

  // ───────────────────────────────────────────────
  //  Filter & Group Bottom Sheet
  // ───────────────────────────────────────────────

  /// Opens bottom sheet to select filters and grouping options
  void openFilterGroupBySheet(BuildContext context) {
    List<String> tempFilters = [];
    String? tempGroupBy;
    tempFilters = List.from(_selectedFilters);
    tempGroupBy = _selectedGroupBy;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final groupMap = groupTechnicalNames;

          return Container(
            height: MediaQuery.of(context).size.height * 0.8,
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
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(
                            Icons.close,
                            color: isDark ? Colors.white : Colors.black54,
                          ),
                          splashRadius: 20,
                        ),
                      ],
                    ),
                  ),

                  // Tabs (Filter / Group By)
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

                  // Bottom action bar
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
                                selectedStateValue = null;
                                selectedType = '';
                                selectedScheduleDate = null;
                                selectedDeadlineDate = null;
                                _selectedFilters.clear();
                                _selectedGroupBy = null;
                                isFilterApplied = false;
                              });

                              Navigator.pop(context);
                              _service.clearPaginationState();
                              _fetchData();
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
                                isFilterApplied =
                                    tempFilters.isNotEmpty ||
                                    tempGroupBy != null;
                              });

                              Navigator.pop(context);
                              _service.clearPaginationState();
                              _fetchData();
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
        color: isDark ? Colors.white.withOpacity(0.9) : Colors.black,
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

  Widget _buildEmptyState(bool isDark, bool hasFilters, BuildContext context) {
    return EmptyState(
      title: 'No Pickings Found',
      subtitle: hasFilters ? 'Try adjusting your filters or search term' : 'There are no picking items available.',
      lottieAsset: 'assets/lotties/no_data.json',
      actionLabel: hasFilters ? 'Clear All Filters' : null,
      onAction: hasFilters ? () {
        setState(() {
          selectedStateValue = null;
          selectedType = '';
          selectedScheduleDate = null;
          selectedDeadlineDate = null;
          _selectedFilters.clear();
          _selectedGroupBy = null;
          _searchTerm = '';
          _searchController.clear();
          isFilterApplied = false;
        });
        _service.clearPaginationState();
        _fetchData();
      } : null,
    );
  }

  Widget _buildErrorState(bool isDark, BuildContext context) {
    return ErrorStateWidget(
      title: 'Something went wrong',
      message: 'Unable to load pickings. Please check your connection or try again.',
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
    final bool hasFilters = _selectedFilters.isNotEmpty ||
        _searchTerm.isNotEmpty ||
        selectedScheduleDate != null ||
        selectedDeadlineDate != null ||
        selectedStateValue != null;
    final int activeFilterCount = _selectedFilters.length +
        (_searchTerm.isNotEmpty ? 1 : 0) +
        (selectedScheduleDate != null ? 1 : 0) +
        (selectedDeadlineDate != null ? 1 : 0) +
        (selectedStateValue != null ? 1 : 0);

    // Filter locations based on current search term
    final filteredLocations = _service.allPickingsByLocation.entries
        .map((entry) {
          final location = entry.key;
          final pickings = entry.value.where((picking) {
            final item = picking['item']?.toLowerCase() ?? '';
            final searchTerm = _searchTerm.toLowerCase();
            return item.contains(searchTerm) ||
                location.toLowerCase().contains(searchTerm);
          }).toList();
          return MapEntry(location, pickings);
        })
        .where((entry) => entry.value.isNotEmpty)
        .toList();

    final motionProvider = Provider.of<MotionProvider>(context, listen: false);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50], // Match mobo_inv_app
      body: Column(
        children: [
          // Search Bar
          ListSearchBar(
            controller: _searchController,
            hintText: 'Search by location or item...',
            hasActiveFilters: hasFilters || hasGroupBy,
            onFilterTap: () => openFilterGroupBySheet(context),
            onChanged: (value) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 400), () {
                setState(() {
                  _searchTerm = value;
                  _service.clearPaginationState();
                });
                _fetchData();
              });
            },
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _buildFilterIndicator(isDark, activeFilterCount),
                  ],
                ),
                // Pagination for Flat List (if no grouping)
                if (_selectedGroupBy == null)
                  Consumer<CompanyProvider>(
                      builder: (context, companyProvider, _) {
                    // Collect global stats
                    final totalGlobalCount = _service.totalPickingsCount.values
                        .fold(0, (sum, count) => sum + count);
                    
                    // For simplified global pagination, we use the first warehouse's page
                    // since the service currently fetches all warehouses per "page" request.
                    final firstLoc = _service.allPickingsByLocation.keys.isNotEmpty 
                        ? _service.allPickingsByLocation.keys.first 
                        : null;
                    final currentPage = firstLoc != null ? (_service.currentPage[firstLoc] ?? 0) : 0;
                    final hasNext = _service.hasNextPage.values.any((val) => val == true);
                    
                    final start = currentPage * _service.pageSize + 1;
                    final end = (start + _service.pageSize - 1).clamp(0, totalGlobalCount);
                    final rangeText = totalGlobalCount > 0 ? '$start-$end/$totalGlobalCount' : '0/0';

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Range Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[800] : Colors.grey[100],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            rangeText,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.grey[300] : Colors.grey[700],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Back Arrow
                        _buildPaginationArrow(
                          icon: HugeIcons.strokeRoundedArrowLeft01,
                          onPressed: currentPage > 0 
                            ? () => _loadPrevPage(firstLoc!) 
                            : null,
                          isDark: isDark,
                          enabled: currentPage > 0,
                        ),
                        
                        // Next Arrow
                        _buildPaginationArrow(
                          icon: HugeIcons.strokeRoundedArrowRight01,
                          onPressed: hasNext 
                            ? () => _loadNextPage(firstLoc!) 
                            : null,
                          isDark: isDark,
                          enabled: hasNext,
                        ),
                      ],
                    );
                  }),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                if (isLoading)
                  ListShimmer.buildListShimmer(context, itemCount: 6)
                else if (catchError)
                  Positioned.fill(
                    child: _buildErrorState(isDark, context),
                  )
                else if (filteredLocations.isEmpty)
                  Positioned.fill(
                    child: _buildEmptyState(isDark, hasFilters, context),
                  )
                else if (_selectedGroupBy != null &&
                    _selectedGroupBy!.isNotEmpty &&
                    _groupedPickings.isNotEmpty)
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_groupedPickings.length} groups',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Row(
                              children: [
                                if (!_allGroupsExpanded && _groupedPickings.isNotEmpty)
                                  TextButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        for (final key in _groupedPickings.keys) {
                                          _groupExpanded[key] = true;
                                        }
                                        _allGroupsExpanded = true;
                                      });
                                    },
                                    icon: const Icon(Icons.expand_more, size: 18),
                                    label: const Text('Expand All'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                if (_groupExpanded.values.any((expanded) => expanded))
                                  TextButton.icon(
                                    onPressed: () {
                                      setState(() {
                                        for (final key in _groupedPickings.keys) {
                                          _groupExpanded[key] = false;
                                        }
                                        _allGroupsExpanded = false;
                                      });
                                    },
                                    icon: const Icon(Icons.expand_less, size: 18),
                                    label: const Text('Collapse All'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () async => reloadPickingList(),
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: _groupedPickings.length,
                            itemBuilder: (context, index) {
                              final groupName = _groupedPickings.keys.elementAt(
                                index,
                              );
                              final groupPickings = _groupedPickings[groupName]!;
                              final isExpanded = _groupExpanded[groupName] ?? true;

                              return Container(
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
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
                                margin: const EdgeInsets.only(bottom: 24),
                                child: Column(
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          _groupExpanded[groupName] = !isExpanded;
                                        });
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    _selectedGroupBy == 'state'
                                                        ? capitalizeFirstLetter(
                                                            groupName,
                                                          )
                                                        : groupName,
                                                    style: TextStyle(
                                                      color: isDark
                                                          ? Colors.white
                                                          : Colors.black87,
                                                      fontWeight: FontWeight.w600,
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '${groupPickings.length} Pickings',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: isDark
                                                          ? Colors.grey[400]
                                                          : Colors.grey[700],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Icon(
                                              isExpanded
                                                  ? Icons.keyboard_arrow_up
                                                  : Icons.keyboard_arrow_down,
                                              color: isDark
                                                  ? Colors.white70
                                                  : Colors.black54,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    if (isExpanded)
                                      ...groupPickings.map(
                                        (picking) => Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          child: _buildPickingCard(picking, isDark),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  RefreshIndicator(
                    onRefresh: () async => reloadPickingList(),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredLocations.expand((e) => e.value).length,
                      itemBuilder: (context, index) {
                        final allPickings = filteredLocations.expand((e) => e.value).toList();
                        final picking = allPickings[index];
                        return _buildPickingCard(picking, isDark);
                      },
                    ),
                  ),

                if (isPageLoading)
                  const LoadingOverlay(
                    message: 'Loading more...',
                    isFullPage: false,
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  CreatePickingPage(url: _service.url),
              transitionDuration: motionProvider.reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              reverseTransitionDuration: motionProvider.reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, _, child) {
                if (motionProvider.reduceMotion) return child;
                return FadeTransition(opacity: animation, child: child);
              },
            ),
          ).then((_) => reloadPickingList());
        },
        backgroundColor: AppStyle.primaryColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: const HugeIcon(
          icon: HugeIcons.strokeRoundedFileAdd,
          size: 30,
          color: Colors.white,
        ),
        tooltip: 'Add Pickings by Location',
      ),
    );
  }

  /// Builds individual picking card used in list/grouped view
  Widget _buildPickingCard(Map<String, dynamic> picking, bool isDark) {
    final reference = picking['item'] ?? '';
    final state = picking['state'] ?? '';
    final origin = picking['origin']?.toString() ?? 'false';
    final partner = picking['partner_id'] ?? '';
    final scheduled = picking['scheduled_date'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: const Color(0xFF000000).withOpacity(0.06),
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
          onTap: () {
            final odooPickingFormService = OdooPickingFormService();
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, _) => PickingDetailsPage(
                  picking: picking,
                  odooService: odooPickingFormService,
                  isPickingForm: true,
                  isReturnPicking: false,
                  isReturnCreate: false,
                ),
                transitionsBuilder: (context, animation, _, child) =>
                    FadeTransition(opacity: animation, child: child),
              ),
            ).then((_) => reloadPickingList());
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Reference & Status Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        reference,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : AppStyle.primaryColor,
                          letterSpacing: -0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _buildStatusBadge(state, isDark),
                  ],
                ),
                const SizedBox(height: 8),
                
                // Details
                _buildCardDetailRow('Origin:', origin, isDark),
                const SizedBox(height: 4),
                _buildCardDetailRow('Partner:', partner, isDark),
                const SizedBox(height: 4),
                Row(
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedCalendar03,
                      size: 14,
                      color: isDark ? (Colors.grey[100] ?? Colors.white) : const Color(0xffC5C5C5),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Scheduled: $scheduled',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
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

  Widget _buildCardDetailRow(String label, String value, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 85,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[500] : Colors.grey[500],
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value == 'false' ? 'false' : value,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String state, bool isDark) {
    Color bgColor;
    Color textColor;
    String label = capitalizeFirstLetter(stateMap[state] ?? state);

    switch (state) {
      case 'done':
        bgColor = Colors.green.withOpacity(0.1);
        textColor = Colors.green;
        break;
      case 'assigned':
        bgColor = Colors.blue.withOpacity(0.1);
        textColor = Colors.blue;
        break;
      case 'waiting':
      case 'confirmed':
        bgColor = Colors.orange.withOpacity(0.1);
        textColor = Colors.orange;
        break;
      case 'cancel':
        bgColor = Colors.red.withOpacity(0.1);
        textColor = Colors.red;
        break;
      default:
        bgColor = Colors.grey.withOpacity(0.1);
        textColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Helper to build consistent pagination arrows (Matching mobo_sales style)
  Widget _buildPaginationArrow({
    required IconData icon,
    required VoidCallback? onPressed,
    required bool isDark,
    required bool enabled,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.0),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8.0),
          child: HugeIcon(
            icon: icon,
            size: 20,
            color: enabled
                ? (isDark ? Colors.white : Colors.black87)
                : (isDark ? Colors.grey[600]! : Colors.grey[400]!),
          ),
        ),
      ),
    );
  }
}
