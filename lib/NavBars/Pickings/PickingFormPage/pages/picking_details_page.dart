import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive/hive.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/company/session/company_session_manager.dart';
import '../../../../core/navigation/data_loss_warning_dialog.dart';
import '../../../../core/providers/motion_provider.dart';
import '../../../../shared/utils/globals.dart';
import '../../../../shared/widgets/snackbar.dart';
import '../../../OfflineSync/services/odoo_offline_service.dart';
import '../../../OfflineSync/services/offline_sync_service.dart';
import '../models/move_line.dart';
import '../models/partner_details.dart';
import '../models/return_picking.dart';
import '../services/hive_service.dart';
import '../models/picking_form.dart';
import '../models/product.dart';
import '../models/partner.dart';
import '../models/user.dart';
import '../models/stock_move.dart';
import '../services/odoo_picking_form_service.dart';
import '../widgets/info_row.dart';
import 'stock_move_line_list_page.dart';
import 'return_list_page.dart';
import 'package:intl/intl.dart';

/// Detailed view & edit screen for one stock picking / transfer in Odoo
///
/// Supports:
/// • Online & offline mode (with Hive caching + pending sync queue)
/// • View picking header, partner info, status, move lines
/// • Edit basic fields (partner, scheduled date, origin, note, responsible…)
/// • Validate / Cancel / Mark as Todo / Check Availability
/// • Add / edit / delete individual stock moves
/// • Show returns (if any)
/// • Offline queuing of validations, cancellations, updates, new lines
///
/// Uses heavy Hive usage for offline resilience + periodic network checks.
class PickingDetailsPage extends StatefulWidget {
  final Map<String, dynamic> picking;
  final OdooPickingFormService odooService;
  final bool isPickingForm;
  final bool isReturnPicking;
  final bool isReturnCreate;

  const PickingDetailsPage({
    Key? key,
    required this.picking,
    required this.odooService,
    this.isPickingForm = false,
    this.isReturnPicking = false,
    this.isReturnCreate = false,
  }) : super(key: key);

  @override
  State<PickingDetailsPage> createState() => _PickingDetailsPageState();
}

class _PickingDetailsPageState extends State<PickingDetailsPage> {
  // ───────────────────────────────────────────────
  //  Core data lists (loaded either online or from Hive)
  // ───────────────────────────────────────────────
  List<PickingForm> pickings = [];
  List<Product> products = [];
  List<Partner> partnerList = [];
  List<User> userList = [];
  List<StockMove> moveProducts = [];

  // Raw data containers (often used before parsing to models)
  List<Map<String, dynamic>> pickingStockLine = [];
  List<Map<String, dynamic>> returnDataList = [];

  String _errorMessage = '';
  bool isDataAvailable = true;
  bool _isEditing = false;

  // Selection & temporary state
  int? selectedPartnerId;
  int? selectedPicking;
  int? selectedPickingUom;
  String? selectedPickingName;
  String _selectedShippingPolicy = 'direct';
  int? _selectedUserId;

  bool isSaving = false;
  bool isDataFromHive = false;
  bool _isLoading = false;
  final HiveService _hiveService = HiveService();

  // Form controllers
  final TextEditingController deliveryAddressController =
      TextEditingController();
  final TextEditingController operationTypeController = TextEditingController();
  final TextEditingController scheduledDateController = TextEditingController();
  final TextEditingController deadlineController = TextEditingController();
  final TextEditingController dateDoneController = TextEditingController();
  final TextEditingController availabilityController = TextEditingController();
  final TextEditingController sourceDocController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  bool isOfflineValidate = false;
  bool isOfflineCancel = false;
  bool isOnlineAvailability = false;
  bool isCreateSaving = false;
  Map<String, dynamic>? partnerDetails;
  Timer? _networkTimer;
  Uint8List? _cachedImage;

  @override
  void initState() {
    super.initState();
    _startNetworkCheck();
    _initializeHive();
    _fetchData();
  }

  @override
  void dispose() {
    _networkTimer?.cancel();
    super.dispose();
  }

  /// Starts periodic network availability check (every 2 seconds)
  /// Updates `isOnlineAvailability` flag used across the page.
  void _startNetworkCheck() {
    _checkNetwork();

    _networkTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkNetwork();
    });
  }

  /// Checks connectivity to Odoo server and updates UI state
  Future<void> _checkNetwork() async {
    final odooPickingFormService = OdooPickingFormService();
    await odooPickingFormService.initializeOdooClient();
    final availability = await odooPickingFormService
        .checkNetworkConnectivity();
    if (mounted) {
      setState(() {
        isOnlineAvailability = availability;
      });
    }
  }

  Future<void> _initializeHive() async {
    final odooPickingFormService = OdooPickingFormService();
    await odooPickingFormService.initializeOdooClient();
    await _hiveService.initialize();
  }

  /// Main data loading decision point:
  ///   1. Checks if we have offline data in Hive
  ///   2. If online → also load fresh data from Odoo
  ///   3. Sets loading flags & error states
  Future<void> _fetchData() async {
    final odooPickingFormService = OdooPickingFormService();
    await odooPickingFormService.initializeOdooClient();
    setState(() {
      isDataAvailable = true;
    });
    final isOnline = await odooPickingFormService.checkNetworkConnectivity();
    setState(() {
      isDataFromHive = !isOnline;
    });

    // Check if this picking has pending validation / cancellation
    final syncService = OfflineSyncService(
      HiveService(),
      OdooOfflineSyncService(),
    );
    final pendingValidations = await syncService.getPendingValidations();
    final pendingCancellations = await syncService.getPendingCancellation();
    final pickingId = int.parse(widget.picking['id'].toString());

    final isCancel = pendingCancellations.any(
      (pending) => pending['pickingId'] == pickingId,
    );
    final isPending = pendingValidations.any(
      (pending) => pending['pickingId'] == pickingId,
    );
    setState(() {
      isOfflineValidate = isPending;
      isOfflineCancel = isCancel;
    });
    final hasOfflineData = await _loadOfflineData();

    if (hasOfflineData) {
      setState(() {
        isDataAvailable = false;
      });
    }

    if (isOnline) await _loadOnlineData();

    setState(() {
      isDataAvailable = false;
    });
  }

  Future<void> _loadSavingData() async {
    final odooPickingFormService = OdooPickingFormService();
    await odooPickingFormService.initializeOdooClient();
    final pickingId = int.parse(widget.picking['id'].toString());
    pickings = await odooPickingFormService.loadPickings(pickingId);
    partnerDetails = await odooPickingFormService.loadPartnerDetails(
      pickings[0].partnerId?[0],
    );
    final imageString = partnerDetails?['image_1920'];
    if (imageString != null && imageString.isNotEmpty) {
      setState(() {
        _cachedImage = base64Decode(imageString);
      });
    } else {
      setState(() {
        _cachedImage = null;
      });
    }
    moveProducts = await odooPickingFormService.loadProductMoves(pickingId);
    setState(() {});
  }

  // ───────────────────────────────────────────────
  //                ONLINE FLOW
  // ───────────────────────────────────────────────

  /// Loads fresh data from Odoo + caches partner image & details to Hive
  Future<void> _loadOnlineData() async {
    final odooPickingFormService = OdooPickingFormService();
    await odooPickingFormService.initializeOdooClient();
    final pickingId = int.parse(widget.picking['id'].toString());
    pickings = await odooPickingFormService.loadPickings(pickingId);
    products = await odooPickingFormService.loadProducts();
    partnerList = await odooPickingFormService.loadPartners();
    partnerDetails = await odooPickingFormService.loadPartnerDetails(
      pickings[0].partnerId?[0],
    );
    final imageString = partnerDetails?['image_1920'];
    if (imageString != null && imageString.isNotEmpty) {
      _cachedImage = base64Decode(imageString);
    }

    final partnerDetailModel = PartnerDetails(
      id: pickings[0].partnerId?[0] ?? 0,
      address: partnerDetails?['address'],
      imageBase64: partnerDetails?['image_1920'],
    );

    await _hiveService.savePartnerDetails(partnerDetailModel);

    userList = await odooPickingFormService.loadUsers();
    moveProducts = await odooPickingFormService.loadProductMoves(pickingId);
    setState(() {});
  }

  /// ───────────────────────────────────────────────
  ///                OFFLINE FLOW
  /// ───────────────────────────────────────────────

  /// Loads all necessary data from Hive when offline or as fallback
  /// Returns true if at least picking header was found
  Future<bool> _loadOfflineData() async {
    try {
      final pickingId = int.parse(widget.picking['id'].toString());

      final picking = await _hiveService.getPickingById(pickingId);
      if (picking != null) {
        setState(() {
          pickings = [picking];
        });
      }
      final productsData = await _hiveService.getProducts();
      final partnersData = await _hiveService.getPartners();
      final usersData = await _hiveService.getUsers();
      final movesData = await _hiveService.getStockMoves(pickingId: pickingId);
      final partnerId = pickings[0].partnerId?[0];
      if (partnerId != null) {
        final offlinePartnerDetails = await _hiveService.getPartnerDetails(
          partnerId,
        );
        if (offlinePartnerDetails != null) {
          setState(() {
            partnerDetails = offlinePartnerDetails.toJson();
            if (offlinePartnerDetails.imageBase64 != null &&
                offlinePartnerDetails.imageBase64!.isNotEmpty) {
              _cachedImage = base64Decode(offlinePartnerDetails.imageBase64!);
            }
          });
        }
      }
      setState(() {
        products = productsData;
        partnerList = partnersData;
        userList = usersData;
        moveProducts = movesData;
      });
      return true;
    } catch (e) {
      setState(() {
        _errorMessage = "Failed to load offline data.";
      });
      return false;
    }
  }

  /// Returns color for scheduled / deadline date (red = overdue, amber = today)
  Color getScheduledDateColor(String dateString) {
    try {
      final now = DateTime.now();
      final scheduled = DateTime.parse(dateString);
      final today = DateTime(now.year, now.month, now.day);
      final scheduledDay = DateTime(
        scheduled.year,
        scheduled.month,
        scheduled.day,
      );
      if (scheduledDay.isBefore(today)) {
        return Colors.red;
      } else if (scheduledDay.isAtSameMomentAs(today)) {
        return Colors.amber[900]!;
      } else {
        return Colors.black;
      }
    } catch (_) {
      return Colors.grey;
    }
  }

  // ───────────────────────────────────────────────
  //                ACTIONS – VALIDATE / CANCEL / ...
  // ───────────────────────────────────────────────

  /// Validates the picking (online → immediate, offline → queue)
  /// Prevents validation if empty or no quantities reserved
  Future<void> _validatePicking() async {
    if (moveProducts.isEmpty) {
      CustomSnackbar.showWarning(
        context,
        'You can’t validate an empty transfer. Please add some products to move before proceeding.',
      );

      return;
    }
    bool hasZeroQuantity = moveProducts.any((product) => product.quantity == 0);
    if (hasZeroQuantity) {
      CustomSnackbar.showWarning(
        context,
        'You cannot validate a transfer if no quantities are reserved. To force the transfer, encode quantities.',
      );

      return;
    }
    final odooPickingFormService = OdooPickingFormService();
    await odooPickingFormService.initializeOdooClient();
    setState(() => isSaving = true);
    final pickingId = int.parse(widget.picking['id'].toString());
    final isOnline = await odooPickingFormService.checkNetworkConnectivity();
    if (isOnline) {
      final success = await odooPickingFormService.validatePicking(pickingId);
      if (success == true) {
        await _loadSavingData();
        setState(() => isSaving = false);
      } else if (success is Map && success['name'] == 'Create Backorder?') {
        await _showBackorderDialog(pickingId, success);
        setState(() => isSaving = false);
      } else {
        setState(() {
          isSaving = false;
          _errorMessage = "Failed to validate picking.";
        });
      }
    } else {
      try {
        final pickingData = pickings.firstWhere((p) => p.id == pickingId);
        pickingData.state = 'draft';
        await _hiveService.savePendingValidation(
          pickingId,
          pickingData.toJson(),
        );
        await _hiveService.savePickings([pickingData.toJson()]);
        setState(() {
          pickings = [pickingData];
          isSaving = false;
          isOfflineValidate = true;
        });
        CustomSnackbar.showWarning(
          context,
          'Validation queued for sync when online.',
        );
      } catch (e) {
        setState(() {
          _errorMessage = "Failed to queue validation.";
        });
      }
    }
  }

  /// Cancels the picking (online → immediate, offline → queue)
  Future<void> _cancelPicking() async {
    final odooPickingFormService = OdooPickingFormService();
    await odooPickingFormService.initializeOdooClient();
    setState(() => isSaving = true);
    final pickingId = int.parse(widget.picking['id'].toString());
    final isOnline = await odooPickingFormService.checkNetworkConnectivity();
    if (isOnline) {
      final success = await odooPickingFormService.cancelPicking(pickingId);
      if (success) {
        await _loadSavingData();
        setState(() => isSaving = false);
      } else {
        setState(() {
          isSaving = false;
          _errorMessage = "Failed to cancel picking.";
        });
      }
    } else {
      try {
        final pickingData = pickings.firstWhere((p) => p.id == pickingId);
        pickingData.state = 'cancel';
        await _hiveService.savePendingCancellation(
          pickingId,
          pickingData.toJson(),
        );
        await _hiveService.savePickings([pickingData.toJson()]);
        setState(() {
          pickings = [pickingData];
          isSaving = false;
          isOfflineCancel = true;
        });
        CustomSnackbar.showWarning(
          context,
          'Cancellation queued for sync when online.',
        );
      } catch (e) {
        setState(() {
          _errorMessage = "Failed to queue cancellation.";
          isSaving = false;
        });
      }
    }
  }

  /// Loads & navigates to detailed move lines (uses Hive cache when offline)
  Future<void> _stockMoveLine() async {
    setState(() {
      isSaving = true;
    });
    final motionProvider = Provider.of<MotionProvider>(context, listen: false);

    final odooPickingFormService = OdooPickingFormService();
    await odooPickingFormService.initializeOdooClient();
    final pickingId = int.parse(widget.picking['id'].toString());

    final box = await Hive.openBox<MoveLine>('move_lines');

    if (!isOnlineAvailability) {
      final cachedLines = box.values
          .where((line) => line.pickingId == pickingId)
          .map((line) => line.toJson())
          .toList();

      if (cachedLines.isNotEmpty) {
        setState(() {
          pickingStockLine = cachedLines;
          isSaving = false;
        });
      }
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              StockMoveLineListPage(pickingStockLine: pickingStockLine),
          transitionDuration: motionProvider.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 300),
          reverseTransitionDuration: motionProvider.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 300),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (motionProvider.reduceMotion) return child;
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      final cachedLines = box.values
          .where((line) => line.pickingId == pickingId)
          .map((line) => line.toJson())
          .toList();

      if (cachedLines.isNotEmpty) {
        setState(() {
          pickingStockLine = cachedLines;
          isSaving = false;
        });
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                StockMoveLineListPage(pickingStockLine: pickingStockLine),
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

        final moveLines = await odooPickingFormService.loadStockMoveLines(
          pickingId,
        );
        for (var line in moveLines) {
          final moveLine = MoveLine(
            id: line['id'] ?? 0,
            pickingId: pickingId,
            data: line,
          );
          await box.put('${pickingId}_${line['id'] ?? 0}', moveLine);
        }

        setState(() {
          pickingStockLine = moveLines;
          isSaving = false;
        });
      } else {
        final moveLines = await odooPickingFormService.loadStockMoveLines(
          pickingId,
        );
        for (var line in moveLines) {
          final moveLine = MoveLine(
            id: line['id'] ?? 0,
            pickingId: pickingId,
            data: line,
          );
          await box.put('${pickingId}_${line['id'] ?? 0}', moveLine);
        }

        setState(() {
          pickingStockLine = moveLines;
          isSaving = false;
        });
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                StockMoveLineListPage(pickingStockLine: pickingStockLine),
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
      }
    }
    setState(() {
      isSaving = false;
    });
  }

  /// Checks product availability for the current picking and refreshes data if successful.
  ///
  /// Calls Odoo's `stock.picking` → `action_assign()` equivalent (reserves stock).
  /// On success: reloads the full picking details (moves, state, etc.).
  /// On failure: sets an error message visible in the UI.
  /// Does **not** support offline queuing — availability check requires server connection.
  Future<void> _showAvailability() async {
    final odooPickingFormService = OdooPickingFormService();
    await odooPickingFormService.initializeOdooClient();
    final pickingId = int.parse(widget.picking['id'].toString());
    final success = await odooPickingFormService.checkAvailability(pickingId);
    if (success) {
      await _loadSavingData();
    } else {
      setState(() {
        _errorMessage = "Failed to check availability.";
      });
    }
  }

  /// Marks the picking as "To Do" (confirmed/ready state in Odoo).
  ///
  /// Typically called when the picking is in draft → moves it to confirmed/assigned.
  /// On success: reloads fresh picking data and clears loading state.
  /// On failure: shows error message and resets loading indicator.
  /// This action is **online only** — no offline fallback is implemented here.
  Future<void> _markAsTodoPicking() async {
    final odooPickingFormService = OdooPickingFormService();
    await odooPickingFormService.initializeOdooClient();
    setState(() => isSaving = true);
    final pickingId = int.parse(widget.picking['id'].toString());
    final success = await odooPickingFormService.markAsTodoPicking(pickingId);
    if (success) {
      await _loadSavingData();
      setState(() => isSaving = false);
    } else {
      setState(() {
        isSaving = false;
        _errorMessage = "Failed to mark as todo.";
      });
    }
  }

  /// Loads and navigates to the list of return pickings (reverse transfers) for this picking.
  ///
  /// Behavior:
  /// - Online: fetches fresh return data from Odoo → caches each return in Hive
  /// - Offline: uses cached returns from Hive 'return_pickings' box
  ///
  /// After loading data (cached or fresh), navigates to `ReturnListPage` with a smooth
  /// fade transition (motion-reduced if user preference is set).
  ///
  /// Caches use pickingId as key — overwrites previous returns for same picking.
  /// Shows loading overlay (`isSaving`) during fetch/navigation.
  Future<void> _returnPicking() async {
    setState(() {
      isSaving = true;
    });

    final motionProvider = Provider.of<MotionProvider>(context, listen: false);
    final odooPickingFormService = OdooPickingFormService();
    await odooPickingFormService.initializeOdooClient();

    final pickingId = int.parse(widget.picking['id'].toString());
    final box = await Hive.openBox<ReturnPicking>('return_pickings');

    if (!isOnlineAvailability) {
      final cachedReturns = box.values
          .where((item) => item.pickingId == pickingId)
          .toList();

      if (cachedReturns.isNotEmpty) {
        List<Map<String, dynamic>> loadedReturnData = cachedReturns
            .map((e) => e.data)
            .toList();
        setState(() {
          returnDataList = loadedReturnData;
          isSaving = false;
        });
      }
    } else {
      final returnData = await odooPickingFormService.loadReturnPickings(
        pickingId,
      );
      for (var data in returnData) {
        final partner = data['partner_id'] as List<dynamic>? ?? [0, ''];
        final returnPicking = ReturnPicking(
          id: data['id'] ?? 0,
          pickingId: pickingId,
          name: data['name'] ?? '',
          partnerId: partner.isNotEmpty ? partner[0] : 0,
          scheduledDate: data['scheduled_date'] ?? '',
          origin: data['origin'] ?? '',
          state: data['state'] ?? '',
          data: data,
        );
        await box.put('${pickingId}', returnPicking);
      }

      setState(() {
        returnDataList = returnData;
        isSaving = false;
      });
    }

    setState(() {
      isSaving = false;
    });

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => ReturnListPage(
          returnDataList: returnDataList,
          odooService: odooPickingFormService,
        ),
        transitionDuration: motionProvider.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 300),
        reverseTransitionDuration: motionProvider.reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (motionProvider.reduceMotion) return child;
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  /// Saves edited picking header fields (online → Odoo, offline → Hive queue)
  Future<void> _saveChanges(
    Map<String, dynamic> listOfUpdates,
    String title,
  ) async {
    final odooPickingFormService = OdooPickingFormService();
    await odooPickingFormService.initializeOdooClient();
    setState(() => isSaving = true);
    final pickingId = int.parse(widget.picking['id'].toString());
    String? selectedPartnerName;
    if (selectedPartnerId != null) {
      final selectedPartner = partnerList.firstWhere(
        (partner) => partner.id == selectedPartnerId,
        orElse: () => Partner(id: 0, name: 'Unknown'),
      );
      selectedPartnerName = selectedPartner.name;
    }

    String? selectedUserName;
    if (_selectedUserId != null) {
      final selectedUser = userList.firstWhere(
        (user) => user.id == _selectedUserId,
        orElse: () => User(id: 0, name: 'Unknown'),
      );
      selectedUserName = selectedUser.name;
    }
    final updatedListOfUpdates = {...listOfUpdates};

    final isOnline = await odooPickingFormService.checkNetworkConnectivity();
    if (isOnline) {
      final success = await odooPickingFormService.saveChanges(
        pickingId,
        updatedListOfUpdates,
      );
      if (success) {
        await _loadSavingData();
        setState(() {
          _isEditing = false;
          isSaving = false;
        });
      } else {
        await _hiveService.savePendingUpdates(pickingId, {
          'title': title,
          'partner_name': selectedPartnerName,
          'user_name': selectedUserName,
          'updates': updatedListOfUpdates,
        });
        setState(() {
          isSaving = false;
          _isEditing = false;
          _errorMessage = "Changes saved offline. Will sync when online.";
        });
      }
    } else {
      await _hiveService.savePendingUpdates(pickingId, {
        'title': title,
        'partner_name': selectedPartnerName,
        'user_name': selectedUserName,
        'updates': updatedListOfUpdates,
      });
      setState(() {
        isSaving = false;
        _isEditing = false;
        _errorMessage = "Changes saved offline. Will sync when online.";
      });
    }
  }

  Future<void> _showBackorderDialog(int pickingId, success) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Create Backorder?'),
        content: const Text(
          'Some products are not fully available. Would you like to create a backorder for the remaining quantities or validate without a backorder?',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final odooPickingFormService = OdooPickingFormService();
              await odooPickingFormService.initializeOdooClient();
              try {
                await CompanySessionManager.callKwWithCompany({
                  'model': 'stock.backorder.confirmation',
                  'method': 'process_cancel_backorder',
                  'args': [success['context']['active_ids'] ?? []],
                  'kwargs': {'context': success['context']},
                });
                await _loadSavingData();
                setState(() => isSaving = false);
                Navigator.of(context).pop();
                CustomSnackbar.showWarning(
                  context,
                  'Picking validated without backorder.',
                );
              } catch (e) {
                setState(() {
                  isSaving = false;
                  _errorMessage = "Failed to validate without backorder.";
                });
                CustomSnackbar.showError(context, _errorMessage);
              }
            },

            child: const Text('No Backorder'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final odooPickingFormService = OdooPickingFormService();
              await odooPickingFormService.initializeOdooClient();
              try {
                await CompanySessionManager.callKwWithCompany({
                  'model': 'stock.backorder.confirmation',
                  'method': 'process',
                  'args': [success['context']['button_validate_picking_ids']],
                  'kwargs': {'context': success['context']},
                });
                await _loadSavingData();
                setState(() => isSaving = false);
                Navigator.of(context).pop();
                CustomSnackbar.showSuccess(
                  context,
                  'Backorder created successfully.',
                );
              } catch (e) {
                setState(() {
                  isSaving = false;
                  _errorMessage = "Failed to create backorder.";
                });
                CustomSnackbar.showError(context, _errorMessage);
              }
            },
            child: const Text('Create Backorder'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String formatToOdooDatetime(String isoString) {
    try {
      DateTime parsed = DateTime.parse(isoString);
      return DateFormat("yyyy-MM-dd HH:mm:ss").format(parsed);
    } catch (e) {
      return isoString;
    }
  }

  /// Builds nice looking status badge (Draft, Ready, Done, Cancelled…)
  Widget _buildStatusIndicator(String status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color getStatusColor(String status) {
      switch (status.toLowerCase()) {
        case 'draft':
          return isDark ? Colors.white : Colors.black54;
        case 'waiting':
          return isDark ? Colors.white : Colors.black54;
        case 'confirmed':
          return isDark ? Colors.white : Colors.black54;
        case 'assigned':
          return isDark ? Colors.white : Colors.black54;
        case 'done':
          return isDark ? Colors.white : Colors.black54;
        case 'cancel':
          return isDark ? Colors.white : Colors.black54;
        default:
          return Colors.grey;
      }
    }

    String getStatusText(String status) {
      switch (status.toLowerCase()) {
        case 'draft':
          return 'DRAFT';
        case 'waiting':
          return 'WAITING ANOTHER OPERATION';
        case 'confirmed':
          return 'WAITING';
        case 'assigned':
          return 'READY';
        case 'done':
          return 'DONE';
        case 'cancel':
          return 'CANCELLED';
        default:
          return status.toUpperCase();
      }
    }

    final statusColor = getStatusColor(status);
    final statusText = getStatusText(status);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[800] : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getStatusIcon(status.toLowerCase()),
                color: statusColor,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'draft':
        return HugeIcons.strokeRoundedLicenseDraft;
      case 'waiting':
        return HugeIcons.strokeRoundedAlertCircle;
      case 'confirmed':
        return HugeIcons.strokeRoundedCheckmarkCircle03;
      case 'assigned':
        return HugeIcons.strokeRoundedTask01;
      case 'done':
        return HugeIcons.strokeRoundedNoteDone;
      case 'cancel':
        return HugeIcons.strokeRoundedCancelCircle;
      default:
        return HugeIcons.strokeRoundedAlertCircle;
    }
  }

  // ───────────────────────────────────────────────
  //                BUILD & UI LOGIC
  // ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: _handleBackNavigation,
      child: Stack(
        children: [
          if (isDataAvailable) ...[
            Scaffold(
              backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],

              appBar: AppBar(
                backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
                title: Text(
                  widget.picking['item'] ?? "Loading Pickings...",
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
                  onPressed: isSaving
                      ? null
                      : () async {
                          final canPop = await _handleBackNavigation();
                          if (canPop && context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                ),
              ),
              body: ListView.builder(
                itemCount: 6,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Shimmer.fromColors(
                      baseColor: isDark ? Color(0xFF2A2A2A) : Colors.grey[300]!,
                      highlightColor: Colors.grey.shade100,
                      child: Container(
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ] else if (pickings.isEmpty) ...[
            Scaffold(
              backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],

              appBar: AppBar(
                backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
                title: Text(
                  widget.picking['item'] ?? "No Picking Data",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                leading: IconButton(
                  icon: Icon(
                    HugeIcons.strokeRoundedArrowLeft01,
                    color: isDark ? Colors.white : Colors.black,
                    size: 28,
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          final canPop = await _handleBackNavigation();
                          if (canPop && context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                ),
              ),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      HugeIcons.strokeRoundedTruck,
                      color: isDark ? Colors.white : AppStyle.primaryColor,
                      size: 80,
                    ),
                    SizedBox(height: 20),
                    Text(
                      "No picking details available.",
                      style: TextStyle(
                        fontSize: 18,
                        color: isDark ? Colors.white : AppStyle.primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Scaffold(
              backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],

              appBar: AppBar(
                backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
                title: Text(
                  _isEditing
                      ? 'Edit ${widget.picking['item'] ?? widget.picking['name']}'
                      : (widget.picking['item'] ??
                            widget.picking['name'] ??
                            'Picking Details'),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                leading: IconButton(
                  icon: Icon(
                    HugeIcons.strokeRoundedArrowLeft01,
                    color: isDark ? Colors.white : Colors.black,
                    size: 28,
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          final canPop = await _handleBackNavigation();
                          if (canPop && context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                ),
                actions: [
                  if (!_isEditing) ...[
                    if (pickings.isNotEmpty &&
                        !['done', 'cancel'].contains(pickings[0].state)) ...[
                      IconButton(
                        onPressed: () async {
                          setState(() {
                            _isEditing = true;
                          });
                        },
                        tooltip: 'Edit Picking',
                        icon: Icon(
                          HugeIcons.strokeRoundedPencilEdit02,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                    if ([
                      'draft',
                      'confirmed',
                      'assigned',
                    ].contains(pickings[0].state))
                      if (!isOfflineValidate && !isOfflineCancel)
                        PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            size: 20,
                          ),
                          color: isDark ? Colors.grey[900] : Colors.white,
                          elevation: 8,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          itemBuilder: (context) {
                            List<PopupMenuEntry<String>> items = [];

                            if (pickings[0].state == 'draft' &&
                                isOnlineAvailability) {
                              items.add(
                                PopupMenuItem(
                                  value: 'mark_as_todo',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.task_alt,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black54,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        "Mark as Todo",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            if (pickings[0].showCheckAvailability &&
                                isOnlineAvailability) {
                              items.add(
                                PopupMenuItem(
                                  value: 'check_availability',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.search,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black54,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        "Check Availability",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            items.addAll([
                              PopupMenuItem(
                                value: 'validate',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black54,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      "Validate",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'cancel',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.cancel_outlined,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black54,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      "Cancel",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ]);

                            return items;
                          },
                          onSelected: (value) async {
                            switch (value) {
                              case 'mark_as_todo':
                                _markAsTodoPicking();
                                break;
                              case 'check_availability':
                                _showAvailability();
                                break;
                              case 'validate':
                                _validatePicking();
                                break;
                              case 'cancel':
                                _cancelPicking();
                                break;
                            }
                          },
                        ),
                  ],
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isOfflineValidate)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "This picking was validated while offline. Please sync it from the Offline Sync page.",
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    if (isOfflineCancel)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "This picking was cancelled while offline. Please sync it from the Offline Sync page.",
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    const SizedBox(height: 16),
                    if (pickings[0].partnerId != null) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 0),
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
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _cachedImage != null
                                        ? ClipOval(
                                            child: Image.memory(
                                              _cachedImage!,
                                              width: 40,
                                              height: 40,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        : Icon(
                                            Icons.person,
                                            color: isDark
                                                ? Colors.white
                                                : AppStyle.primaryColor,
                                            size: 40,
                                          ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            pickings[0].partnerId?[1] ??
                                                'Unknown',
                                            style: TextStyle(
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            partnerDetails?['address'] ??
                                                'No address available',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: isDark
                                                  ? Colors.white60
                                                  : Colors.black54,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          _buildStatusIndicator(
                                            pickings[0].state,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 32),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 70,
                            child: ElevatedButton.icon(
                              onPressed: _stockMoveLine,
                              icon: const Icon(Icons.list_alt),
                              label: Text(
                                "Detailed Operations",
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? Colors.white
                                      : AppStyle.primaryColor,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark
                                    ? Colors.grey[850]
                                    : Colors.white,
                                foregroundColor: isDark
                                    ? Colors.white
                                    : AppStyle.primaryColor,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: BorderSide(
                                    color: isDark
                                        ? Colors.white
                                        : AppStyle.primaryColor.withOpacity(
                                            0.7,
                                          ),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (pickings[0].returnCount > 0) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: SizedBox(
                              height: 70,
                              child: ElevatedButton.icon(
                                onPressed: _returnPicking,
                                icon: const Icon(Icons.keyboard_return),
                                label: Text(
                                  "Return (${pickings[0].returnCount})",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? Colors.white
                                        : AppStyle.primaryColor,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isDark
                                      ? Colors.grey[850]
                                      : Colors.white,
                                  foregroundColor: isDark
                                      ? Colors.white
                                      : AppStyle.primaryColor,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(
                                      color: isDark
                                          ? Colors.white
                                          : AppStyle.primaryColor.withOpacity(
                                              0.7,
                                            ),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 24),
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
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              "Delivery Details",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Column(
                                children: [
                                  InfoRow(
                                    label: "Delivery Address",
                                    value: pickings[0].partnerId,
                                    isEditing: _isEditing,
                                    prefixIcon: FontAwesomeIcons.locationDot,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    dropdownItems: partnerList
                                        .map((p) => p.toJson())
                                        .toList(),
                                    selectedId:
                                        selectedPartnerId ??
                                        (pickings[0].partnerId?.isNotEmpty ??
                                                false
                                            ? pickings[0].partnerId![0]
                                            : null),
                                    onDropdownChanged: (value) {
                                      setState(() {
                                        selectedPartnerId = value?['id'];
                                      });
                                    },
                                  ),

                                  InfoRow(
                                    label: "Operation Type",
                                    value: pickings[0].pickingTypeId,
                                    isEditing: false,
                                    controller: operationTypeController,
                                    prefixIcon: FontAwesomeIcons.tasks,
                                  ),
                                  InfoRow(
                                    label: "Scheduled Date",
                                    value: pickings[0].scheduledDate,
                                    isEditing: _isEditing,
                                    controller: scheduledDateController,
                                    color: getScheduledDateColor(
                                      pickings[0].scheduledDate ??
                                          DateTime.now().toString(),
                                    ),
                                    prefixIcon: FontAwesomeIcons.calendarAlt,
                                    onTapEditing: () async {
                                      DateTime? picked = await showDatePicker(
                                        context: context,
                                        initialDate:
                                            DateTime.tryParse(
                                              pickings[0].scheduledDate ?? '',
                                            ) ??
                                            DateTime.now(),
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime(2100),
                                      );
                                      if (picked != null) {
                                        setState(() {
                                          scheduledDateController.text = picked
                                              .toIso8601String();
                                        });
                                      }
                                    },
                                  ),
                                  if (pickings[0].dateDeadline != null &&
                                      pickings[0].dateDeadline!.isNotEmpty)
                                    InfoRow(
                                      label: "Deadline",
                                      value: pickings[0].dateDeadline,
                                      isEditing: false,
                                      prefixIcon: FontAwesomeIcons.calendarAlt,
                                      controller: deadlineController,
                                      color: getScheduledDateColor(
                                        pickings[0].dateDeadline ??
                                            DateTime.now().toString(),
                                      ),
                                      onTapEditing: () async {
                                        DateTime? picked = await showDatePicker(
                                          context: context,
                                          initialDate:
                                              DateTime.tryParse(
                                                pickings[0].dateDeadline ?? '',
                                              ) ??
                                              DateTime.now(),
                                          firstDate: DateTime(2000),
                                          lastDate: DateTime(2100),
                                        );
                                        if (picked != null) {
                                          setState(() {
                                            deadlineController.text = picked
                                                .toIso8601String();
                                          });
                                        }
                                      },
                                    ),
                                  if (pickings[0].state == 'done')
                                    InfoRow(
                                      label: "Effective Date",
                                      value: pickings[0].dateDone,
                                      isEditing: _isEditing,
                                      controller: dateDoneController,
                                      prefixIcon: FontAwesomeIcons.calendarAlt,
                                      color: getScheduledDateColor(
                                        pickings[0].dateDone ??
                                            DateTime.now().toString(),
                                      ),
                                      onTapEditing: _isEditing
                                          ? () async {
                                              DateTime?
                                              picked = await showDatePicker(
                                                context: context,
                                                initialDate:
                                                    DateTime.tryParse(
                                                      pickings[0].dateDone ??
                                                          '',
                                                    ) ??
                                                    DateTime.now(),
                                                firstDate: DateTime(2000),
                                                lastDate: DateTime(2100),
                                              );
                                              if (picked != null) {
                                                setState(() {
                                                  dateDoneController.text =
                                                      picked.toIso8601String();
                                                });
                                              }
                                            }
                                          : null,
                                    ),
                                  if (pickings[0].pickingTypeCode ==
                                          'outgoing' &&
                                      [
                                        'waiting',
                                        'confirmed',
                                        'assigned',
                                      ].contains(pickings[0].state))
                                    InfoRow(
                                      label: "Product Availability",
                                      value: pickings[0].productsAvailability,
                                      isEditing: false,
                                      controller: availabilityController,
                                      prefixIcon: FontAwesomeIcons.box,
                                      color:
                                          pickings[0].productsAvailability
                                                  ?.toLowerCase() ==
                                              "available"
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  InfoRow(
                                    label: "Source Document",
                                    value: pickings[0].origin,
                                    isEditing: _isEditing,
                                    prefixIcon: FontAwesomeIcons.fileLines,
                                    controller: sourceDocController,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
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
                        padding: const EdgeInsets.all(2.0),
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
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    padding: const EdgeInsets.all(4),
                                    child: TabBar(
                                      controller: tabController,
                                      indicator: BoxDecoration(
                                        color: Colors.transparent,
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
                                        return _buildStyledTab(
                                          text,
                                          isSelected,
                                        );
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
                                        _productTable(isDark),
                                        _additionalInfo(),
                                        _notesTab(),
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
                    if (_isEditing) ...[
                      if (pickings.isNotEmpty &&
                          !['done', 'cancel'].contains(pickings[0].state)) ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              if (_isEditing) {
                                final listOfUpdates = {
                                  'partner_id': selectedPartnerId,
                                  'scheduled_date': formatToOdooDatetime(
                                    scheduledDateController.text,
                                  ),
                                  'origin': sourceDocController.text,
                                  'date_done': dateDoneController.text,
                                  'move_type': _selectedShippingPolicy,
                                  'user_id': _selectedUserId,
                                  'note': _noteController.text,
                                };
                                await _saveChanges(
                                  listOfUpdates,
                                  widget.picking['item'] ??
                                      widget.picking['name'] ??
                                      'Picking Details',
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark
                                  ? Colors.white
                                  : AppStyle.primaryColor,
                              foregroundColor: isDark
                                  ? Colors.black
                                  : Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 16,
                              ),
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
                              "Save Delivery",
                              style: TextStyle(
                                color: isDark ? Colors.black : Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            if (isSaving)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(
                  child: CupertinoActivityIndicator(
                    radius: 30,
                    color: AppStyle.primaryColor,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

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

  Future<bool> _showUnsavedChangesDialog(context) async {
    final result = await DataLossWarningDialog.show(
      context: context,
      title: 'Discard Changes?',
      message: 'You have unsaved changes. Do you want to discard them?',
      confirmText: 'Discard',
      cancelText: 'Keep Editing',
    );
    return result ?? false;
  }

  Future<bool> _handleBackNavigation() async {
    if (isSaving) return false;
    if (_isEditing) {
      final discard = await _showUnsavedChangesDialog(context);
      if (discard) {
        setState(() {
          _isEditing = false;
        });
      }
      return false;
    }
    return true;
  }

  // ───────────────────────────────────────────────
  //                EDIT / ADD PRODUCT LINE DIALOGS
  // ───────────────────────────────────────────────

  /// Dialog for editing existing move line (quantity + product change)
  Widget _editProductLine(BuildContext context, StockMove product, int index) {
    final TextEditingController qtyController = TextEditingController(
      text: product.quantity.toString(),
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return StatefulBuilder(
      builder: (context, setStateDialog) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Edit Product Line',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ],
          ),
          content: Container(
            height: _errorMessage.isNotEmpty
                ? MediaQuery.of(context).size.height * 0.20
                : MediaQuery.of(context).size.height * 0.17,
            width: MediaQuery.of(context).size.width * 0.95,
            child: Stack(
              children: [
                SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Product",
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white60 : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 5),
                          DropdownSearch<Map<String, dynamic>>(
                            popupProps: PopupProps.menu(
                              showSearchBox: true,
                              searchFieldProps: TextFieldProps(
                                decoration: InputDecoration(
                                  labelText: "Search Product",
                                  labelStyle: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                  prefixIcon: Icon(Icons.search),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            items: products.map((p) => p.toJson()).toList(),
                            itemAsString: (item) => item?['name'] ?? '',
                            selectedItem: products
                                .firstWhere(
                                  (element) => element.id == selectedPicking,
                                  orElse: () =>
                                      Product(id: 0, name: '', uom_id: 0),
                                )
                                .toJson(),
                            onChanged: (value) {
                              setState(() {
                                selectedPicking = value?['id'];
                                selectedPickingName = value?['name'];
                              });
                            },
                            dropdownDecoratorProps: DropDownDecoratorProps(
                              dropdownSearchDecoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                hintText: "Select Product",
                                hintStyle: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black87,
                                ),
                                prefixIcon: Icon(
                                  Icons.inventory_2,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[500],
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: isDark
                                        ? Colors.white24
                                        : Colors.transparent,
                                    width: 1.5,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: isDark
                                        ? Colors.white
                                        : AppStyle.primaryColor,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                            validator: (value) => value == null
                                ? 'Please select a product'
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Quantity",
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white60 : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 5),
                          TextField(
                            controller: qtyController,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              hintText: 'Add Quantity',
                              hintStyle: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white60 : Colors.black87,
                              ),
                              prefixIcon: Icon(
                                Icons.format_list_numbered,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[500],
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: isDark
                                      ? Colors.white24
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: isDark
                                      ? Colors.white
                                      : AppStyle.primaryColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_errorMessage.isNotEmpty)
                        Text(
                          _errorMessage,
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_isLoading)
                  Container(
                    color: Colors.black26,
                    child: const Center(
                      child: CupertinoActivityIndicator(
                        radius: 30,
                        color: AppStyle.primaryColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      setStateDialog(() {
                        _isLoading = true;
                      });
                      final odooPickingFormService = OdooPickingFormService();
                      await odooPickingFormService.initializeOdooClient();
                      final pickingId = int.parse(
                        widget.picking['id'].toString(),
                      );
                      await odooPickingFormService.deleteProductMove(
                        product.id,
                        pickingId,
                      );
                      setState(() {
                        moveProducts.removeAt(index);
                      });
                      await _loadSavingData();
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                      setStateDialog(() {
                        _isLoading = false;
                      });
                    },
                    icon: const Icon(Icons.delete),
                    label: Text(
                      'DELETE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppStyle.primaryColor,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark
                          ? Colors.black
                          : AppStyle.primaryColor,
                      side: BorderSide(
                        color: isDark ? Colors.white : Color(0xFFBB2649),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final enteredQty =
                          double.tryParse(qtyController.text.trim()) ?? 0.0;
                      if (selectedPicking == null) {
                        setState(() {
                          _errorMessage = "Please select a product.";
                        });
                        Navigator.of(context).pop();
                        showDialog(
                          context: context,
                          builder: (context) =>
                              _editProductLine(context, product, index),
                        );
                      } else if (enteredQty > 0) {
                        setStateDialog(() {
                          _isLoading = true;
                          _errorMessage = '';
                        });
                        final odooPickingFormService = OdooPickingFormService();
                        await odooPickingFormService.initializeOdooClient();
                        final pickingId = int.parse(
                          widget.picking['id'].toString(),
                        );
                        final moveUpdate = StockMove(
                          id: product.id,
                          productId: [
                            selectedPicking!,
                            selectedPickingName ?? 'Unnamed',
                          ],
                          productUomQty: product.productUomQty,
                          quantity: enteredQty,
                        );
                        final isOnline = await odooPickingFormService
                            .checkNetworkConnectivity();
                        if (isOnline) {
                          await odooPickingFormService.updateProductMove(
                            product.id,
                            selectedPicking!,
                            selectedPickingName ?? 'Unnamed',
                            enteredQty,
                            int.tryParse(
                                  widget.picking['location_id_int']
                                          ?.toString() ??
                                      '',
                                ) ??
                                1,
                            int.tryParse(
                                  widget.picking['location_dest_id_int']
                                          ?.toString() ??
                                      '',
                                ) ??
                                1,
                          );
                          setState(() {
                            moveProducts[index] = StockMove(
                              id: product.id,
                              productId: [
                                selectedPicking!,
                                selectedPickingName ?? 'Unnamed',
                              ],
                              productUomQty: product.productUomQty,
                              quantity: enteredQty,
                            );
                          });
                          await _loadSavingData();
                        } else {
                          final locationIdInt =
                              widget.picking['location_id_int'] != null
                              ? int.tryParse(
                                  widget.picking['location_id_int'].toString(),
                                )
                              : null;

                          final locationDestIdInt =
                              widget.picking['location_dest_id_int'] != null
                              ? int.tryParse(
                                  widget.picking['location_dest_id_int']
                                      .toString(),
                                )
                              : null;
                          await _hiveService.savePendingProductUpdates(
                            pickingId,
                            {
                              'move': moveUpdate.toJson(),
                              'timestamp': DateTime.now(),
                              'location_id_int': locationIdInt,
                              'location_dest_id_int': locationDestIdInt,
                            },
                            widget.picking['item'] ??
                                widget.picking['name'] ??
                                'Picking Details',
                          );

                          setState(() {
                            moveProducts[index] = moveUpdate;
                          });
                        }

                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                        setStateDialog(() {
                          _isLoading = false;
                        });
                      } else {
                        setState(() {
                          _errorMessage = "Quantity must be greater than zero.";
                        });
                        Navigator.of(context).pop();
                        showDialog(
                          context: context,
                          builder: (context) =>
                              _editProductLine(context, product, index),
                        );
                      }
                    },
                    icon: const Icon(Icons.save),
                    label: Text(
                      'SAVE',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.black : Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark
                          ? Colors.white
                          : AppStyle.primaryColor,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Dialog for adding new move line
  Widget _addProductLine(BuildContext context) {
    final TextEditingController qtyController = TextEditingController(
      text: '1',
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return StatefulBuilder(
      builder: (context, setState) => Stack(
        children: [
          AlertDialog(
            backgroundColor: isDark ? Colors.grey[850] : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Add a Product Line',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ],
            ),
            content: Container(
              height: _errorMessage.isNotEmpty
                  ? MediaQuery.of(context).size.height * 0.20
                  : MediaQuery.of(context).size.height * 0.17,
              width: MediaQuery.of(context).size.width * 0.95,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Product",
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white60 : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 5),
                        DropdownSearch<Map<String, dynamic>>(
                          popupProps: PopupProps.menu(
                            showSearchBox: true,
                            searchFieldProps: TextFieldProps(
                              decoration: InputDecoration(
                                hintText: "Search Product",
                                hintStyle: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          items: products.map((p) => p.toJson()).toList(),
                          itemAsString: (item) => item?['name'] ?? '',
                          onChanged: (value) {
                            setState(() {
                              _errorMessage = '';
                              selectedPicking = value?['id'];
                              selectedPickingName = value?['name'];
                              selectedPickingUom = value?['uom_id'] ?? 1;
                            });
                          },
                          dropdownDecoratorProps: DropDownDecoratorProps(
                            dropdownSearchDecoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              hintText: "Select Product",
                              hintStyle: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white60 : Colors.black87,
                              ),
                              prefixIcon: Icon(
                                Icons.inventory_2,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[500],
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: isDark
                                      ? Colors.white24
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: isDark
                                      ? Colors.white
                                      : AppStyle.primaryColor,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          validator: (value) =>
                              value == null ? 'Please select a product' : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Quantity",
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white60 : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 5),
                        TextField(
                          controller: qtyController,
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            hintText: 'Add Quantity',
                            hintStyle: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white60 : Colors.black87,
                            ),
                            prefixIcon: Icon(
                              Icons.format_list_numbered,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[500],
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.white24
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.white
                                    : AppStyle.primaryColor,
                                width: 2,
                              ),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_errorMessage.isNotEmpty)
                      Text(
                        _errorMessage,
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? Colors.white : Colors.black87,
                        side: BorderSide(
                          color: isDark ? Colors.white : Color(0xFFBB2649),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                      child: Text(
                        "CANCEL",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppStyle.primaryColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        setState(() {
                          isCreateSaving = true;
                        });
                        final enteredQty =
                            double.tryParse(qtyController.text.trim()) ?? 0.0;
                        if (selectedPicking == 0) {
                          setState(() {
                            isCreateSaving = false;
                            _errorMessage = "Please select a product.";
                          });
                          Navigator.of(context).pop();
                          showDialog(
                            context: context,
                            builder: (context) => _addProductLine(context),
                          );
                        } else if (enteredQty > 0) {
                          setState(() {
                            _errorMessage = '';
                          });
                          final odooPickingFormService =
                              OdooPickingFormService();
                          await odooPickingFormService.initializeOdooClient();
                          final pickingId =
                              int.tryParse(
                                widget.picking['id']?.toString() ?? '',
                              ) ??
                              0;
                          final isOnline = await odooPickingFormService
                              .checkNetworkConnectivity();

                          if (isOnline) {
                            await odooPickingFormService.addProductToLine(
                              pickingId,
                              selectedPicking!,
                              selectedPickingName ?? 'Unnamed',
                              selectedPickingUom ?? 1,
                              enteredQty,
                              int.tryParse(
                                    widget.picking['location_id_int']
                                            ?.toString() ??
                                        '',
                                  ) ??
                                  1,
                              int.tryParse(
                                    widget.picking['location_dest_id_int']
                                            ?.toString() ??
                                        '',
                                  ) ??
                                  1,
                            );
                          } else {
                            final newProduct = {
                              'move': {
                                'product_id': [
                                  selectedPicking!,
                                  selectedPickingName ?? 'Unnamed',
                                ],
                                'quantity': enteredQty,
                                'quantity_product_uom': '',
                              },
                              'pickingId': pickingId,
                              'pickingName': widget.picking['item'],
                            };

                            final hiveService = HiveService();
                            await hiveService.initialize();
                            await hiveService.savePendingProductUpdates(
                              pickingId,
                              newProduct,
                              selectedPickingName ?? 'Unnamed',
                            );

                            await hiveService.saveProducts([newProduct]);
                          }
                          if (isOnline) await _loadSavingData();
                          setState(() {
                            isCreateSaving = false;
                          });
                          Navigator.of(context).pop();
                        }
                      },
                      icon: Icon(
                        Icons.add,
                        color: isDark ? Colors.black : Colors.white,
                      ),
                      label: Text(
                        'Add',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.black : Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? Colors.white
                            : AppStyle.primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (isCreateSaving)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CupertinoActivityIndicator(
                  radius: 30,
                  color: AppStyle.primaryColor,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────
  //                TABS CONTENT
  // ───────────────────────────────────────────────

  Widget _productTable(isDark) {
    List<Widget> productRows = moveProducts.asMap().entries.map((entry) {
      int index = entry.key;
      StockMove product = entry.value;
      return GestureDetector(
        onTap: () {
          if (pickings[0].state != 'done' && pickings[0].state != 'cancel') {
            setState(() {
              _errorMessage = "";
              selectedPicking = product.productId?[0];
              selectedPickingName = product.productId?[1];
            });
            showDialog(
              context: context,
              builder: (context) => _editProductLine(context, product, index),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(flex: 5, child: Text(product.productId?[1] ?? '')),
              Expanded(flex: 2, child: Text(product.productUomQty.toString())),
              Expanded(flex: 2, child: Text(product.quantity.toString())),
            ],
          ),
        ),
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      "Product",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      "Demand",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      "Quantity",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            ...productRows,
            const SizedBox(height: 12),
            if (pickings[0].state != 'done' && pickings[0].state != 'cancel')
              GestureDetector(
                onTap: () {
                  setState(() {
                    _errorMessage = "";
                    selectedPicking = 0;
                  });
                  showDialog(
                    context: context,
                    builder: (context) => _addProductLine(context),
                  );
                },
                child: Text(
                  "+ Add a line",
                  style: TextStyle(
                    color: isDark ? Colors.white : AppStyle.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _additionalInfo() {
    final picking = pickings[0];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {},
            child: _isEditing
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Shipping Policy",
                        style: TextStyle(
                          fontWeight: FontWeight.w400,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xff7F7F7F),
                        ),
                      ),

                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: isDark
                              ? const Color(0xFF2A2A2A)
                              : const Color(0xFFF2F4F6),
                          border: Border.all(
                            color: Colors.transparent,
                            width: 1,
                          ),
                        ),
                        child: DropdownButton2<String>(
                          isExpanded: true,
                          value: _selectedShippingPolicy,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'direct',
                              child: Text("When all products are ready"),
                            ),
                            DropdownMenuItem(
                              value: 'one',
                              child: Text("As soon as possible"),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _selectedShippingPolicy = value;
                              });
                            }
                          },
                          dropdownStyleData: DropdownStyleData(
                            maxHeight: 200,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.white,
                            ),
                            offset: const Offset(0, -3),
                          ),
                          underline: const SizedBox(),
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Shipping Policy",
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        picking.moveType == 'direct'
                            ? 'When all products are ready'
                            : 'As soon as possible',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontWeight: FontWeight.normal,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          InfoRow(
            label: "Responsible",
            value: picking.userId,
            isEditing: _isEditing,
            dropdownItems: userList.map((u) => u.toJson()).toList(),
            selectedId:
                _selectedUserId ??
                (picking.userId?.isNotEmpty ?? false
                    ? picking.userId![0]
                    : null),
            onDropdownChanged: (value) {
              setState(() {
                _selectedUserId = value?['id'];
              });
            },
            onTap: () {},
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Procurement Group",
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                (picking.groupId != null && picking.groupId!.length > 1)
                    ? picking.groupId![1]
                    : "None",
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.normal,
                  fontSize: 14,
                ),
                textAlign: TextAlign.end,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Company",
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                (picking.companyId != null && picking.companyId!.length > 1)
                    ? picking.companyId![1]
                    : "None",
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.normal,
                  fontSize: 14,
                ),
                textAlign: TextAlign.end,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _notesTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoRow(
              label: "Note",
              value: pickings.isNotEmpty ? pickings[0].note : '',
              isEditing: _isEditing,
              controller: _noteController,
              readOnly:
                  pickings.isNotEmpty &&
                  ['done', 'cancel'].contains(pickings[0].state),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}
