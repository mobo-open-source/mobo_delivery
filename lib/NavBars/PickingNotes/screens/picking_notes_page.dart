import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hugeicons/hugeicons.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../Dashboard/infrastructure/profile_refresh_bus.dart';
import '../../../Dashboard/screens/dashboard/pages/dashboard.dart';
import '../../../Dashboard/services/storage_service.dart';
import '../../../core/company/infrastructure/company_refresh_bus.dart';
import '../../../core/company/providers/company_provider.dart';
import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../Pickings/PickingFormPage/services/hive_service.dart';
import '../../shimmer_loading.dart';
import '../services/odoo_picking_note_service.dart';
import '../utils/utils.dart';
import '../constants/constants.dart';
import 'add_picking_notes_page.dart';
import '../widgets/add_note_bottom_sheet.dart';

/// Main screen for viewing and managing internal notes on stock pickings (transfers, receipts, deliveries).
///
/// Features:
///   - Paginated list of pickings with search, filters, and grouping
///   - Offline support with cached data from Hive
///   - Displays existing notes (cleaned of HTML) on each picking tile
///   - Bottom sheet for adding/editing notes when online
///   - Periodic connectivity check and refresh buttons
///   - Empty/error states with Lottie animations and retry options
class PickingNotesPage extends StatefulWidget {
  const PickingNotesPage({super.key});

  @override
  State<PickingNotesPage> createState() => _PickingNotesPageState();
}

/// Manages state, data fetching, filtering, grouping, pagination, and offline/online handling for picking notes.
///
/// Key responsibilities:
///   - Loads and caches pickings from Odoo/Hive
///   - Handles search, filters, grouping, and pagination UI
///   - Refreshes list on connectivity change or user action
///   - Opens note-editing bottom sheet for selected picking
///   - Shows loading shimmer, empty states, error screens
class _PickingNotesPageState extends State<PickingNotesPage> {
  final OdooPickingNoteService _odooService = OdooPickingNoteService();
  List<Map<String, dynamic>> pickings = [];
  int currentPage = 0;
  final int itemsPerPage = 40;
  bool _isLoading = true;
  bool pageLoading = false;
  bool pageFilterLoading = false;
  final HiveService _hiveService = HiveService();
  final TextEditingController _searchController = TextEditingController();
  int totalCount = 0;
  int displayedCount = 0;
  int previousPagesCount = 0;
  late DashboardStorageService storageService;
  bool isOnline = false;
  int? userId;
  int? companyId;
  bool? isSystem;
  List<String> _selectedFilters = [];
  String? _selectedGroupBy;
  Map<String, List<Map<String, dynamic>>> _groupedPickings = {};
  Map<String, bool> _groupExpanded = {};
  bool hasFilters = false;
  bool hasGroupBy = false;
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
    storageService = DashboardStorageService();
    _initAll();
  }

  /// Initializes services, Hive, Odoo client, cached data, and starts initial fetch.
  Future<void> _initAll() async {
    await _initialize();
    await _initializeServices();
  }

  /// Rebuilds grouped pickings map based on current `_selectedGroupBy` and `pickings`.
  ///
  /// Clears existing groups and expansions, then groups items by the selected field.
  /// Special handling for 'state' (capitalized), 'origin' (fallback text), 'picking_type'.
  void _updateGroupedPickings() {
    _groupedPickings.clear();
    _groupExpanded.clear();

    if (_selectedGroupBy == null || _selectedGroupBy!.isEmpty) {
      return;
    }

    final Map<String, List<Map<String, dynamic>>> tempGroups = {};

    for (final picking in pickings) {
      String groupKey;

      switch (_selectedGroupBy) {
        case 'state':
          final state = picking['state']?.toString() ?? 'unknown';
          groupKey = capitalizeFirstLetter(state);
          break;

        case 'origin':
          groupKey = picking['origin']?.toString() ?? 'No Source Document';
          if (groupKey.trim().isEmpty) groupKey = 'No Source Document';
          break;

        case 'picking_type':
          groupKey = (picking['picking_type_id']?[1]?.toString() ?? 'Unknown');
          break;

        default:
          groupKey = 'UnKnown';
      }

      tempGroups.putIfAbsent(groupKey, () => []).add(picking);
    }

    setState(() {
      _groupedPickings = tempGroups;
      for (var key in tempGroups.keys) {
        _groupExpanded[key] = true;
      }
    });
  }

  /// Checks general connectivity + pings Odoo server `/web` endpoint.
  ///
  /// Returns `true` only if device has network **and** server responds with 200.
  Future<bool> checkNetworkConnectivity() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('url') ?? '';
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult != ConnectivityResult.none) {
      return true;
    }
    try {
      final response = await http
          .get(Uri.parse('$url/web'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  /// Sets `isOnline` flag based on connectivity check and triggers rebuild.
  Future<void> _initializeServices() async {
    isOnline = await checkNetworkConnectivity();
    setState(() {});
  }

  /// Initializes Odoo client, Hive, loads cached data, and fetches fresh pickings.
  ///
  /// Falls back to cached pickings on failure.
  /// Updates pagination metadata and groups if needed.
  Future<void> _initialize() async {
    setState(() => _isLoading = true);

    await _odooService.initializeClient();
    await _hiveService.initialize();

    final cachedPickings = await _hiveService.getPickings();
    if (cachedPickings.isNotEmpty) {
      setState(() {
        pickings = cachedPickings.map((p) => p.toJson()).toList();
        displayedCount = pickings.length;
        previousPagesCount = 0;
        _isLoading = false;
      });
    }
    totalCount = _hiveService.getTotalCount();
    await _fetchStockPickings(page: 0);
    await _updateTotalCount();
    setState(() => _isLoading = false);
  }

  /// Refreshes total count from Odoo and saves to Hive.
  Future<void> _updateTotalCount() async {
    final count = await _odooService.StockCount(
      searchText: _searchController.text,
      filters: _selectedFilters,
    );
    await _hiveService.saveTotalCount(count);
    setState(() {
      totalCount = count;
    });
  }

  /// Fetches one page of stock pickings from Odoo with search & filters.
  ///
  /// Saves results to Hive for offline use.
  /// Updates pagination state and groups.
  /// Catches errors and sets `catchError` flag.
  Future<void> _fetchStockPickings({required int page}) async {
    try {
      final newPickings = await _odooService.fetchStockPickings(
        page,
        itemsPerPage,
        searchQuery: _searchController.text,
        filters: _selectedFilters,
      );

      if (newPickings.isNotEmpty) {
        await _hiveService.savePickings(newPickings);
      }

      final int newPreviousPagesCount = page * itemsPerPage;
      await _updateTotalCount();

      setState(() {
        pickings = newPickings;
        currentPage = page;
        previousPagesCount = newPreviousPagesCount.clamp(0, totalCount);
        displayedCount = previousPagesCount + newPickings.length;
      });
      _updateGroupedPickings();
    } catch (e) {
      setState(() {
        catchError = true;
      });
    }
  }

  /// Generates human-readable page range string (e.g. "1-40", "41-80").
  ///
  /// Handles edge cases (zero items, last partial page).
  String get _pageRange {
    if (totalCount == 0) return '0-0';
    final start = currentPage * itemsPerPage + 1;
    final maxEnd = start + itemsPerPage - 1;
    final safeUpperBound = totalCount < start ? start : totalCount;
    final end = maxEnd.clamp(start, safeUpperBound);
    return '$start-$end';
  }

  /// Opens bottom sheet for selecting filters and grouping options.
  ///
  /// Uses tabs: "Filter" (chips) and "Group By" (radio options).
  /// Applies selections and refetches data on "Apply".
  /// Clears all filters/groups on "Clear All".
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
                            Icons.close,
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
                                _selectedFilters = [];
                                _selectedGroupBy = null;
                                hasFilters = false;
                                hasGroupBy = false;
                                currentPage = 0;
                              });

                              Navigator.pop(context);

                              _fetchStockPickings(page: 0);
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
                                hasGroupBy =
                                    _selectedGroupBy != null &&
                                    _selectedGroupBy!.isNotEmpty;

                                currentPage = 0;
                              });

                              Navigator.pop(context);
                              _fetchStockPickings(page: 0);
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

  /// Capitalizes first letter of a string (used for group keys).
  String capitalizeFirstLetter(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  /// Reloads current page of pickings (used by refresh indicators).
  Future<void> reloadPickingList() async {
    await _fetchStockPickings(page: currentPage);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: () async {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => Dashboard(initialIndex: 0)),
        );
        return false;
      },
      child: Scaffold(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        appBar: AppBar(
          backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
          title: Text(
            'Pickings',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
              fontSize: 22,
            ),
          ),
          leading: IconButton(
            icon: Icon(
              HugeIcons.strokeRoundedArrowLeft01,
              color: isDark ? Colors.white : Colors.black,
              size: 28,
            ),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => Dashboard(initialIndex: 0),
                ),
              );
            },
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                if (isOnline) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AddPickingNotesPage(),
                    ),
                  );
                } else {
                  CustomSnackbar.showError(
                    context,
                    'Cannot add note while offline. Please try again later.',
                  );
                }
              },
              icon: Icon(
                HugeIcons.strokeRoundedNoteAdd,
                color: isDark ? Colors.white : Colors.black,
              ),
              label: Text(
                'Add Note',
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
              ),
            ),
          ],
        ),
        body: Stack(
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
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              hintText: 'Search by Location and Item',
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
                                  HugeIcons.strokeRoundedFilterHorizontal,
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
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: AppStyle.primaryColor,
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              _fetchStockPickings(page: 0);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Filter/group status chips + pagination controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Builder(
                      builder: (context) {
                        hasFilters = _selectedFilters.isNotEmpty;
                        hasGroupBy = (_selectedGroupBy?.isNotEmpty ?? false);

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
                            orElse: () =>
                                _selectedGroupBy!.replaceAll('_', ' '),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.all(24.0),
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
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _selectedFilters.length.toString(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.black
                                              : Colors.white,
                                          fontWeight: FontWeight.w500,
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
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        HugeIcons.strokeRoundedLayer,
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
                                _pageRange,
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
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            HugeIcons.strokeRoundedArrowLeft01,
                            size: 25,
                            color: currentPage > 0
                                ? (isDark ? Colors.white70 : Colors.black87)
                                : (isDark
                                      ? Colors.grey[800]
                                      : Colors.grey.withOpacity(0.7)),
                          ),
                          onPressed: currentPage > 0
                              ? () async {
                                  setState(() {
                                    pageLoading = true;
                                  });
                                  await _fetchStockPickings(
                                    page: currentPage - 1,
                                  );
                                  setState(() {
                                    pageLoading = false;
                                  });
                                }
                              : null,
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            HugeIcons.strokeRoundedArrowRight01,
                            size: 25,
                            color: (currentPage + 1) * itemsPerPage < totalCount
                                ? (isDark ? Colors.white70 : Colors.black87)
                                : (isDark
                                      ? Colors.grey[800]
                                      : Colors.grey.withOpacity(0.7)),
                          ),
                          onPressed:
                              (currentPage + 1) * itemsPerPage < totalCount
                              ? () async {
                                  setState(() {
                                    pageLoading = true;
                                  });
                                  await _fetchStockPickings(
                                    page: currentPage + 1,
                                  );
                                  setState(() {
                                    pageLoading = false;
                                  });
                                }
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),

                // Main content: loading / empty / error / grouped / flat list
                _isLoading
                    ? Expanded(child: const GridViewShimmer())
                    : pickings.isEmpty
                    ? Expanded(
                        child: Center(
                          child: _buildEmptyState(isDark, hasFilters, context),
                        ),
                      )
                    : catchError
                    ? Expanded(
                        child: Center(child: _buildErrorState(isDark, context)),
                      )
                    : (_selectedGroupBy != null &&
                          _selectedGroupBy!.isNotEmpty &&
                          _groupedPickings.isNotEmpty)
                    ? Expanded(
                        child: RefreshIndicator(
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
                              final groupPickings =
                                  _groupedPickings[groupName]!;
                              final isExpanded =
                                  _groupExpanded[groupName] ?? true;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.grey[900]
                                      : Colors.white,
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
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          _groupExpanded[groupName] =
                                              !isExpanded;
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
                                                      fontWeight:
                                                          FontWeight.w600,
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
                                          padding: const EdgeInsets.all(8.0),
                                          child: _buildPickingCard(
                                            picking,
                                            isDark,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      )
                    : Expanded(
                        child: RefreshIndicator(
                          onRefresh: () async => reloadPickingList(),
                          child: ListView.builder(
                            itemCount: pickings.length,
                            itemBuilder: (context, index) {
                              final picking = pickings[index];
                              final dateInfo = Utils.getFormattedDateInfo(
                                picking['scheduled_date'],
                              );
                              final rawState = picking['state'] ?? 'unknown';
                              final readableState =
                                  AppConstants.stateLabels[rawState] ??
                                  rawState;
                              final statusColor =
                                  AppConstants.stateColors[rawState] ??
                                  Colors.black;

                              return Column(
                                children: [
                                  SizedBox(height: 10,),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Container(
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
                                      margin: const EdgeInsets.only(bottom: 8),
                                      child: ListTile(
                                        title: Text(
                                          picking['name'] ?? 'Unnamed Picking',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: isDark
                                                ? Colors.white
                                                : AppStyle.primaryColor,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (picking['note'] is String &&
                                                picking['note'].isNotEmpty) ...[
                                              Text(
                                                'Note: ${picking['note'].replaceAll(RegExp(r'<[^>]*>'), '')}',
                                                style: TextStyle(
                                                  color: isDark
                                                      ? Colors.white60
                                                      : Colors.black54,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                            ],
                                            Text(
                                              'Scheduled: ${dateInfo['label']}',
                                              style: TextStyle(
                                                color: isDark
                                                    ? Colors.white54
                                                    : dateInfo['color'],
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            readableState,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: statusColor,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        onTap: () {
                                          final rawNote = picking['note'];
                                          final cleanedNote = (rawNote is String)
                                              ? rawNote.replaceAll(
                                                  RegExp(r'<[^>]*>'),
                                                  '',
                                                )
                                              : '';
                                          if (isOnline) {
                                            showModalBottomSheet(
                                              context: context,
                                              shape: const RoundedRectangleBorder(
                                                borderRadius: BorderRadius.vertical(
                                                  top: Radius.circular(16),
                                                ),
                                              ),
                                              isScrollControlled: true,
                                              backgroundColor:
                                              Theme.of(context).brightness == Brightness.dark
                                                  ? Colors.grey[900]
                                                  : Colors.grey[50],
                                              builder: (context) => Padding(
                                                padding: MediaQuery.of(
                                                  context,
                                                ).viewInsets,
                                                child: AddNoteBottomSheet(
                                                  pickingId: picking['id'],
                                                  pickingName: picking['name'],
                                                  existingNote: cleanedNote,
                                                  onNoteAdded: () =>
                                                      _fetchStockPickings(
                                                        page: currentPage,
                                                      ),
                                                ),
                                              ),
                                            );
                                          } else {
                                            CustomSnackbar.showError(
                                              context,
                                              'Cannot add note while offline. Please try again later.',
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
              ],
            ),

            // Loading overlay during page fetch
            if (pageLoading)
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
    );
  }

  /// Builds a single picking card/tile with name, scheduled date, status badge, and note preview.
  ///
  /// Tapping opens note-editing bottom sheet (if online).
  Widget _buildPickingCard(Map<String, dynamic> picking, bool isDark) {
    final dateInfo = Utils.getFormattedDateInfo(picking['scheduled_date']);
    final rawState = picking['state'] ?? 'unknown';
    final readableState = AppConstants.stateLabels[rawState] ?? rawState;
    final statusColor = AppConstants.stateColors[rawState] ?? Colors.black;

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
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          picking['name'] ?? 'Unnamed Picking',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: isDark ? Colors.white : AppStyle.primaryColor,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (picking['note'] is String &&
                picking['note'].toString().isNotEmpty) ...[
              Text(
                'Note: ${picking['note'].toString().replaceAll(RegExp(r'<[^>]*>'), '')}',
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.grey[700],
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
            ],
            Text(
              'Scheduled: ${dateInfo['label']}',
              style: TextStyle(
                color: isDark ? Colors.white54 : dateInfo['color'],
                fontSize: 13,
              ),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            readableState,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: statusColor,
              fontSize: 12,
            ),
          ),
        ),
        onTap: () {
          final rawNote = picking['note'];
          final cleanedNote = (rawNote is String)
              ? rawNote.replaceAll(RegExp(r'<[^>]*>'), '')
              : '';

          if (isOnline) {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              backgroundColor:
              Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[900]
                  : Colors.grey[50],
              builder: (context) => Padding(
                padding: MediaQuery.of(context).viewInsets,
                child: AddNoteBottomSheet(
                  pickingId: picking['id'],
                  pickingName: picking['name'],
                  existingNote: cleanedNote,
                  onNoteAdded: () => _fetchStockPickings(page: currentPage),
                ),
              ),
            );
          } else {
            CustomSnackbar.showError(context, 'Cannot add note while offline.');
          }
        },
      ),
    );
  }

  /// Reusable centered layout with Lottie animation, title, subtitle, and optional action button.
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

  /// Empty state UI shown when no pickings are found.
  ///
  /// Displays ghost Lottie animation with optional "Clear Filters" button.
  Widget _buildEmptyState(bool isDark, hasFilters, BuildContext context) {
    return _buildCenteredLottie(
      lottie: 'assets/empty_ghost.json',
      title: 'No picking notes found',
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
                  _selectedFilters = [];
                  _selectedGroupBy = null;
                  hasFilters = false;
                  hasGroupBy = false;
                  currentPage = 0;
                });
                _fetchStockPickings(page: 0);
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

  /// Error state UI shown when data fetch fails.
  ///
  /// Displays 404-style Lottie animation with "Retry" button that reinitializes company data.
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
}
