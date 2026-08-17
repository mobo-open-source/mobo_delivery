import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hugeicons/hugeicons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/list_search_bar.dart';
import '../../../shared/widgets/error_state_widget.dart';
import '../../../shared/widgets/loaders/loading_widget.dart';
import '../../../shared/widgets/loaders/delivery_shimmers.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../Dashboard/infrastructure/profile_refresh_bus.dart';
import '../../../Dashboard/screens/dashboard/pages/dashboard.dart';
import '../../../Dashboard/services/storage_service.dart';
import '../../../core/company/infrastructure/company_refresh_bus.dart';
import '../../../core/company/providers/company_provider.dart';
import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/buttons/mobo_button.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../Pickings/PickingFormPage/services/hive_service.dart';
import '../bloc/attach_documents_bloc.dart';
import '../bloc/attach_documents_event.dart';
import '../bloc/attach_documents_state.dart';
import '../services/odoo_attach_service.dart';
import 'picking_documents_page.dart';
import '../utils/utils.dart';
import '../constants/constants.dart';

/// Screen for attaching documents (signatures, images, PDFs, etc.) to stock pickings/operations.
///
/// Displays a searchable, filterable, paginated list of pickings (transfers, receipts, deliveries).
/// Supports online/offline mode (uses Hive cache when offline), grouping, filtering, and
/// multiple attachment methods: drawing signature in-app, uploading files, or selecting existing documents.
class AttachDocumentsPage extends StatefulWidget {
  const AttachDocumentsPage({super.key});

  @override
  State<AttachDocumentsPage> createState() => _AttachDocumentsPageState();
}

/// Manages state, connectivity, UI interactions, file picking, and BLoC events for document attachment.
///
/// Responsibilities:
///   - Checks online/offline status and handles cached data when offline
///   - Manages search, filters, grouping, and pagination
///   - Shows bottom sheets for attachment options (signature / file upload)
///   - Handles signature capture & file uploads via BLoC
///   - Displays empty/error/loading states with Lottie animations
class _AttachDocumentsPageState extends State<AttachDocumentsPage> {
  late DashboardStorageService storageService;
  int? userId;
  int? companyId;
  bool? isSystem;
  bool isOnline = false;
  final TextEditingController _searchController = TextEditingController();

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

  /// Initializes services and checks connectivity on first build.
  Future<void> _initAll() async {
    await _initializeServices();
  }

  /// Checks real network connectivity + tries to reach the Odoo server URL.
  ///
  /// Returns `true` if connected to internet **and** Odoo server is reachable.
  /// Uses a quick GET request to `/web` with 5-second timeout.
  Future<bool> checkNetworkConnectivity() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('url') ?? '';
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.every((r) => r == ConnectivityResult.none)) {
      return false;
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

  /// Sets online status based on connectivity check and triggers UI rebuild.
  Future<void> _initializeServices() async {
    isOnline = await checkNetworkConnectivity();
    setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Compact "Expand/Collapse All (N)" toggle shown in place of the range
  /// badge when a group-by is active — matches pickings/returns lists.
  Widget _buildGroupToggle(bool isDark, List<String> groupKeys) {
    final expanded = groupKeys.every((k) => _groupExpanded[k] ?? true);
    return TextButton.icon(
      onPressed: () {
        setState(() {
          final target = !expanded;
          for (final key in groupKeys) {
            _groupExpanded[key] = target;
          }
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

  /// Opens filter & group-by bottom sheet with tabs, chips, and radio options.
  /// Applies selected filters/grouping and triggers data refetch on apply.
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

          return SafeArea(
            top: false,
            left: false,
            right: false,
            child: Container(
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
                              : AppStyle.primaryColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        indicatorPadding: const EdgeInsets.all(4),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        overlayColor: WidgetStateProperty.all(
                          Colors.transparent,
                        ),
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
                                        .where(
                                          (e) => tempFilters.contains(e.value),
                                        )
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
                                  children: filterTechnicalNames.keys.map((
                                    label,
                                  ) {
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
                                          ? Colors.white.withValues(alpha: 0.08)
                                          : AppStyle.primaryColor.withValues(
                                              alpha: 0.08,
                                            ),
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
                                  'Group documents by',
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
                                  subtitle:
                                      'Group by ${entry.key.toLowerCase()}',
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
                            color: isDark
                                ? Colors.grey[700]!
                                : Colors.grey[200]!,
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
                                pageContext.read<AttachDocumentsBloc>().add(
                                  FetchDocumentStockPickings(
                                    0,
                                    pageContext
                                        .read<AttachDocumentsBloc>()
                                        .itemsPerPage,
                                    searchQuery: _searchController.text,
                                    filters: _selectedFilters,
                                    groupBy: _selectedGroupBy,
                                  ),
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
                                pageContext.read<AttachDocumentsBloc>().add(
                                  FetchDocumentStockPickings(
                                    0,
                                    pageContext
                                        .read<AttachDocumentsBloc>()
                                        .itemsPerPage,
                                    searchQuery: _searchController.text,
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
            ),
          );
        },
      ),
    );
  }

  /// Builds grouped/collapsible view when user selects a "Group By" option.
  /// A removable "Active Filters" pill (mobo tint + border, with an ✕).
  Widget _buildActiveFilterChip(
    bool isDark,
    String label,
    VoidCallback onRemove,
  ) {
    return Container(
      padding: const EdgeInsets.only(left: 14, right: 8, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: AppStyle.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppStyle.primaryColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppStyle.primaryColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
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

  Widget _buildGroupedView(AttachDocumentsState state, bool isDark) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<AttachDocumentsBloc>().add(
          FetchDocumentStockPickings(
            0,
            context.read<AttachDocumentsBloc>().itemsPerPage,
            searchQuery: _searchController.text,
            filters: _selectedFilters,
          ),
        );
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: state.groupedPickings.length,
        itemBuilder: (context, index) {
          final groupKey = state.groupedPickings.keys.elementAt(index);
          final items = state.groupedPickings[groupKey]!;
          final isExpanded = _groupExpanded[groupKey] ?? true;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
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
                          ? HugeIcons.strokeRoundedArrowUp01
                          : HugeIcons.strokeRoundedArrowDown01,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),

                    splashColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    focusColor: Colors.transparent,
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
                        child: _buildAttachmentTile(picking, isDark, context),
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

  /// Builds individual picking tile with name, scheduled date, status badge.
  Widget _buildAttachmentTile(
    Map<String, dynamic> picking,
    bool isDark,
    BuildContext context,
  ) {
    final scheduledDateRaw = picking['scheduled_date'];
    final dateInfo = Utils.getFormattedDateInfo(
      scheduledDateRaw is String &&
              scheduledDateRaw.isNotEmpty &&
              scheduledDateRaw != 'false'
          ? scheduledDateRaw
          : '',
    );
    final rawState = picking['state'] ?? 'unknown';
    final readableState = AppConstants.stateLabels[rawState] ?? rawState;
    final statusColor = AppConstants.stateColors[rawState] ?? Colors.black;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
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
            color: const Color(0xFF000000).withOpacity(0.04),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        title: Text(
          picking['name'] ?? 'Unnamed Picking',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: AppStyle.accentOf(context),
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              Icon(
                HugeIcons.strokeRoundedCalendar03,
                size: 13,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                    children: [
                      const TextSpan(text: 'Scheduled: '),
                      TextSpan(
                        text: '${dateInfo['label']}',
                        style: TextStyle(
                          color:
                              dateInfo['color'] as Color? ??
                              (isDark ? Colors.grey[400] : Colors.grey[600]),
                          fontWeight: dateInfo['color'] != null
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            readableState,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w600,
              fontSize: 11,
              letterSpacing: 0.1,
            ),
          ),
        ),
        onTap: () async {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocProvider(
      create: (context) => AttachDocumentsBloc(
        odooService: OdooAttachService(),
        hiveService: HiveService(),
      )..add(InitializeAttachDocuments()),
      child: Builder(
        builder: (blocContext) {
          return WillPopScope(
            onWillPop: () async {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => Dashboard(initialIndex: 0),
                ),
              );
              return false;
            },
            child: Scaffold(
              backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
              body: Column(
                children: [
                  ListSearchBar(
                    controller: _searchController,
                    hintText: 'Search documents...',
                    hasActiveFilters:
                        _selectedFilters.isNotEmpty ||
                        (_selectedGroupBy?.isNotEmpty ?? false),
                    onFilterTap: () => openFilterGroupBySheet(blocContext),
                    onChanged: (value) {
                      blocContext.read<AttachDocumentsBloc>().add(
                        FetchDocumentStockPickings(
                          0,
                          blocContext.read<AttachDocumentsBloc>().itemsPerPage,
                          searchQuery: value,
                          filters: _selectedFilters,
                        ),
                      );
                    },
                  ),
                  Expanded(
                    child: BlocConsumer<AttachDocumentsBloc, AttachDocumentsState>(
                      listenWhen: (prev, curr) =>
                          prev != curr &&
                          (curr is AttachDocumentsError ||
                              curr is AttachDocumentsFileUploaded),
                      listener: (context, state) {
                        if (state is AttachDocumentsError) {
                          CustomSnackbar.showError(context, state.message);
                        } else if (state is AttachDocumentsFileUploaded) {
                          CustomSnackbar.showSuccess(context, state.message);
                        }
                      },
                      builder: (context, state) {
                        if (state is AttachDocumentsLoading) {
                          return const Column(
                            children: [
                              PaginationBarShimmer(),
                              Expanded(
                                child: AttachmentPickingListShimmer(
                                  itemCount: 8,
                                ),
                              ),
                            ],
                          );
                        }

                        if (state is AttachDocumentsError &&
                            state.pickings.isEmpty) {
                          return ErrorStateWidget(
                            errorMessage: state.message,
                            onRetry: () async {
                              await context
                                  .read<CompanyProvider>()
                                  .initialize();
                              ProfileRefreshBus.notifyProfileRefresh();
                              CompanyRefreshBus.notify();
                            },
                          );
                        }

                        final pickings = state is AttachDocumentsLoaded
                            ? state.pickings
                            : state is AttachDocumentsFileUploaded
                            ? state.pickings
                            : state is AttachDocumentsError
                            ? state.pickings
                            : [];

                        final isFetchingMore = state is AttachDocumentsLoaded
                            ? state.isFetchingMore
                            : state is AttachDocumentsFileUploaded
                            ? state.isFetchingMore
                            : state is AttachDocumentsError
                            ? state.isFetchingMore
                            : false;

                        final currentPage = state is AttachDocumentsLoaded
                            ? state.currentPage
                            : state is AttachDocumentsFileUploaded
                            ? state.currentPage
                            : state is AttachDocumentsError
                            ? state.currentPage
                            : 0;

                        final totalCount = state is AttachDocumentsLoaded
                            ? state.totalCount
                            : state is AttachDocumentsFileUploaded
                            ? state.totalCount
                            : state is AttachDocumentsError
                            ? state.totalCount
                            : 0;

                        final groupedNow =
                            hasGroupBy &&
                            state is AttachDocumentsLoaded &&
                            state.groupedPickings.isNotEmpty;
                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                12,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildFilterIndicator(
                                    isDark,

                                    _selectedFilters.length,
                                  ),
                                  if (groupedNow)
                                    _buildGroupToggle(
                                      isDark,
                                      state.groupedPickings.keys.toList(),
                                    )
                                  else
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
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
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
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
                                                (state is AttachDocumentsLoaded)
                                                    ? state.pageRange
                                                    : '',
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
                                        if (totalCount >
                                            context
                                                .read<AttachDocumentsBloc>()
                                                .itemsPerPage) ...[
                                          IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            icon: Icon(
                                              HugeIcons
                                                  .strokeRoundedArrowLeft01,
                                              size: 25,
                                              color: currentPage > 0
                                                  ? (isDark
                                                        ? Colors.white70
                                                        : Colors.black87)
                                                  : (isDark
                                                        ? Colors.grey[800]
                                                        : Colors.grey
                                                              .withValues(
                                                                alpha: 0.7,
                                                              )),
                                            ),
                                            onPressed:
                                                currentPage > 0 &&
                                                    !isFetchingMore
                                                ? () async {
                                                    if (isOnline) {
                                                      context.read<AttachDocumentsBloc>().add(
                                                        FetchDocumentStockPickings(
                                                          currentPage - 1,
                                                          context
                                                              .read<
                                                                AttachDocumentsBloc
                                                              >()
                                                              .itemsPerPage,
                                                          searchQuery:
                                                              _searchController
                                                                  .text,
                                                          filters:
                                                              _selectedFilters,
                                                          groupBy:
                                                              _selectedGroupBy,
                                                        ),
                                                      );
                                                    } else {
                                                      final bloc = context
                                                          .read<
                                                            AttachDocumentsBloc
                                                          >();
                                                      final hiveService =
                                                          HiveService();
                                                      final cachedPickings =
                                                          await hiveService
                                                              .getPickings();
                                                      if (!mounted) return;
                                                      if (cachedPickings
                                                          .isNotEmpty) {
                                                        final itemsPerPage =
                                                            bloc.itemsPerPage;
                                                        final start =
                                                            (currentPage - 1) *
                                                            itemsPerPage;
                                                        final end =
                                                            start +
                                                            itemsPerPage;
                                                        final offlinePickings = cachedPickings
                                                            .sublist(
                                                              start
                                                                  .clamp(
                                                                    0,
                                                                    cachedPickings
                                                                        .length,
                                                                  )
                                                                  .toInt(),
                                                              end
                                                                  .clamp(
                                                                    0,
                                                                    cachedPickings
                                                                        .length,
                                                                  )
                                                                  .toInt(),
                                                            )
                                                            .map(
                                                              (p) => p.toJson(),
                                                            )
                                                            .toList();
                                                        bloc.add(
                                                          LoadOfflineDocuments(
                                                            pickings:
                                                                offlinePickings,
                                                            currentPage:
                                                                currentPage - 1,
                                                            totalCount:
                                                                cachedPickings
                                                                    .length,
                                                          ),
                                                        );
                                                      } else {
                                                        CustomSnackbar.showError(
                                                          this.context,
                                                          "No cached data available offline.",
                                                        );
                                                      }
                                                    }
                                                  }
                                                : null,
                                          ),
                                          IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            icon: Icon(
                                              HugeIcons
                                                  .strokeRoundedArrowRight01,
                                              size: 25,
                                              color:
                                                  (currentPage + 1) *
                                                          context
                                                              .read<
                                                                AttachDocumentsBloc
                                                              >()
                                                              .itemsPerPage <
                                                      totalCount
                                                  ? (isDark
                                                        ? Colors.white70
                                                        : Colors.black87)
                                                  : (isDark
                                                        ? Colors.grey[800]
                                                        : Colors.grey
                                                              .withValues(
                                                                alpha: 0.7,
                                                              )),
                                            ),
                                            onPressed:
                                                (currentPage + 1) *
                                                            context
                                                                .read<
                                                                  AttachDocumentsBloc
                                                                >()
                                                                .itemsPerPage <
                                                        totalCount &&
                                                    !isFetchingMore
                                                ? () {
                                                    context
                                                        .read<
                                                          AttachDocumentsBloc
                                                        >()
                                                        .add(
                                                          FetchDocumentStockPickings(
                                                            currentPage + 1,
                                                            context
                                                                .read<
                                                                  AttachDocumentsBloc
                                                                >()
                                                                .itemsPerPage,
                                                            searchQuery:
                                                                _searchController
                                                                    .text,
                                                            filters:
                                                                _selectedFilters,
                                                            groupBy:
                                                                _selectedGroupBy,
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
                            ),
                            pickings.isEmpty
                                ? Expanded(
                                    child: Builder(
                                      builder: (ctx) {
                                        final searchTerm = _searchController
                                            .text
                                            .trim();
                                        final hasSearch = searchTerm.isNotEmpty;
                                        final hasActiveFilters =
                                            hasFilters || hasGroupBy;
                                        final searchOnly =
                                            hasSearch && !hasActiveFilters;

                                        String title;
                                        String subtitle;
                                        String? actionLabel;
                                        VoidCallback? onAction;

                                        if (searchOnly) {
                                          title =
                                              'No results for "$searchTerm"';
                                          subtitle =
                                              'Try a different search term.';
                                          actionLabel = 'Clear Search';
                                          onAction = () {
                                            setState(
                                              () => _searchController.clear(),
                                            );
                                            context
                                                .read<AttachDocumentsBloc>()
                                                .add(
                                                  FetchDocumentStockPickings(
                                                    0,
                                                    context
                                                        .read<
                                                          AttachDocumentsBloc
                                                        >()
                                                        .itemsPerPage,
                                                    searchQuery: '',
                                                    filters: _selectedFilters,
                                                    groupBy: _selectedGroupBy,
                                                  ),
                                                );
                                          };
                                        } else if (hasActiveFilters) {
                                          title = 'No attachments found';
                                          subtitle =
                                              'Try adjusting your filters or search term.';
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
                                            context
                                                .read<AttachDocumentsBloc>()
                                                .add(
                                                  FetchDocumentStockPickings(
                                                    0,
                                                    context
                                                        .read<
                                                          AttachDocumentsBloc
                                                        >()
                                                        .itemsPerPage,
                                                    searchQuery: '',
                                                    filters: const [],
                                                    groupBy: null,
                                                  ),
                                                );
                                          };
                                        } else {
                                          title = 'No attachments found';
                                          subtitle =
                                              'There are no attachments available.';
                                        }

                                        return EmptyState(
                                          title: title,
                                          subtitle: subtitle,
                                          actionLabel: actionLabel,
                                          onAction: onAction,
                                        );
                                      },
                                    ),
                                  )
                                : hasGroupBy && state.groupedPickings.isNotEmpty
                                ? Expanded(
                                    child: _buildGroupedView(state, isDark),
                                  )
                                : Expanded(
                                    child: RefreshIndicator(
                                      onRefresh: () async {
                                        context.read<AttachDocumentsBloc>().add(
                                          FetchDocumentStockPickings(
                                            0,
                                            context
                                                .read<AttachDocumentsBloc>()
                                                .itemsPerPage,
                                            searchQuery: _searchController.text,
                                            filters: _selectedFilters,
                                          ),
                                        );
                                      },
                                      child: ListView.builder(
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
                                        padding: const EdgeInsets.only(
                                          top: 4,
                                          bottom: 16,
                                        ),
                                        itemCount:
                                            pickings.length +
                                            (isFetchingMore ? 1 : 0),
                                        itemBuilder: (context, index) {
                                          if (index == pickings.length) {
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 14,
                                                  ),
                                              child: Center(
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const LoadingWidget(
                                                      size: 26,
                                                      variant: LoadingVariant
                                                          .staggeredDots,
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Text(
                                                      'Loading more documents...',
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        color: isDark
                                                            ? Colors.white70
                                                            : Colors.grey[600],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }
                                          final picking = pickings[index];
                                          final scheduledDateRaw2 =
                                              picking['scheduled_date'];
                                          final dateInfo =
                                              Utils.getFormattedDateInfo(
                                                scheduledDateRaw2 is String &&
                                                        scheduledDateRaw2
                                                            .isNotEmpty &&
                                                        scheduledDateRaw2 !=
                                                            'false'
                                                    ? scheduledDateRaw2
                                                    : '',
                                              );
                                          final rawState =
                                              picking['state'] ?? 'unknown';
                                          final readableState =
                                              AppConstants
                                                  .stateLabels[rawState] ??
                                              rawState;
                                          final statusColor =
                                              AppConstants
                                                  .stateColors[rawState] ??
                                              Colors.black;

                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                            ),
                                            child: Container(
                                              margin: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isDark
                                                    ? Colors.grey[850]
                                                    : Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: isDark
                                                      ? Colors.grey[850]!
                                                      : Colors.grey[200]!,
                                                  width: 0.5,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: const Color(
                                                      0xFF000000,
                                                    ).withOpacity(0.04),
                                                    offset: const Offset(0, 2),
                                                    blurRadius: 8,
                                                  ),
                                                ],
                                              ),
                                              child: Material(
                                                color: Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                clipBehavior: Clip.antiAlias,
                                                child: ListTile(
                                                  contentPadding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 2,
                                                      ),
                                                  title: Text(
                                                    picking['name'] ??
                                                        'Unnamed Picking',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 15,
                                                      color: isDark
                                                          ? Colors.white
                                                          : AppStyle
                                                                .primaryColor,
                                                    ),
                                                  ),
                                                  subtitle: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 2,
                                                        ),
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          HugeIcons
                                                              .strokeRoundedCalendar03,
                                                          size: 13,
                                                          color: isDark
                                                              ? Colors.grey[400]
                                                              : Colors
                                                                    .grey[600],
                                                        ),
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        Expanded(
                                                          child: Text.rich(
                                                            TextSpan(
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                color: isDark
                                                                    ? Colors
                                                                          .grey[400]
                                                                    : Colors
                                                                          .grey[600],
                                                              ),
                                                              children: [
                                                                const TextSpan(
                                                                  text:
                                                                      'Scheduled: ',
                                                                ),
                                                                TextSpan(
                                                                  text:
                                                                      '${dateInfo['label']}',
                                                                  style: TextStyle(
                                                                    color:
                                                                        dateInfo['color']
                                                                            as Color? ??
                                                                        (isDark
                                                                            ? Colors.grey[400]
                                                                            : Colors.grey[600]),
                                                                    fontWeight:
                                                                        dateInfo['color'] !=
                                                                            null
                                                                        ? FontWeight
                                                                              .w600
                                                                        : FontWeight
                                                                              .w400,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  trailing: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 9,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: statusColor
                                                          .withValues(
                                                            alpha: 0.10,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      readableState,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: statusColor,
                                                        fontSize: 11,
                                                        letterSpacing: 0.1,
                                                      ),
                                                    ),
                                                  ),
                                                  onTap: () {
                                                    Navigator.of(context).push(
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            PickingDocumentsPage(
                                                              picking: picking,
                                                            ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                          ],
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
    );
  }
}
