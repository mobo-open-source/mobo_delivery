import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../../../core/providers/motion_provider.dart';
import '../../../../shared/utils/globals.dart';
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
  /// Sets `isLoading = false` when complete.
  /// Shows error message if offline data fails to load.
  Future<void> _initializeData() async {
    final isOnline = await odooPickingFormService.checkNetworkConnectivity();
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getInt('userId') ?? 0;
    if (isOnline) {
      products = await odooService.loadProducts();
      partnerList = await odooService.loadPartners();
      users = await odooService.loadUsers();
      operationTypes = await odooService.loadOperationTypes();
    } else {
      await _loadOfflineData();
    }
    setState(() {
      isLoading = false;
    });
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
    final motionProvider = Provider.of<MotionProvider>(context, listen: false);

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
        final inputFormat = DateFormat('dd-MM-yyyy');
        final date = inputFormat.parse(rawText);
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

        for (var product in moveProducts) {
          await odooService.createStockMove(
            name: product.productName,
            productId: product.productId,
            productUomQty: product.productUomQty,
            productUomId: product.productUomId,
            pickingId: pickingId,
            locationId: locationId,
            locationDestId: locationDestId,
          );
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
              transitionDuration: motionProvider.reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              reverseTransitionDuration: motionProvider.reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    if (motionProvider.reduceMotion) return child;
                    return FadeTransition(opacity: animation, child: child);
                  },
            ),
          );
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
        body: Center(
          child: CupertinoActivityIndicator(
            radius: 40,
            color: isDark?Colors.white:AppStyle.primaryColor,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
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
                                DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime.now(),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setState(() {
                                    scheduledDateController.text = DateFormat(
                                      'dd-MM-yyyy',
                                    ).format(picked);
                                  });
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

                // Tabbed section: Operations / Additional Info / Note
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

                // Create button + error message
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
}
