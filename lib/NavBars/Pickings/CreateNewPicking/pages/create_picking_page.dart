import 'package:flutter/cupertino.dart';
import 'package:shimmer/shimmer.dart';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../../../Rating/review_service.dart';
import '../../../../shared/utils/date_picker_utils.dart';
import '../../../../shared/utils/globals.dart';
import '../../../../shared/widgets/buttons/mobo_button.dart';
import '../../../../shared/widgets/inputs/mobo_text_field.dart';
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

  final ScrollController _tabHeaderScrollController = ScrollController();
  final List<GlobalKey> _tabItemKeys = List.generate(3, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    odooService = OdooCreatePickingService(widget.url);
    _initializeData();
  }

  @override
  void dispose() {
    scheduledDateController.dispose();
    sourceDocController.dispose();
    _noteController.dispose();
    _tabHeaderScrollController.dispose();
    super.dispose();
  }

  void _ensureTabVisible(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _tabItemKeys[index];
      if (key.currentContext != null) {
        Scrollable.ensureVisible(
          key.currentContext!,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      }
    });
  }

  /// Loads dropdown data (products, partners, users, operation types) either online or from Hive cache.
  ///
  /// Online path: loads from Odoo. For any list that comes back empty (silent RPC failure),
  /// falls back to the Hive cache so the form is still usable.
  /// Offline path: loads entirely from Hive cache.
  /// Shows an error if critical dropdowns (partner + operation type) couldn't be populated at all.
  Future<void> _initializeData() async {
    try {
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
    double quantity, {
    String? imageBase64,
  }) {
    setState(() {
      moveProducts.add(
        StockMoveModel(
          productId: productId,
          productName: productName,
          productUomQty: quantity,
          productUomId: productUomId,
          quantity: quantity,
          imageBase64: imageBase64,
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

        final pickingCompanyId =
            await odooService.getPickingCompanyId(pickingId);

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
              companyId: pickingCompanyId,
            );
          } catch (e) {
            throw Exception(
              "Failed to add '${product.productName}': "
              "${e.toString().replaceFirst('Exception: ', '')}",
            );
          }
        }

        if (moveProducts.isNotEmpty) {
          try {
            await odooService.confirmPicking(
              pickingId,
              companyId: pickingCompanyId,
            );
          } catch (e) {
            if (mounted) {
              CustomSnackbar.showWarning(
                context,
                "Picking created but couldn't be confirmed: "
                "${e.toString().replaceFirst('Exception: ', '')}. "
                "Confirm it manually from the picking detail page.",
              );
            }
          }
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
              selectedProduct.cleanName,
              selectedProduct.uom_id,
              quantity,
              imageBase64: selectedProduct.imageBase64,
            );
          }
        },
      ),
    );
  }

  void _showEditProductDialog(int index) {
    final move = moveProducts[index];
    // Find the full ProductModel (with image) from the loaded list, fall back
    // to a minimal one built from the stored move data.
    final existing = products.cast<ProductModel?>().firstWhere(
      (p) => p?.id == move.productId,
      orElse: () => null,
    );
    final initial = existing ??
        ProductModel(
          id: move.productId,
          name: move.productName,
          uom_id: 0,
          imageBase64: move.imageBase64,
        );

    showDialog(
      context: context,
      builder: (context) => AddProductDialog(
        products: products,
        initialProduct: initial,
        initialQuantity: move.productUomQty,
        onAdd: (selectedProduct, quantity) {
          if (selectedProduct != null && quantity > 0) {
            setState(() {
              moveProducts[index] = StockMoveModel(
                productId: selectedProduct.id,
                productName: selectedProduct.cleanName,
                productUomQty: quantity,
                productUomId: selectedProduct.uom_id,
                quantity: quantity,
                imageBase64: selectedProduct.imageBase64,
              );
            });
          }
        },
      ),
    );
  }

  void _deleteProduct(int index) {
    setState(() => moveProducts.removeAt(index));
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
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: TextButton(
            onPressed: (!isLoading &&
                    _selectedPartnerId != null &&
                    _selectedOperationTypeId != null)
                ? _createPicking
                : null,
            style: TextButton.styleFrom(
              backgroundColor: AppStyle.primaryColor,
              disabledBackgroundColor: Colors.grey[400],
              disabledForegroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(13),
            ),
            child: const Text(
              'Create Picking',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: SingleChildScrollView(
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
                            ? Colors.black.withValues(alpha: 0.18)
                            : Colors.black.withValues(alpha: 0.06),
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
                            fontSize: 16,
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
                            RequiredLabel(
                              'Delivery Address',
                              isRequired: true,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xff7F7F7F),
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

                            RequiredLabel(
                              'Operation Type',
                              isRequired: true,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xff7F7F7F),
                            ),

                            const SizedBox(height: 8),
                            InfoRow(
                              label: "Operation Type",
                              value: null,
                              isEditing: true,
                              dropdownItems: operationTypes,
                              selectedId: _selectedOperationTypeId,
                              itemAsString: (item) => item.name,
                              prefixIcon: HugeIcons.strokeRoundedExchange01,
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
                                fontWeight: FontWeight.w500,
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
                                DateTime? pickedDate =
                                    await DatePickerUtils.showStandardDatePicker(
                                  context: context,
                                  initialDate: now,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (pickedDate != null && context.mounted) {
                                  TimeOfDay? pickedTime =
                                      await DatePickerUtils.showStandardTimePicker(
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
                                fontWeight: FontWeight.w500,
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
                              margin: const EdgeInsets.only(bottom: 12),
                              height: 40,
                                child: ListView.separated(
                                  controller: _tabHeaderScrollController,
                                  scrollDirection: Axis.horizontal,
                                  physics: const ClampingScrollPhysics(),
                                  itemCount: 3,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    const labels = [
                                      'Operations',
                                      'Additional Info',
                                      'Note',
                                    ];
                                    return ListenableBuilder(
                                      listenable: tabController,
                                      builder: (context, _) {
                                        return GestureDetector(
                                          key: _tabItemKeys[index],
                                          onTap: () {
                                            tabController.animateTo(index);
                                            _ensureTabVisible(index);
                                          },
                                          child: _buildPillTab(
                                            label: labels[index],
                                            isSelected:
                                                tabController.index == index,
                                            isDark: isDark,
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                              Container(
                                width: double.infinity,
                                constraints:
                                    const BoxConstraints(minHeight: 240),
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color:
                                      isDark ? Colors.grey[850] : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isDark
                                          ? Colors.black.withValues(alpha: 0.18)
                                          : Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                // Swipe the body to move to the adjacent section.
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onHorizontalDragEnd: (details) {
                                    final v = details.primaryVelocity ?? 0;
                                    if (v < -250 && tabController.index < 2) {
                                      final next = tabController.index + 1;
                                      tabController.animateTo(next);
                                      _ensureTabVisible(next);
                                    } else if (v > 250 &&
                                        tabController.index > 0) {
                                      final prev = tabController.index - 1;
                                      tabController.animateTo(prev);
                                      _ensureTabVisible(prev);
                                    }
                                  },
                                  child: AnimatedBuilder(
                                    animation: tabController.animation!,
                                    builder: (context, _) {
                                      switch (tabController.index) {
                                        case 1:
                                          return AdditionalInfo(
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
                                          );
                                        case 2:
                                          return NotesTab(
                                            noteController: _noteController,
                                          );
                                        default:
                                          return ProductTable(
                                            moveProducts: moveProducts,
                                            onAddLine: _showAddProductDialog,
                                            onEdit: _showEditProductDialog,
                                            onDelete: _deleteProduct,
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

                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _errorMessage,
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
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

  Widget _buildPillTab({
    required String label,
    required bool isSelected,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.black
            : (isDark ? Colors.grey[800] : Colors.white),
        border: Border.all(
          color: isSelected
              ? Colors.black
              : (isDark ? Colors.grey[600]! : Colors.grey[300]!),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: TextStyle(
          color: isSelected
              ? Colors.white
              : (isDark ? Colors.grey[400] : Colors.grey[700]),
          fontSize: 15,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
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
            Row(
              children: List.generate(3, (index) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Container(height: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))),
                ),
              )),
            ),
            const SizedBox(height: 16),
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            const SizedBox(height: 24),
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
