import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../Dashboard/infrastructure/profile_refresh_bus.dart';
import '../../../../core/company/infrastructure/company_refresh_bus.dart';
import '../../../../core/company/providers/company_provider.dart';
import '../../../../core/providers/motion_provider.dart';
import '../../../../shared/utils/globals.dart';
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

  // Filter & Group options
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
  final Map<String, ScrollController> _locationScrollControllers = {};
  final Set<String> _isFetchingMore = {};
  int initialCount = 0;

  // ───────────────────────────────────────────────
  //  Lifecycle & Subscriptions
  // ───────────────────────────────────────────────
  late final StreamSubscription _companySub;

  List<String> _selectedFilters = [];
  String? _selectedGroupBy;
  Map<String, List<Map<String, dynamic>>> _groupedPickings = {};
  Map<String, bool> _groupExpanded = {};
  bool hasFilters = false;
  bool hasGroupBy = false;
  Timer? _searchDebounce;
  bool catchError = false;

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
  }

  @override
  void dispose() {
    _companySub.cancel();
    super.dispose();
  }

  void _onCompanyRefresh() {
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
      );
      final allPickings = _service.allPickingsByLocation.values
          .expand((e) => e)
          .toList();

      _buildGroupedPickings(allPickings);
      if (mounted) {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() {
        catchError = true;
      });
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

  /// Returns label & color for scheduled date relative to today
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
      setState(() {});
    } catch (e) {
    } finally {
      _isFetchingMore.remove(location);
      setState(() => isPageLoading = false);
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
                  selectedStateValue = null;
                  selectedType = '';
                  selectedScheduleDate = null;
                  selectedDeadlineDate = null;
                  _selectedFilters.clear();
                  _selectedGroupBy = null;
                  isFilterApplied = false;
                });

                _service.clearPaginationState();
                _fetchData();
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
  //  Build Method
  // ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {

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
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
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
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        hintText: 'Search by Location and Item',
                        hintStyle: TextStyle(
                          color: isDark
                              ? Colors.white
                              : const Color(0xff1E1E1E),
                          fontWeight: FontWeight.w400,
                          fontSize: 15,
                        ),
                        prefixIcon: IconButton(
                          icon: Icon(
                            HugeIcons.strokeRoundedFilterHorizontal,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            size: 18,
                          ),
                          tooltip: 'Filter & Group By',
                          onPressed: () {
                            openFilterGroupBySheet(context);
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppStyle.primaryColor),
                        ),
                      ),
                      onChanged: (value) {
                        _searchDebounce?.cancel();
                        _searchDebounce = Timer(
                          const Duration(milliseconds: 400),
                          () {
                            setState(() {
                              _searchTerm = value;
                              _service.clearPaginationState();
                            });
                            _fetchData();
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Builder(
                builder: (context) {
                  hasFilters = _selectedFilters.isNotEmpty;
                  hasGroupBy = (_selectedGroupBy?.isNotEmpty ?? false);

                  if (!hasFilters && !hasGroupBy) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        "No filters applied",
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : Colors.black54,
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

                    groupDisplayName = groupMap.keys.firstWhere(
                      (key) => groupMap[key] == _selectedGroupBy,
                      orElse: () => _selectedGroupBy!.replaceAll('_', ' '),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasFilters)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white70 : Colors.black,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _selectedFilters.length.toString(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.black : Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  "Active",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.black : Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (hasGroupBy) ...[
                          if (hasFilters) const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white70 : Colors.black,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  HugeIcons.strokeRoundedLayer,
                                  size: 16,
                                  color: isDark ? Colors.black : Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  groupDisplayName ?? "Group",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.black : Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
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
            ],
          ),
          SizedBox(height: 10),
          Expanded(
            child: Stack(
              children: [
                if (isLoading)
                  ListView.builder(
                    itemCount: 8,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Shimmer.fromColors(
                        baseColor: isDark
                            ? const Color(0xFF2A2A2A)
                            : Colors.grey[300]!,
                        highlightColor: Colors.grey.shade100,
                        period: const Duration(seconds: 3),
                        child: Container(
                          height: 80,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF2A2A2A)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  )
                else if (catchError)
                  Expanded(
                    child: Center(child: _buildErrorState(isDark, context)),
                  )
                else if (filteredLocations.isEmpty)
                  Expanded(
                    child: Center(
                      child: _buildEmptyState(isDark, hasFilters, context),
                    ),
                  )
                else if (_selectedGroupBy != null &&
                    _selectedGroupBy!.isNotEmpty &&
                    _groupedPickings.isNotEmpty)
                  RefreshIndicator(
                    onRefresh: () async => reloadPickingList(),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: _groupedPickings.length,
                      itemBuilder: (context, index) {
                        final groupName = _groupedPickings.keys.elementAt(
                          index,
                        );
                        final groupPickings = _groupedPickings[groupName]!;
                        final isExpanded = _groupExpanded[groupName] ?? true;

                        return Container(
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
                  )
                else
                  RefreshIndicator(
                    onRefresh: () async => reloadPickingList(),
                    child: ListView.builder(
                      itemCount: filteredLocations.length,
                      itemBuilder: (context, index) {
                        final location = filteredLocations[index].key;
                        final pickings = filteredLocations[index].value;
                        initialCount = pickings.length;
                        final currentPage = _service.currentPage[location] ?? 0;
                        final totalCount =
                            _service.totalPickingsCount[location] ??
                            pickings.length;
                        final hasNext = _service.hasNextPage[location] == true;

                        return Card(
                          elevation: 3,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          color: isDark ? Colors.grey[800] : Colors.grey[50],
                          child: Theme(
                            data: Theme.of(
                              context,
                            ).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              iconColor: isDark
                                  ? Colors.white
                                  : AppStyle.primaryColor,
                              collapsedIconColor: isDark
                                  ? Colors.white
                                  : AppStyle.primaryColor,
                              title: Text(
                                location,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? Colors.white
                                      : AppStyle.primaryColor,
                                  fontSize: 16,
                                ),
                              ),
                              children: [
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
                                            _service.pageRangeForLocation(
                                              location,
                                            ),
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
                                            '$totalCount',
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
                                      icon: Icon(
                                        HugeIcons.strokeRoundedArrowLeft01,
                                        size: 22,
                                        color: currentPage > 0
                                            ? (isDark
                                                  ? Colors.white
                                                  : Colors.black87)
                                            : Colors.grey,
                                      ),
                                      onPressed: currentPage > 0
                                          ? () => _loadPrevPage(location)
                                          : null,
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        HugeIcons.strokeRoundedArrowRight01,
                                        size: 22,
                                        color: hasNext
                                            ? (isDark
                                                  ? Colors.white
                                                  : Colors.black87)
                                            : Colors.grey,
                                      ),
                                      onPressed: hasNext
                                          ? () => _loadNextPage(location)
                                          : null,
                                    ),
                                  ],
                                ),
                                SizedBox(height: 10,),
                                SizedBox(
                                  height: 600,
                                  child: ListView.builder(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    controller: _locationScrollControllers
                                        .putIfAbsent(
                                          location,
                                          () => ScrollController(),
                                        ),
                                    itemCount: pickings.length,
                                    itemBuilder: (context, index) {
                                      final picking = pickings[index];
                                      final dateInfo = getFormattedDateInfo(
                                        picking['scheduled_date'] ?? '',
                                      );
                                      final label = dateInfo['label'];

                                      return Padding(
                                        padding:  const EdgeInsets.symmetric(
                                            horizontal: 16.0),
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          margin: const EdgeInsets.only(bottom: 12),
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
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 4,
                                                ),
                                            title: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  picking['item'] ?? '',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                    color: isDark
                                                        ? Colors.white
                                                        : AppStyle.primaryColor,
                                                  ),
                                                ),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: getStateColor(
                                                      picking['state'],
                                                    ).withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    capitalizeFirstLetter(
                                                      stateMap[picking['state']] ??
                                                          'Unknown',
                                                    ),
                                                    style: TextStyle(
                                                      color: getStateColor(
                                                        picking['state'],
                                                      ),
                                                      fontWeight: FontWeight.w600,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (picking['partner_id'] !=
                                                    '') ...[
                                                  Text(
                                                    "Delivery Address: ${picking['partner_id']}",
                                                    style: TextStyle(
                                                      color: isDark
                                                          ? Colors.white60
                                                          : Colors.black54,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                ],
                                                Text(
                                                  "Scheduled: $label",
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? Colors.white60
                                                        : Colors.black54,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            onTap: () {
                                              final odooPickingFormService =
                                                  OdooPickingFormService();
                                              Navigator.push(
                                                context,
                                                PageRouteBuilder(
                                                  pageBuilder:
                                                      (
                                                        context,
                                                        animation,
                                                        _,
                                                      ) => PickingDetailsPage(
                                                        picking: picking,
                                                        odooService:
                                                            odooPickingFormService,
                                                        isPickingForm: true,
                                                        isReturnPicking: false,
                                                        isReturnCreate: false,
                                                      ),
                                                  transitionsBuilder:
                                                      (
                                                        context,
                                                        animation,
                                                        _,
                                                        child,
                                                      ) => FadeTransition(
                                                        opacity: animation,
                                                        child: child,
                                                      ),
                                                ),
                                              ).then((_) => reloadPickingList());
                                            },
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                if (isPageLoading)
                  Container(
                    child: Center(
                      child: LoadingAnimationWidget.staggeredDotsWave(
                        color: AppStyle.primaryColor,
                        size: 50,
                      ),
                    ),
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
        backgroundColor: isDark ? Colors.white : AppStyle.primaryColor,
        child: Icon(
          HugeIcons.strokeRoundedAdd01,
          size: 25,
          color: isDark ? Colors.black : Colors.white,
        ),
        tooltip: 'Add Pickings by Location',
      ),
    );
  }

  /// Builds individual picking card used in grouped view
  Widget _buildPickingCard(Map<String, dynamic> picking, bool isDark) {
    final dateInfo = getFormattedDateInfo(picking['scheduled_date'] ?? '');
    final label = dateInfo['label'];

    return Container(
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
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ListTile(
          title: Text(picking['item'] ?? ''),
          subtitle: Text("Scheduled: $label"),
          onTap: () {
            final odooPickingFormService = OdooPickingFormService();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PickingDetailsPage(
                  picking: picking,
                  odooService: odooPickingFormService,
                  isPickingForm: true,
                  isReturnPicking: false,
                  isReturnCreate: false,
                ),
              ),
            ).then((_) => reloadPickingList());
          },
        ),
      ),
    );
  }
}
