import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:hugeicons/hugeicons.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../../Dashboard/infrastructure/profile_refresh_bus.dart';
import '../../../Dashboard/screens/dashboard/pages/dashboard.dart';
import '../../../Dashboard/services/storage_service.dart';
import '../../../core/company/infrastructure/company_refresh_bus.dart';
import '../../../core/company/providers/company_provider.dart';
import '../../../core/providers/motion_provider.dart';
import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../Pickings/PickingFormPage/services/hive_service.dart';
import '../../shimmer_loading.dart';
import '../bloc/attach_documents_bloc.dart';
import '../bloc/attach_documents_event.dart';
import '../bloc/attach_documents_state.dart';
import '../screens/signature_screen.dart';
import '../services/odoo_attach_service.dart';
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
  MotionProvider? _motionProvider;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionProvider = Provider.of<MotionProvider>(context, listen: false);
  }

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

  /// Shows bottom sheet with attachment options: Signature or File Upload.
  void _showAttachmentOptions(
    BuildContext context,
    Map<String, dynamic> picking,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor:
      Theme.of(context).brightness == Brightness.dark
          ? Colors.grey[900]
          : Colors.grey[50],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalContext) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            children: [
              ListTile(
                leading: Icon(
                  HugeIcons.strokeRoundedSignature,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                title: Text(
                  "Signature",
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                onTap: () {
                  Navigator.pop(modalContext);
                  _showSignatureOptions(context, picking);
                },
              ),
              ListTile(
                leading: Icon(
                  HugeIcons.strokeRoundedUploadSquare02,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                title: Text(
                  "Upload Images or PDF",
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                onTap: () => _pickAndUploadFile(context, picking, [
                  'jpg',
                  'jpeg',
                  'png',
                  'pdf',
                ]),
              ),
              ListTile(
                leading: Icon(
                  HugeIcons.strokeRoundedLink01,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                title: Text(
                  "Attach Document",
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                onTap: () => _pickAndUploadFile(context, picking, [
                  'pdf',
                  'doc',
                  'docx',
                  'xls',
                  'xlsx',
                  'txt',
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Displays secondary bottom sheet for signature-specific choices:
  /// Draw in-app or upload existing signature file.
  void _showSignatureOptions(
    BuildContext parentContext,
    Map<String, dynamic> picking,
  ) {
    final isDark = Theme.of(parentContext).brightness == Brightness.dark;

    showModalBottomSheet(
      context: parentContext,
      backgroundColor:
      Theme.of(context).brightness == Brightness.dark
          ? Colors.grey[900]
          : Colors.grey[50],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalContext) {
        return Wrap(
          children: [
            ListTile(
              leading: Icon(
                HugeIcons.strokeRoundedPenTool03,
                color: isDark ? Colors.white : Colors.black87,
              ),
              title: Text(
                "Signature from App",
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              onTap: () async {
                Navigator.pop(modalContext);
                final result = await Navigator.push(
                  parentContext,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const SignatureScreen(),
                    transitionDuration: _motionProvider?.reduceMotion ?? false
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    reverseTransitionDuration:
                        _motionProvider?.reduceMotion ?? false
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          if (_motionProvider?.reduceMotion ?? false)
                            return child;
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                  ),
                );
                if (result != null) {
                  try {
                    parentContext.read<AttachDocumentsBloc>().add(
                      UploadFile(
                        result['mimeType'],
                        result['base64'],
                        picking['id'],
                        result['fileName'],
                      ),
                    );
                    CustomSnackbar.showSuccess(
                      parentContext,
                      'File uploaded successfully.',
                    );
                  } catch (e) {
                    CustomSnackbar.showError(
                      context,
                      'Something went wrong, please try again later.',
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: Icon(
                HugeIcons.strokeRoundedFileUpload,
                color: isDark ? Colors.white : Colors.black87,
              ),
              title: Text(
                "Upload Signature",
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              onTap: () => _pickAndUploadFile(parentContext, picking, [
                'jpg',
                'jpeg',
                'png',
                'pdf',
              ]),
            ),
          ],
        );
      },
    );
  }

  /// Opens file picker with allowed extensions, encodes file to base64,
  /// and dispatches UploadFile event to the BLoC.
  Future<void> _pickAndUploadFile(
    BuildContext parentContext,
    Map<String, dynamic> picking,
    List<String> allowedExtensions,
  ) async {
    Navigator.pop(parentContext);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        withData: true,
      );
      if (result != null && result.files.single.bytes != null) {
        final fileBytes = result.files.single.bytes!;
        final fileName = result.files.single.name;
        final mimeType = Utils.getMimeType(fileName);
        final base64File = base64Encode(fileBytes);
        parentContext.read<AttachDocumentsBloc>().add(
          UploadFile(mimeType, base64File, picking['id'], fileName),
        );
        CustomSnackbar.showSuccess(
          parentContext,
          'File uploaded successfully.',
        );
      } else {
        CustomSnackbar.showError(context, 'File picking cancelled.');
      }
    } catch (e) {
      CustomSnackbar.showError(
        context,
        'Something went wrong, please try again later',
      );
    }
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

  /// Builds grouped/collapsible view when user selects a "Group By" option.
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
    final dateInfo = Utils.getFormattedDateInfo(
      picking['scheduled_date'] ?? '',
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
            color: const Color(0xFF000000).withOpacity(0.05),
            offset: const Offset(0, 6),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ListTile(
        title: Text(
          picking['name'] ?? 'Unnamed Picking',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: isDark ? Colors.white : AppStyle.primaryColor,
          ),
        ),
        subtitle: Text(
          'Scheduled: ${dateInfo['label']}',
          style: TextStyle(color: isDark ? Colors.white54 : dateInfo['color']),
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
        onTap: () async {},
      ),
    );
  }

  /// Reusable centered layout with Lottie animation, title, subtitle, and optional button.
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

  /// Shows empty state with ghost animation and optional "Clear Filters" button.
  Widget _buildEmptyState(bool isDark, hasFilters, BuildContext context) {
    return _buildCenteredLottie(
      lottie: 'assets/empty_ghost.json',
      title: 'No attachments found',
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
                context.read<AttachDocumentsBloc>().add(
                  FetchDocumentStockPickings(
                    0,
                    context.read<AttachDocumentsBloc>().itemsPerPage,
                    searchQuery: _searchController.text,
                    filters: _selectedFilters,
                    groupBy: _selectedGroupBy,
                  ),
                );
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

  /// Displays error state with 404-style animation and "Retry" button.
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
              appBar: AppBar(
                backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
                title: Text(
                  'Attach Signed Document',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 22,
                    color: isDark ? Colors.white : Colors.black,
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
              ),
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
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
                                    openFilterGroupBySheet(blocContext);
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
                                blocContext.read<AttachDocumentsBloc>().add(
                                  FetchDocumentStockPickings(
                                    0,
                                    blocContext
                                        .read<AttachDocumentsBloc>()
                                        .itemsPerPage,
                                    searchQuery: value,
                                    filters: _selectedFilters,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: BlocConsumer<AttachDocumentsBloc, AttachDocumentsState>(
                      listener: (context, state) {
                        if (state is AttachDocumentsError) {
                          Expanded(child: _buildErrorState(isDark, context));
                        }
                      },
                      builder: (context, state) {
                        if (state is AttachDocumentsLoading) {
                          return const GridViewShimmer();
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

                        return Stack(
                          children: [
                            Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Builder(
                                      builder: (context) {
                                        hasFilters =
                                            _selectedFilters.isNotEmpty;
                                        hasGroupBy =
                                            (_selectedGroupBy?.isNotEmpty ??
                                            false);

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
                                            "Operation Type": "picking_type_id",
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
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
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
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
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
                                                        groupDisplayName ??
                                                            "Group",
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: isDark
                                                              ? Colors.black
                                                              : Colors.white,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                        overflow: TextOverflow
                                                            .ellipsis,
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
                                        IconButton(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          icon: Icon(
                                            HugeIcons.strokeRoundedArrowLeft01,
                                            size: 25,
                                            color: currentPage > 0
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
                                              currentPage > 0 && !isFetchingMore
                                              ? () async {
                                                  if (isOnline) {
                                                    context
                                                        .read<
                                                          AttachDocumentsBloc
                                                        >()
                                                        .add(
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
                                                          ),
                                                        );
                                                  } else {
                                                    final hiveService =
                                                        HiveService();
                                                    final cachedPickings =
                                                        await hiveService
                                                            .getPickings();

                                                    if (cachedPickings
                                                        .isNotEmpty) {
                                                      final start =
                                                          (currentPage - 1) *
                                                          context
                                                              .read<
                                                                AttachDocumentsBloc
                                                              >()
                                                              .itemsPerPage;
                                                      final end =
                                                          start +
                                                          context
                                                              .read<
                                                                AttachDocumentsBloc
                                                              >()
                                                              .itemsPerPage;

                                                      final offlinePickings =
                                                          cachedPickings
                                                              .sublist(
                                                                start.clamp(
                                                                  0,
                                                                  cachedPickings
                                                                      .length,
                                                                ),
                                                                end.clamp(
                                                                  0,
                                                                  cachedPickings
                                                                      .length,
                                                                ),
                                                              )
                                                              .map(
                                                                (p) =>
                                                                    p.toJson()
                                                                        as Map<
                                                                          String,
                                                                          dynamic
                                                                        >,
                                                              )
                                                              .toList();

                                                      context
                                                          .read<
                                                            AttachDocumentsBloc
                                                          >()
                                                          .add(
                                                            LoadOfflineDocuments(
                                                              pickings:
                                                                  offlinePickings,
                                                              currentPage:
                                                                  currentPage -
                                                                  1,
                                                              totalCount:
                                                                  cachedPickings
                                                                      .length,
                                                            ),
                                                          );
                                                    } else {
                                                      CustomSnackbar.showError(
                                                        context,
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
                                            HugeIcons.strokeRoundedArrowRight01,
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
                                                      : Colors.grey.withOpacity(
                                                          0.7,
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
                                                        ),
                                                      );
                                                }
                                              : null,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                pickings.isEmpty
                                    ? Expanded(
                                        child: _buildEmptyState(
                                          isDark,
                                          hasFilters,
                                          context,
                                        ),
                                      )
                                    : hasGroupBy &&
                                          state.groupedPickings.isNotEmpty
                                    ? Expanded(
                                        child: _buildGroupedView(state, isDark),
                                      )
                                    : Expanded(
                                        child: RefreshIndicator(
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
                                            itemCount: pickings.length,
                                            itemBuilder: (context, index) {
                                              final picking = pickings[index];
                                              final dateInfo =
                                                  Utils.getFormattedDateInfo(
                                                    picking['scheduled_date'] ??
                                                        '',
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
                                                          picking['name'] ??
                                                              'Unnamed Picking',
                                                          style: TextStyle(
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 15,
                                                            color: isDark
                                                                ? Colors.white
                                                                : AppStyle.primaryColor,
                                                          ),
                                                        ),
                                                        subtitle: Text(
                                                          'Scheduled: ${dateInfo['label']}',
                                                          style: TextStyle(
                                                            color: isDark
                                                                ? Colors.white54
                                                                : dateInfo['color'],
                                                          ),
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
                                                        onTap: () {
                                                          if (isOnline) {
                                                            _showAttachmentOptions(
                                                              context,
                                                              picking,
                                                            );
                                                          } else {
                                                            CustomSnackbar.showError(
                                                              context,
                                                              'Cannot attach while offline. Please try again later.',
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
                            if (isFetchingMore)
                              Container(
                                child: Center(
                                  child:
                                      LoadingAnimationWidget.staggeredDotsWave(
                                        color: AppStyle.primaryColor,
                                        size: 50,
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
