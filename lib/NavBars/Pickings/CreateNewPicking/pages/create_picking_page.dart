import 'package:flutter/cupertino.dart';
import 'package:shimmer/shimmer.dart';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../../../Rating/review_service.dart';
import '../../../../shared/utils/globals.dart';
import '../../../../shared/widgets/loaders/loading_widget.dart';
import '../../../../shared/widgets/snackbar.dart';
import '../../PickingFormPage/pages/picking_details_page.dart';
import '../../PickingFormPage/services/hive_service.dart';
import '../../PickingFormPage/services/odoo_picking_form_service.dart';
import '../models/product.dart';
import '../models/partner.dart';
import '../models/user.dart';
import '../models/operation_type.dart';
import '../models/stock_move.dart';
import '../services/odoo_create_picking_service.dart';
import '../widgets/add_product_dialog.dart';
import '../widgets/additional_info.dart';
import '../widgets/info_row.dart';
import '../widgets/notes_tab.dart';
import '../widgets/product_table.dart';

/// Full-screen form page for creating a new stock picking (transfer, receipt, delivery, etc.).
///
/// Allows the user to:
///   - Select delivery partner (customer/supplier)
///   - Choose operation type (determines source/destination locations)
///   - Set scheduled date, source document, shipping policy, responsible user, internal note
///   - Add one or more products (with quantity)
///   - Save online (creates in Odoo + navigates to details) or offline (stores in Hive)
///
/// Supports dark/light theme, motion reduction, offline fallback, form validation,
/// error display, and analytics tracking on successful creation.
class CreatePickingPage extends StatefulWidget {
  final String url;

  const CreatePickingPage({Key? key, required this.url}) : super(key: key);

  @override
  State<CreatePickingPage> createState() => _CreatePickingPageState();
}

/// Manages form state, data loading (online/offline), product lines, validation,
/// and creation logic for new stock pickings.
///
/// Key responsibilities:
///   - Loads dropdown data (products, partners, users, operation types)
///   - Falls back to Hive cache when offline
///   - Builds picking payload with move lines (products)
///   - Creates picking online (Odoo) or saves offline (Hive)
///   - Navigates to details page on success (online)
class _CreatePickingPageState extends State<CreatePickingPage> {
  late OdooCreatePickingService odooService;
  List<ProductModel> products = [];
  List<PartnerModel> partnerList = [];
  List<UserModel> users = [];
  List<OperationTypeModel> operationTypes = [];
  List<StockMoveModel> moveProducts = [];
  int? userId;
  String _errorMessage = '';
  bool isLoading = true;

  final TextEditingController scheduledDateController = TextEditingController();
  final TextEditingController sourceDocController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  String _selectedShippingPolicy = 'direct';
  int? _selectedPartnerId;
  int? _selectedUserId;
  int? _selectedOperationTypeId;
  int? defaultLocationSrcId;
  int? defaultLocationDestId;
  String? _selectedPartnerName;
  String? _selectedOperationTypeName;
  String? _selectedUserName;
  final HiveService _hiveService = HiveService();
  final odooPickingFormService = OdooPickingFormService();

  @override
  void initState() {
    super.initState();
    odooService = OdooCreatePickingService(widget.url);
    _initializeData();
  }

  /// Loads dropdown data (products, partners, users, operation types) either online or from Hive cache.
  ///
  /// Online path: loads from Odoo. For any list that comes back empty (silent RPC failure),
  /// falls back to the Hive cache so the form is still usable.
  /// Offline path: loads entirely from Hive cache.
  /// Shows an error if critical dropdowns (partner + operation type) couldn't be populated at all.
  Future<void> _initializeData() async {
    try {
      // 1. Always load offline data first as a robust baseline
      await _loadOfflineData();

      final initResults = await Future.wait([
        odooPickingFormService.checkNetworkConnectivity(),
        SharedPreferences.getInstance(),
      ]);
      final isOnline = initResults[0] as bool;
      final prefs = initResults[1] as SharedPreferences;

      userId = prefs.getInt('userId') ?? 0;
      if (isOnline) {
        final results = await Future.wait([
          odooService.loadProducts().catchError((e) {
            debugPrint('loadProducts error: $e');
            return <ProductModel>[];
          }),
          odooService.loadPartners().catchError((e) {
            debugPrint('loadPartners error: $e');
            return <PartnerModel>[];
          }),
          odooService.loadUsers().catchError((e) {
            debugPrint('loadUsers error: $e');
            return <UserModel>[];
          }),
          odooService.loadOperationTypes().catchError((e) {
            debugPrint('loadOperationTypes error: $e');
            return <OperationTypeModel>[];
          }),
        ]);
        
        final freshProducts = (results[0] as List?)?.cast<ProductModel>() ?? <ProductModel>[];
        final freshPartners = (results[1] as List?)?.cast<PartnerModel>() ?? <PartnerModel>[];
        final freshUsers = (results[2] as List?)?.cast<UserModel>() ?? <UserModel>[];
        final freshOpTypes = (results[3] as List?)?.cast<OperationTypeModel>() ?? <OperationTypeModel>[];

        setState(() {
          if (freshProducts.isNotEmpty) products = freshProducts;
          if (freshPartners.isNotEmpty) partnerList = freshPartners;
          if (freshUsers.isNotEmpty) users = freshUsers;
          if (freshOpTypes.isNotEmpty) operationTypes = freshOpTypes;
        });
      }

      // If the two required dropdowns are still empty after all fallbacks, surface an error.
      if (mounted && partnerList.isEmpty && operationTypes.isEmpty) {
        setState(() {
          _errorMessage =
              "Could not load required data (partners and operation types). "
              "Please check your connection and pull down to retry.";
        });
      } else {
        setState(() {
          _errorMessage = '';
        });
      }
    } catch (e) {
      debugPrint("Error initializing data: $e");
      if (mounted && partnerList.isEmpty && operationTypes.isEmpty) {
        setState(() {
          _errorMessage = "Error loading data: ${e.toString().replaceFirst('Exception: ', '')}";
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  /// Fills only the lists that are currently empty from the Hive cache.
  /// Called after an online load where individual RPC calls silently returned [].
  Future<void> _loadOfflineDataForEmpty() async {
    try {
      if (products.isEmpty) {
        final productsData = await _hiveService.getProducts();
        products = productsData
            .map((p) => ProductModel(id: p.id, name: p.name, uom_id: p.uom_id))
            .toList();
      }
      if (partnerList.isEmpty) {
        final partnersData = await _hiveService.getPartners();
        partnerList = partnersData
            .map((p) => PartnerModel(id: p.id, name: p.name))
            .toList();
      }
      if (users.isEmpty) {
        final usersData = await _hiveService.getUsers();
        users = usersData
            .map((u) => UserModel(id: u.id, name: u.name))
            .toList();
      }
      if (operationTypes.isEmpty) {
        final operationsData = await _hiveService.getOperationTypes();
        operationTypes = operationsData
            .map(
              (o) => OperationTypeModel(
                id: o.id,
                name: o.name,
                defaultLocationSrcId: o.defaultLocationSrcId,
                defaultLocationDestId: o.defaultLocationDestId,
              ),
            )
            .toList();
      }
    } catch (e) {
      debugPrint("Error loading offline fallback data: $e");
    }
  }

  /// Loads cached dropdown data from Hive when offline.
  ///
  /// Maps Hive models to UI models.
  /// Sets error message if any load fails.
  Future<void> _loadOfflineData() async {
    try {
      final productsData = await _hiveService.getProducts();
      final partnersData = await _hiveService.getPartners();
      final usersData = await _hiveService.getUsers();
      final operationsData = await _hiveService.getOperationTypes();

      setState(() {
        products = productsData
            .map((p) => ProductModel(id: p.id, name: p.name, uom_id: p.uom_id))
            .toList();

        partnerList = partnersData
            .map((p) => PartnerModel(id: p.id, name: p.name))
            .toList();

        users = usersData
            .map((u) => UserModel(id: u.id, name: u.name))
            .toList();

        operationTypes = operationsData
            .map(
              (o) => OperationTypeModel(
                id: o.id,
                name: o.name,
                defaultLocationSrcId: o.defaultLocationSrcId,
                defaultLocationDestId: o.defaultLocationDestId,
              ),
            )
            .toList();
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Failed to load offline data.";
      });
    }
  }

  /// Adds a new product line (stock move) to the picking.
  ///
  /// Called from `AddProductDialog` callback.
  /// Triggers rebuild to show updated product table.
  void addProductToLine(
    int productId,
    String productName,
    int productUomId,
    double quantity,
  ) {
    setState(() {
      moveProducts.add(
        StockMoveModel(
          productId: productId,
          productName: productName,
          productUomQty: quantity,
          productUomId: productUomId,
          quantity: quantity,
        ),
      );
    });
  }

  /// Validates form and creates the picking (online or offline).
  ///
  /// Online flow:
  ///   1. Formats scheduled date
  ///   2. Creates picking record
  ///   3. Fetches auto-assigned locations
  ///   4. Creates stock moves for each product
  ///   5. Fetches full details and navigates to PickingDetailsPage
  ///
  /// Offline flow:
  ///   - Saves complete payload to Hive as pending create
  ///   - Shows warning and pops screen
  ///
  /// Handles validation errors and shows user feedback.
  Future<void> _createPicking() async {
    if (_selectedPartnerId == null && _selectedOperationTypeId == null) {
      setState(() {
        _errorMessage = "Please select a Delivery Address and Operation Type.";
      });
      return;
    }
    if (_selectedPartnerId == null) {
      setState(() {
        _errorMessage = "Please select a Delivery Address.";
      });
      return;
    }
    if (_selectedOperationTypeId == null) {
      setState(() {
        _errorMessage = "Please select an Operation Type.";
      });
      return;
    }
    setState(() {
      isLoading = true;
    });

    final pickingService = OdooCreatePickingService(widget.url);
    final isOnline = await pickingService.checkNetworkConnectivity();

    try {
      String? formattedScheduledDate;
      final rawText = scheduledDateController.text.trim();
      if (rawText.isNotEmpty && rawText.toLowerCase() != 'none') {
        DateTime date;
        try {
          date = DateFormat('dd-MM-yyyy HH:mm:ss').parse(rawText);
        } catch (_) {
          try {
            date = DateFormat('dd-MM-yyyy').parse(rawText);
          } catch (_) {
            date = DateTime.now();
          }
        }
        formattedScheduledDate = DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
      } else {
        formattedScheduledDate = DateFormat(
          'yyyy-MM-dd HH:mm:ss',
        ).format(DateTime.now());
      }

      if (isOnline) {
        final pickingId = await odooService.createPicking(
          partnerId: _selectedPartnerId!,
          operationTypeId: _selectedOperationTypeId!,
          scheduledDate: formattedScheduledDate,
          origin: sourceDocController.text.isNotEmpty
              ? sourceDocController.text
              : null,
          moveType: _selectedShippingPolicy,
          userId: _selectedUserId,
          note: _noteController.text.isNotEmpty ? _noteController.text : null,
        );

        final locations = await odooService.getPickingLocations(pickingId!);
        final locationId = locations['location_id'] as int?;
        final locationDestId = locations['location_dest_id'] as int?;

        if (locationId == null || locationDestId == null) {
          throw Exception("Invalid locations");
        }

        // Defensive: surface per-product failures instead of letting one
        // bad UoM / location / access error leave the picking silently
        // empty in Odoo. The picking itself was already created above —
        // if any move fails we stop, report the first failure with the
        // product name, and let the user retry in the form view.
        for (var product in moveProducts) {
          try {
            await odooService.createStockMove(
              name: product.productName,
              productId: product.productId,
              productUomQty: product.productUomQty,
              productUomId: product.productUomId,
              pickingId: pickingId,
              locationId: locationId,
              locationDestId: locationDestId,
            );
          } catch (e) {
            throw Exception(
              "Failed to add '${product.productName}': "
              "${e.toString().replaceFirst('Exception: ', '')}",
            );
          }
        }

        if (moveProducts.isNotEmpty) {
          await odooService.confirmPicking(pickingId);
        }

        final newPicking = await odooService.getNewPickingDetails(pickingId);

        if (newPicking != null) {
          setState(() => isLoading = false);
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  PickingDetailsPage(
                    picking: {
                      'id': newPicking['id'],
                      'item': newPicking['name'],
                      'location_id_int': locationId,
                      'location_dest_id_int': locationDestId,
                    },
                    odooService: OdooPickingFormService(),
                    isPickingForm: true,
                    isReturnPicking: false,
                    isReturnCreate: false,
                  ),
              transitionDuration: const Duration(milliseconds: 300),
              reverseTransitionDuration: const Duration(milliseconds: 300),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
return FadeTransition(opacity: animation, child: child);
                  },
            ),
          );
          ReviewService().trackSignificantEvent();
          Future.delayed(const Duration(seconds: 3), () {
            if (!mounted) return;
            ReviewService().checkAndShowRating(context);
          });
        } else {
          setState(() {
            isLoading = false;
            _errorMessage = "Failed to fetch newly created picking details.";
          });
        }
      } else {
        final hiveService = HiveService();

        await hiveService.savePendingCreates({
          'partnerId': _selectedPartnerId,
          'partnerName': _selectedPartnerName,
          'operationTypeId': _selectedOperationTypeId,
          'operationTypeName': _selectedOperationTypeName,
          'scheduledDate': formattedScheduledDate,
          'origin': sourceDocController.text,
          'moveType': _selectedShippingPolicy,
          'userId': _selectedUserId,
          'userName': _selectedUserName,
          'note': _noteController.text,
          'products': moveProducts
              .map(
                (p) => {
                  'productId': p.productId,
                  'productName': p.productName,
                  'productUomQty': p.productUomQty,
                  'productUomId': p.productUomId,
                  'defaultLocationSrcId': defaultLocationSrcId,
                  'defaultLocationDestId': defaultLocationDestId,
                },
              )
              .toList(),
        });

        setState(() {
          isLoading = false;
          _errorMessage = "No internet. Picking saved offline.";
        });
        CustomSnackbar.showWarning(
          context,
          'No internet. Picking saved offline.',
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        _errorMessage = "Failed to create picking: $e";
      });
    }
  }

  /// Shows dialog to add a new product line to the picking.
  void _showAddProductDialog() {
    showDialog(
      context: context,
      builder: (context) => AddProductDialog(
        products: products,
        onAdd: (selectedProduct, quantity) {
          if (selectedProduct != null && quantity > 0) {
            addProductToLine(
              selectedProduct.id,
              selectedProduct.name,
              selectedProduct.uom_id,
              quantity,
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isLoading) {
      return Scaffold(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],

        appBar: AppBar(
          forceMaterialTransparency: true,
          backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
          title: Text(
            "Create New Picking",
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
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _buildShimmerLoading(),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        forceMaterialTransparency: true,
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        title: Text(
          'Create New Picking',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: isDark ? Colors.white : Colors.black,
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Delivery Information',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.grey[900],
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: isDark ? Colors.grey[700] : Colors.grey[200],
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Delivery Address',
                              style: TextStyle(
                                fontWeight: FontWeight.w400,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xff7F7F7F),
                              ),
                            ),

                            const SizedBox(height: 8),
                            InfoRow(
                              label: "Delivery Address",
                              value: null,
                              isEditing: true,
                              dropdownItems: partnerList,
                              selectedId: _selectedPartnerId,
                              prefixIcon:
                                  HugeIcons.strokeRoundedPackageDelivered,
                              onDropdownChanged: (value) {
                                setState(() {
                                  _selectedPartnerId = value?.id;
                                  _selectedPartnerName = value?.name;
                                  _errorMessage = '';
                                });
                              },
                            ),
                            const SizedBox(height: 12),

                            Text(
                              'Operation Type',
                              style: TextStyle(
                                fontWeight: FontWeight.w400,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xff7F7F7F),
                              ),
                            ),

                            const SizedBox(height: 8),
                            InfoRow(
                              label: "Operation Type",
                              value: null,
                              isEditing: true,
                              dropdownItems: operationTypes,
                              selectedId: _selectedOperationTypeId,
                              itemAsString: (item) => item.name,
                              prefixIcon:
                                  HugeIcons.strokeRoundedShippingTruck01,
                              onDropdownChanged: (value) {
                                setState(() {
                                  _selectedOperationTypeId = value?.id;
                                  _selectedOperationTypeName = value?.name;
                                  defaultLocationSrcId =
                                      value?.defaultLocationSrcId;
                                  defaultLocationDestId =
                                      value?.defaultLocationDestId;
                                  _errorMessage = '';
                                });
                              },
                            ),
                            const SizedBox(height: 12),

                            Text(
                              'Schedule Date',
                              style: TextStyle(
                                fontWeight: FontWeight.w400,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xff7F7F7F),
                              ),
                            ),

                            const SizedBox(height: 8),
                            InfoRow(
                              label: "Scheduled Date",
                              value: null,
                              isEditing: true,
                              controller: scheduledDateController,
                              prefixIcon: HugeIcons.strokeRoundedCalendar03,
                              onTapEditing: () async {
                                final now = DateTime.now();
                                DateTime? pickedDate = await showDatePicker(
                                  context: context,
                                  initialDate: now,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (pickedDate != null && context.mounted) {
                                  TimeOfDay? pickedTime = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.now(),
                                  );
                                  if (pickedTime != null) {
                                    final combined = DateTime(
                                      pickedDate.year,
                                      pickedDate.month,
                                      pickedDate.day,
                                      pickedTime.hour,
                                      pickedTime.minute,
                                    );
                                    setState(() {
                                      scheduledDateController.text = DateFormat(
                                        'dd-MM-yyyy HH:mm:ss',
                                      ).format(combined);
                                    });
                                  }
                                }
                              },
                            ),
                            const SizedBox(height: 12),

                            Text(
                              'Source Document',
                              style: TextStyle(
                                fontWeight: FontWeight.w400,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xff7F7F7F),
                              ),
                            ),

                            const SizedBox(height: 8),
                            InfoRow(
                              label: "Source Document",
                              value: null,
                              isEditing: true,
                              controller: sourceDocController,
                              prefixIcon: HugeIcons.strokeRoundedDocumentCode,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                Container(
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
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: DefaultTabController(
                      length: 3,
                      child: Builder(
                        builder: (context) {
                          final TabController tabController =
                              DefaultTabController.of(context)!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                padding: const EdgeInsets.all(4),
                                child: TabBar(
                                  controller: tabController,
                                  indicator: BoxDecoration(
                                    color: Colors
                                        .transparent,
                                  ),
                                  dividerColor: Colors.transparent,
                                  labelPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  overlayColor: MaterialStateProperty.all(
                                    Colors.transparent,
                                  ),
                                  tabs: List.generate(3, (index) {
                                    String text;
                                    switch (index) {
                                      case 0:
                                        text = "Operations";
                                        break;
                                      case 1:
                                        text = "Additional Info";
                                        break;
                                      case 2:
                                        text = "Note";
                                        break;
                                      default:
                                        text = "";
                                    }
                                    bool isSelected =
                                        tabController.index == index;
                                    return _buildStyledTab(text, isSelected);
                                  }),
                                  onTap: (_) {
                                    (context as Element).markNeedsBuild();
                                  },
                                ),
                              ),
                              SizedBox(
                                height: 300,
                                child: TabBarView(
                                  controller: tabController,
                                  children: [
                                    ProductTable(
                                      moveProducts: moveProducts,
                                      onAddLine: _showAddProductDialog,
                                    ),
                                    AdditionalInfo(
                                      selectedShippingPolicy:
                                          _selectedShippingPolicy,
                                      onShippingPolicyChanged: (value) {
                                        setState(() {
                                          _selectedShippingPolicy = value;
                                        });
                                      },
                                      userList: users,
                                      selectedUserId: _selectedUserId,
                                      onUserChanged: (value) {
                                        setState(() {
                                          _selectedUserId = value?.id;
                                          _selectedUserName = value?.name;
                                        });
                                      },
                                    ),
                                    NotesTab(noteController: _noteController),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _createPicking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark
                          ? Colors.white
                          : AppStyle.primaryColor,
                      foregroundColor: isDark
                          ? Colors.black
                          :Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: isDark
                          ? Colors.grey[700]!
                          : Colors.grey[400]!,
                    ),
                    icon: Icon(
                      HugeIcons.strokeRoundedNoteAdd,
                      color: isDark ? Colors.black : Colors.white,
                      size: 20,
                    ),
                    label: Text(
                      "Create Picking",
                      style: TextStyle(
                        color: isDark
                            ? Colors.black
                            : Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),

                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _errorMessage,
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Builds styled tab button for the operations/additional info/note section.
  Widget _buildStyledTab(String text, bool isSelected) {
    return Tab(
      child: Container(
        width: 120,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          border: isSelected
              ? null
              : Border.all(color: Colors.grey.shade400, width: 1),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: isSelected ? Colors.white : Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// Builds a shimmer loading effect that mimics the form layout.
  Widget _buildShimmerLoading() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey[850]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Simulating "Delivery Information" container
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: List.generate(4, (index) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    children: [
                      Container(width: 24, height: 24, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(child: Container(height: 20, color: Colors.white)),
                    ],
                  ),
                )),
              ),
            ),
            const SizedBox(height: 24),
            // Simulating Tabs
            Row(
              children: List.generate(3, (index) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Container(height: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15))),
                ),
              )),
            ),
            const SizedBox(height: 16),
            // Simulating Tab Content
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 24),
            // Simulating Button
            Container(
              height: 56,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
