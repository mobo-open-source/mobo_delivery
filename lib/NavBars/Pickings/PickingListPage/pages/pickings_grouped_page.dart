import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:provider/provider.dart';
import '../../../../core/company/session/company_session_manager.dart';
import '../../../../Dashboard/screens/dashboard/bloc/dashboard_bloc.dart';
import '../../../../Dashboard/screens/dashboard/bloc/dashboard_state.dart';
import '../../../../Dashboard/infrastructure/profile_refresh_bus.dart';
import '../../../../core/company/infrastructure/company_refresh_bus.dart';
import '../services/pickings_filter_bus.dart';
import '../../../../core/company/providers/company_provider.dart';
import '../../../../shared/utils/globals.dart';
import '../../../../shared/utils/odoo_datetime_format.dart';
import '../../../../shared/widgets/buttons/mobo_button.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/list_search_bar.dart';
import '../../../../shared/widgets/error_state_widget.dart';
import '../../../../shared/widgets/loaders/delivery_shimmers.dart';
import '../../../../shared/widgets/loading_overlay.dart';
import '../../../../shared/widgets/snackbar.dart';
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
  final TextEditingController _searchController = TextEditingController();
  final PickingService _service = PickingService();

  String? selectedStateLabel;
  String? selectedStateValue;
  DateTime? selectedScheduleDate;
  DateTime? selectedDeadlineDate;
  String selectedType = 'outgoing';
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

  StreamSubscription? _profileSub;
  late final StreamSubscription _companySub;
  StreamSubscription<String?>? _homeFilterSub;

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

    _companySub = CompanyRefreshBus.stream.listen((_) async {
      if (!mounted) return;
      _onCompanyRefresh();
    });

    _profileSub = ProfileRefreshBus.onProfileRefresh.listen((_) {
      if (!mounted) return;
      _onCompanyRefresh();
    });

    _homeFilterSub = PickingsFilterBus.stream.listen((chip) async {
      if (!mounted) return;
      setState(() {
        _selectedFilters = chip == null ? <String>[] : [chip];
        _selectedGroupBy = null;
        isFilterApplied = _selectedFilters.isNotEmpty;
        _service.clearPaginationState();
      });
      await _fetchData();
    });
  }

  @override
  void dispose() {
    _companySub.cancel();
    _profileSub?.cancel();
    _homeFilterSub?.cancel();
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

  /// Main data fetch method — calls service with current filters/search.
  ///
  /// Bounded by a 15-second timeout so the shimmer can't sit forever on a
  /// slow or hung Odoo response. On failure: if a list is already loaded
  /// the user keeps seeing it and gets a snackbar (transient error). Only
  /// when there is nothing to fall back to do we replace the page with
  /// the retryable error widget.
  Future<void> _fetchData() async {
    final hadDataBefore =
        _service.allPickingsByLocation.values.any((list) => list.isNotEmpty);
    setState(() {
      isLoading = true;
      catchError = false;
    });
    try {
      await _service.fetchData(
        scheduledDate: selectedScheduleDate,
        deadlineDate: selectedDeadlineDate,
        state: selectedStateValue,
        type: selectedType,
        searchTerm: _searchTerm,
        filters: _selectedFilters,
        forceRefresh: _isFreshFetch,
      ).timeout(const Duration(seconds: 15));
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
    } on TimeoutException {
      if (mounted) {
        if (hadDataBefore) {
          CustomSnackbar.showError(
            context,
            'Refresh took too long. Showing previous results.',
          );
        } else {
          setState(() => catchError = true);
        }
      }
    } catch (_) {
      if (mounted) {
        if (hadDataBefore) {
          CustomSnackbar.showError(
            context,
            'Could not refresh pickings. Showing previous results.',
          );
        } else {
          setState(() => catchError = true);
        }
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

  Future<void> _loadNextPage(String location) async {

    final pageSize = _service.pageSize;
    final totalGlobal = _service.totalPickingsCount.values
        .fold<int>(0, (a, b) => a + b);
    final maxPage = totalGlobal > 0 ? ((totalGlobal - 1) ~/ pageSize) : 0;
    final currentPage = _service.currentPage[location] ?? 0;
    if (currentPage >= maxPage) return;
    await _fetchPageForAllLocations(currentPage + 1);
  }

  Future<void> _loadPrevPage(String location) async {
    final prevPage = (_service.currentPage[location] ?? 0) - 1;
    if (prevPage >= 0) {
      await _fetchPageForAllLocations(prevPage);
    }
  }

  Future<void> _fetchPageForAllLocations(int page) async {
    if (_isFetchingMore.isNotEmpty) return;

    final overrides = <String, int>{};
    for (final loc in _service.totalPickingsCount.keys) {
      overrides[loc] = page;
      _isFetchingMore.add(loc);
    }
    if (overrides.isEmpty) return;
    setState(() => isPageLoading = true);

    try {

      await _service.fetchData(
        scheduledDate: selectedScheduleDate,
        deadlineDate: selectedDeadlineDate,
        state: selectedStateValue,
        type: selectedType,
        searchTerm: _searchTerm,
        filters: _selectedFilters,
        pageOverrides: overrides,
      );
      for (final loc in overrides.keys) {
        _service.currentPage[loc] = page;
        final newPickings = _service.allPickingsByLocation[loc] ?? [];
        _service.previousPickingsByLocation[loc] = newPickings;
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
    } finally {
      _isFetchingMore.clear();
      if (mounted) {
        setState(() => isPageLoading = false);
      }
    }
  }

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
                        color: isDark ? const Color(0xFF2A2A2A) : AppStyle.primaryColor,
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
                                    color: AppStyle.primaryColor,
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
                                selectedColor: AppStyle.primaryColor,
                                backgroundColor: isDark
                                    ? Colors.white.withOpacity(0.08)
                                    : AppStyle.primaryColor.withOpacity(0.08),
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
                                'Group pickings by',
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
                                selectedStateValue = null;
                                selectedType = 'outgoing';
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
                                isFilterApplied =
                                    tempFilters.isNotEmpty ||
                                    tempGroupBy != null;
                              });

                              Navigator.pop(context);
                              _service.clearPaginationState();
                              _fetchData();
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
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 8, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: AppStyle.primaryColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppStyle.primaryColor.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppStyle.primaryColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              HugeIcons.strokeRoundedCancel01,
              size: 16,
              color: AppStyle.primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  /// A single "Group By" radio option (title + description), matching the
  /// quotation group-by list in the mobo sales app.
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
              activeColor: AppStyle.primaryColor,
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

  Widget _buildEmptyState(bool isDark, bool hasFilters, BuildContext context) {

    final hasSearch = _searchTerm.isNotEmpty;
    final hasActiveFilters = _selectedFilters.isNotEmpty ||
        _selectedGroupBy != null ||
        selectedStateValue != null ||
        selectedScheduleDate != null ||
        selectedDeadlineDate != null;
    final bool searchOnly = hasSearch && !hasActiveFilters;

    String title;
    String subtitle;
    String? actionLabel;
    VoidCallback? onAction;

    if (searchOnly) {
      title = 'No results for "$_searchTerm"';
      subtitle = 'Try a different search term.';
      actionLabel = 'Clear Search';
      onAction = () {
        setState(() {
          _searchTerm = '';
          _searchController.clear();
        });
        _service.clearPaginationState();
        _fetchData();
      };
    } else if (hasActiveFilters) {
      title = 'No Pickings Found';
      subtitle = 'Try adjusting your filters or search term.';
      actionLabel = 'Clear All Filters';
      onAction = () {
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
      };
    } else {
      title = 'No Pickings Found';
      subtitle = 'There are no picking items available.';
    }

    return EmptyState(
      title: title,
      subtitle: subtitle,
      lottieAsset: 'assets/lotties/empty_ghost.json',
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// Combined "Expand/Collapse All (N groups)" pill that replaces the old
  /// two-row layout. Consolidated into the filter-indicator row when a
  /// group-by is active — the count lives inside the button label so the
  /// list gains a whole line of vertical space.
  Widget _buildGroupToggle(bool isDark) {
    final count = _groupedPickings.length;

    final expanded = _groupedPickings.keys
        .every((k) => _groupExpanded[k] ?? true);
    return TextButton.icon(
      onPressed: () {
        setState(() {
          final target = !expanded;
          for (final key in _groupedPickings.keys) {
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
        '${expanded ? 'Collapse' : 'Expand'} All ($count)',
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => const [],
        body: Column(
        children: [
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

          if (isLoading || isPageLoading)
            const PaginationBarShimmer()
          else if (!catchError && filteredLocations.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _buildFilterIndicator(isDark, activeFilterCount),
                  ],
                ),
                if (_selectedGroupBy != null &&
                    _groupedPickings.isNotEmpty)
                  _buildGroupToggle(isDark)
                else if (_selectedGroupBy == null)
                  Consumer<CompanyProvider>(
                      builder: (context, companyProvider, _) {

                    final liveGlobal = _service.globalPickingCount;
                    final livePerWh = _service.totalPickingsCount.values
                        .fold<int>(0, (sum, count) => sum + count);
                    final totalGlobalCount =
                        liveGlobal > 0 ? liveGlobal : livePerWh;
                    final pageSize = _service.pageSize;

                    final firstLoc = _service.allPickingsByLocation.keys.isNotEmpty
                        ? _service.allPickingsByLocation.keys.first
                        : null;
                    final rawCurrentPage = firstLoc != null
                        ? (_service.currentPage[firstLoc] ?? 0)
                        : 0;

                    final maxPage = totalGlobalCount > 0
                        ? ((totalGlobalCount - 1) ~/ pageSize)
                        : 0;
                    final currentPage = rawCurrentPage.clamp(0, maxPage);
                    final hasNext = currentPage < maxPage;

                    final start = totalGlobalCount == 0
                        ? 0
                        : currentPage * pageSize + 1;
                    final end = ((currentPage + 1) * pageSize)
                        .clamp(0, totalGlobalCount);
                    final rangeText = totalGlobalCount > 0
                        ? '$start-$end/$totalGlobalCount'
                        : '0/0';

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color:
                                  isDark ? Colors.white24 : Colors.grey.shade300,
                            ),
                          ),
                          child: Text(
                            rangeText,
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        if (firstLoc != null && maxPage > 0) ...[
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              HugeIcons.strokeRoundedArrowLeft01,
                              size: 25,
                              color: currentPage > 0
                                  ? (isDark ? Colors.white70 : Colors.black87)
                                  : (isDark ? Colors.grey[800] : Colors.grey.withValues(alpha: 0.4)),
                            ),
                            onPressed: currentPage > 0 ? () => _loadPrevPage(firstLoc) : null,
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              HugeIcons.strokeRoundedArrowRight01,
                              size: 25,
                              color: hasNext
                                  ? (isDark ? Colors.white70 : Colors.black87)
                                  : (isDark ? Colors.grey[800] : Colors.grey.withValues(alpha: 0.4)),
                            ),
                            onPressed: hasNext ? () => _loadNextPage(firstLoc) : null,
                          ),
                        ],
                      ],
                    );
                  }),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                if (isLoading || isPageLoading)
                  const PickingListShimmer(itemCount: 6)
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
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () async => reloadPickingList(),
                          child: ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
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
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  children: [
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          _groupExpanded[groupName] = !isExpanded;
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(12),
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
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '${groupPickings.length} Pickings',
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
                                              isExpanded
                                                  ? HugeIcons.strokeRoundedArrowUp01
                                                  : HugeIcons.strokeRoundedArrowDown01,
                                              color: isDark
                                                  ? Colors.white70
                                                  : Colors.black54,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    if (isExpanded) ...[
                                      const SizedBox(height: 4),
                                      ...groupPickings.map(
                                        (picking) => Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          child: _buildPickingCard(
                                            picking,
                                            isDark,
                                            insideGroup: true,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
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
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: filteredLocations.expand((e) => e.value).length,
                      itemBuilder: (context, index) {
                        final allPickings = filteredLocations.expand((e) => e.value).toList();
                        final picking = allPickings[index];
                        return _buildPickingCard(picking, isDark);
                      },
                    ),
                  ),

              ],
            ),
          ),
        ],
      ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'pickingsCreateFab',
        onPressed: () {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  CreatePickingPage(url: _service.url),
              transitionDuration: const Duration(milliseconds: 300),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder: (context, animation, _, child) {
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
  Widget _buildPickingCard(
    Map<String, dynamic> picking,
    bool isDark, {
    bool insideGroup = false,
  }) {
    final reference = cleanOdooValue(picking['item']);
    final state = picking['state'] ?? '';
    final origin = cleanOdooValue(picking['origin']);
    final partner = cleanOdooValue(picking['partner_id']);
    final rawScheduled = picking['scheduled_date'];
    final scheduled = (rawScheduled is String && rawScheduled.isNotEmpty)
        ? OdooDateTimeFormat.formatForDisplay(rawScheduled)
        : cleanOdooValue(rawScheduled);

    return Container(
      margin: EdgeInsets.only(bottom: insideGroup ? 0 : 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),

        border: insideGroup
            ? Border.all(
                color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
                width: 0.8,
              )
            : null,

        boxShadow: insideGroup
            ? const []
            : [
                BoxShadow(
                  color: const Color(0xFF000000).withOpacity(0.05),
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
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            cleanOdooValue(value),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String state, bool isDark) {
    const Color statusGreen  = Color(0xFF00A63E);
    const Color statusBlue   = Color(0xFF3B82F6);
    const Color statusOrange = Color(0xFFF97316);
    const Color statusRed    = Color(0xFFEF4444);
    const Color statusTeal   = Color(0xFF14B8A6);
    const Color statusGrey   = Color(0xFF6B7280);

    Color color;
    String label;

    switch (state) {
      case 'done':
        color = statusGreen;
        label = 'Done';
        break;
      case 'assigned':
        color = statusBlue;
        label = 'Ready';
        break;
      case 'waiting':
        color = statusOrange;
        label = 'Waiting';
        break;
      case 'confirmed':
        color = statusOrange;
        label = 'Waiting';
        break;
      case 'cancel':
        color = statusRed;
        label = 'Cancelled';
        break;
      case 'draft':
        color = statusGrey;
        label = 'Draft';
        break;
      default:
        color = statusGrey;
        label = capitalizeFirstLetter(stateMap[state] ?? state);
    }

    final backgroundColor = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : color.withValues(alpha: 0.10);
    final textColor = isDark ? Colors.white : color;
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
}
