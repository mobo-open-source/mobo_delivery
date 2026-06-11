import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_ce/hive.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:provider/provider.dart';
import '../../../../shared/widgets/loaders/shimmer_skeleton.dart' as sk;
import '../../../../Rating/review_service.dart';
import '../../../../core/company/session/company_session_manager.dart';
import '../../../../core/navigation/data_loss_warning_dialog.dart';
import '../../../../shared/utils/globals.dart';
import '../../../../shared/utils/odoo_datetime_format.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_state_widget.dart';
import '../../../../shared/widgets/loaders/loading_widget.dart';
import '../../../../shared/widgets/loading_overlay.dart';
import '../../../../shared/widgets/snackbar.dart';

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
import '../../../ReturnManagement/services/odoo_return_service.dart';
import '../../../ReturnManagement/widgets/picking_bottom_sheet.dart';

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
  List<PickingForm> pickings = [];
  List<Product> products = [];
  List<Partner> partnerList = [];
  List<User> userList = [];
  List<StockMove> moveProducts = [];

  List<Map<String, dynamic>> pickingStockLine = [];
  List<Map<String, dynamic>> returnDataList = [];

  String _errorMessage = '';
  bool isDataAvailable = true;
  bool _isEditing = false;

  int? selectedPartnerId;
  int? selectedPicking;
  int? selectedPickingUom;
  String? selectedPickingName;
  String? _selectedShippingPolicy;
  int? _selectedUserId;

  List<Map<String, dynamic>> operationTypesList = [];
  int? _selectedPickingTypeId;
  int? _selectedLocationId;
  int? _selectedLocationDestId;

  bool isSaving = false;
  bool isDataFromHive = false;
  bool _isLoading = false;
  final HiveService _hiveService = HiveService();

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
  bool _networkCheckInProgress = false;
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
    deliveryAddressController.dispose();
    operationTypeController.dispose();
    scheduledDateController.dispose();
    deadlineController.dispose();
    dateDoneController.dispose();
    availabilityController.dispose();
    sourceDocController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Starts a periodic network availability check (every 30 seconds).
  ///
  /// 30 s is enough to catch a connection drop without constantly running
  /// DNS lookups in the background. An immediate check fires on mount so
  /// the flag is correct from the first frame.
  void _startNetworkCheck() {
    _checkNetwork();
    _networkTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkNetwork();
    });
  }

  /// Checks connectivity and updates [isOnlineAvailability].
  ///
  /// Guarded by [_networkCheckInProgress] so overlapping timer ticks
  /// (e.g. a slow DNS reply on the previous tick) don't pile up.
  Future<void> _checkNetwork() async {
    if (_networkCheckInProgress) return;
    _networkCheckInProgress = true;
    try {
      final available = await OdooPickingFormService().checkNetworkConnectivity();
      if (mounted) {
        setState(() => isOnlineAvailability = available);
      }
    } finally {
      _networkCheckInProgress = false;
    }
  }

  Future<void> _initializeHive() async {
    final odooPickingFormService = OdooPickingFormService();
    await odooPickingFormService.initializeOdooClient();
    await _hiveService.initialize();
  }

  /// Main data loading decision point:
  ///   1. Resets any stale error so Retry starts clean.
  ///   2. Tries Hive cache (cache-miss is not an error).
  ///   3. If online, loads fresh data from Odoo.
  ///   4. Surfaces an error only if both paths leave `pickings` empty.
  Future<void> _fetchData() async {
    final rawId = widget.picking['id'];
    debugPrint('[PickingDetail] Fetch START id=$rawId');
    final odooPickingFormService = OdooPickingFormService();
    if (mounted) {
      setState(() {
        isDataAvailable = true;
        _errorMessage = '';
      });
    }
    bool isOnline = false;
    try {
      await odooPickingFormService.initializeOdooClient();
      isOnline = await odooPickingFormService.checkNetworkConnectivity();
      if (mounted) {
        setState(() {
          isDataFromHive = !isOnline;
        });
      }

      const isCancel = false;
      const isPending = false;
      if (mounted) {
        setState(() {
          isOfflineValidate = isPending;
          isOfflineCancel = isCancel;
        });
      }

      try {
        await _loadOfflineData();
      } catch (e, st) {
        debugPrint('[PickingDetail] Fetch offline-load FAILED id=$rawId: $e\n$st');
      }

      if (isOnline) {
        try {
          await _loadOnlineData();
        } catch (e, st) {
          debugPrint('[PickingDetail] Fetch online-load FAILED id=$rawId: $e\n$st');
        }
      }
    } catch (e, st) {
      debugPrint('[PickingDetail] Fetch EXCEPTION id=$rawId: $e\n$st');
    } finally {
      if (mounted) {
        setState(() {
          isDataAvailable = false;
          if (pickings.isEmpty) {
            _errorMessage = isOnline
                ? "Couldn't load this picking. It may have been deleted or you don't have access."
                : "You're offline and this picking isn't cached yet. Reconnect and try again.";
          }
        });
      }
      debugPrint(
        '[PickingDetail] Fetch END id=$rawId '
        'online=$isOnline pickings=${pickings.length} '
        'moves=${moveProducts.length} err=${_errorMessage.isEmpty ? "none" : _errorMessage}',
      );
    }
  }

  /// Reloads only the data that changes after a state mutation
  /// (validate, cancel, confirm, check availability).
  ///
  /// Optimisations vs the original sequential version:
  ///   1. Picking header + product moves are fetched in parallel.
  ///   2. Partner details (including `image_1920`) are only re-fetched when
  ///      the image isn't already cached — a state change never alters the
  ///      partner or their image, so the extra round-trip is wasted work.
  Future<void> _loadSavingData() async {
    final odooPickingFormService = OdooPickingFormService();
    await odooPickingFormService.initializeOdooClient();
    final pickingId = int.parse(widget.picking['id'].toString());
    debugPrint('[PickingDetail] Reload START id=$pickingId');

    // Run picking header and moves in parallel.
    final results = await Future.wait<dynamic>([
      odooPickingFormService.loadPickings(pickingId),
      odooPickingFormService.loadProductMoves(pickingId).catchError((e, st) {
        debugPrint('[PickingDetail] Reload moves FAILED id=$pickingId: $e\n$st');
        return moveProducts; // keep whatever is already displayed
      }),
    ]);

    final freshPickings = results[0] as List<PickingForm>;
    final freshMoves = results[1] as List<StockMove>;

    debugPrint(
      '[PickingDetail] Reload id=$pickingId '
      'pickings=${freshPickings.length} moves=${freshMoves.length}',
    );

    if (freshPickings.isEmpty) {
      debugPrint('[PickingDetail] Reload EARLY-RETURN — header empty');
      if (mounted) setState(() {});
      return;
    }

    // Only fetch partner details if the image hasn't been loaded yet.
    // A state change (validate/cancel/etc.) never changes the partner.
    if (_cachedImage == null) {
      final partnerId = freshPickings[0].partnerId?.isNotEmpty == true
          ? freshPickings[0].partnerId![0]
          : null;
      if (partnerId != null) {
        partnerDetails = await odooPickingFormService.loadPartnerDetails(partnerId);
        final imageString = partnerDetails?['image_1920'];
        if (imageString != null && imageString.isNotEmpty && mounted) {
          setState(() => _cachedImage = base64Decode(imageString));
        }
      }
    }

    if (mounted) {
      setState(() {
        pickings = freshPickings;
        moveProducts = freshMoves;
      });
      if (!_isEditing) _syncControllersFromPicking();
    }
  }


  /// Loads fresh data from Odoo + caches partner image & details to Hive.
  ///
  /// Tiered so the page renders as soon as the read-only view has what
  /// it needs:
  ///   - **Foreground** (awaited): picking header, product moves, partner
  ///     details. These are required to draw the picking on screen.
  ///   - **Background** (fire-and-forget via [_loadEditModeDropdowns]):
  ///     products, partners, users, operation types — only needed in
  ///     edit mode. Populated when ready, with the Hive offline cache
  ///     already providing the previous-session values for instant edit.
  ///
  /// Each loader catches its own errors and returns empty/null on
  /// failure, so a slow or failing single call doesn't block the others.
  Future<void> _loadOnlineData() async {
    final odooPickingFormService = OdooPickingFormService();
    await odooPickingFormService.initializeOdooClient();
    final pickingId = int.parse(widget.picking['id'].toString());

    pickings = await odooPickingFormService.loadPickings(pickingId);

    final partnerIdForDetails = (pickings.isNotEmpty &&
            pickings[0].partnerId != null &&
            pickings[0].partnerId!.isNotEmpty)
        ? pickings[0].partnerId![0]
        : null;

    // Load moves and partner details concurrently, but handle moves failure
    // separately so a bad field / RPC error is shown to the user rather than
    // silently leaving the product table empty.
    final results = await Future.wait<dynamic>([
      odooPickingFormService.loadProductMoves(pickingId).catchError((e, st) {
        debugPrint('[PickingDetail] loadProductMoves FAILED id=$pickingId: $e\n$st');
        if (mounted) {
          final msg = _extractOdooError(
            e,
            'Could not load products. '
            'Check your connection or contact your administrator.',
          );
          CustomSnackbar.showError(context, msg);
        }
        // Preserve whatever came from the Hive cache (set by _loadOfflineData).
        return moveProducts;
      }),
      partnerIdForDetails != null
          ? odooPickingFormService.loadPartnerDetails(partnerIdForDetails)
          : Future<dynamic>.value(null),
    ]);

    moveProducts = results[0] as List<StockMove>;
    partnerDetails = results[1] as Map<String, dynamic>?;

    final imageString = partnerDetails?['image_1920'];
    if (imageString != null && imageString.isNotEmpty) {
      _cachedImage = base64Decode(imageString);
    }

    if (partnerIdForDetails != null) {
      final partnerDetailModel = PartnerDetails(
        id: partnerIdForDetails as int,
        address: partnerDetails?['address'],
        imageBase64: partnerDetails?['image_1920'],
      );
      await _hiveService.savePartnerDetails(partnerDetailModel);
    }

    if (mounted) {
      setState(() {});
      if (!_isEditing) _syncControllersFromPicking();
    }

    unawaited(_loadEditModeDropdowns(odooPickingFormService));
  }

  /// Loads the dropdown data that's only used in edit mode (products,
  /// partners, users, operation types) in the background after the
  /// read-only view has rendered. Offline cache from the previous
  /// session already populated these lists via `_loadOfflineData`, so
  /// edit mode is usable immediately; this call just refreshes them
  /// against the server.
  Future<void> _loadEditModeDropdowns(
    OdooPickingFormService service,
  ) async {
    try {
      final results = await Future.wait<dynamic>([
        service.loadProducts().catchError((e) {
          debugPrint('loadProducts error: $e');
          return <Product>[];
        }),
        service.loadPartners().catchError((e) {
          debugPrint('loadPartners error: $e');
          return <Partner>[];
        }),
        service.loadUsers().catchError((e) {
          debugPrint('loadUsers error: $e');
          return <User>[];
        }),
        service.loadOperationTypes().catchError((e) {
          debugPrint('loadOperationTypes error: $e');
          return <Map<String, dynamic>>[];
        }),
      ]);
      if (!mounted) return;
      final freshProducts = (results[0] as List?)?.cast<Product>() ?? <Product>[];
      final freshPartners = (results[1] as List?)?.cast<Partner>() ?? <Partner>[];
      final freshUsers = (results[2] as List?)?.cast<User>() ?? <User>[];
      final freshOpTypes = (results[3] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];
      debugPrint(
        '[EditDropdowns] products=${freshProducts.length} '
        'partners=${freshPartners.length} '
        'users=${freshUsers.length} '
        'opTypes=${freshOpTypes.length}',
      );
      setState(() {
        // Only overwrite cached data if the fresh fetch actually returned results.
        // A silent RPC failure returns [] and must not wipe the Hive-loaded cache.
        if (freshProducts.isNotEmpty) products = freshProducts;
        if (freshPartners.isNotEmpty) partnerList = freshPartners;
        if (freshUsers.isNotEmpty) userList = freshUsers;
        if (freshOpTypes.isNotEmpty) operationTypesList = freshOpTypes;
      });
    } catch (e) {
      debugPrint('[EditDropdowns] load failed: $e');
      // Dropdowns fall back to cached / empty values; edit mode still works.
    }
  }

  /// ───────────────────────────────────────────────
  ///                OFFLINE FLOW
  /// ───────────────────────────────────────────────

  /// Loads all necessary data from Hive when offline or as fallback.
  /// Returns true if the picking header was found in cache; a cache miss
  /// is not an error — `_fetchData` makes the final error decision after
  /// both load paths complete.
  Future<bool> _loadOfflineData() async {
    try {
      final pickingId = int.parse(widget.picking['id'].toString());

      // Load global master data first so dropdown caches are immediately populated
      final productsData = await _hiveService.getProducts();
      final partnersData = await _hiveService.getPartners();
      final usersData = await _hiveService.getUsers();
      final cachedOperationTypes = await OdooPickingFormService()
          .loadOperationTypesFromCache();
      if (mounted) {
        setState(() {
          products = productsData;
          partnerList = partnersData;
          userList = usersData;
          operationTypesList = cachedOperationTypes;
        });
      }

      final picking = await _hiveService.getPickingById(pickingId);
      if (picking == null) {
        return false;
      }
      if (mounted) {
        setState(() {
          pickings = [picking];
        });
        if (!_isEditing) _syncControllersFromPicking();
      }
      final movesData = await _hiveService.getStockMoves(pickingId: pickingId);
      final partnerId = pickings.isEmpty
          ? null
          : (pickings[0].partnerId == null ||
                pickings[0].partnerId!.isEmpty)
              ? null
              : pickings[0].partnerId![0];
      if (partnerId != null) {
        final offlinePartnerDetails = await _hiveService.getPartnerDetails(
          partnerId,
        );
        if (offlinePartnerDetails != null) {
          if (mounted) {
            setState(() {
              partnerDetails = offlinePartnerDetails.toJson();
              if (offlinePartnerDetails.imageBase64 != null &&
                  offlinePartnerDetails.imageBase64!.isNotEmpty) {
                _cachedImage = base64Decode(offlinePartnerDetails.imageBase64!);
              }
            });
          }
        }
      }
      if (mounted) {
        setState(() {
          moveProducts = movesData;
        });
      }
      return true;
    } catch (_) {
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


  /// Extracts a human-readable message from an Odoo RPC exception.
  ///
  /// Odoo errors arrive as strings like:
  ///   "OdooServerException: UserError: Not enough stock."
  ///   "...{\"message\": \"Cannot validate...\"}"
  /// Returns [fallback] when no better message can be found.
  /// Extracts a human-readable Odoo error message from an exception.
  ///
  /// odoo_rpc surfaces server errors in a handful of shapes depending on
  /// the call path — sometimes a JSON-encoded body, sometimes a plain
  /// "OdooException: UserError: ..." string, sometimes a multi-line
  /// payload with a traceback before the user-facing text. The previous
  /// version only matched the simplest single-line JSON shape, which is
  /// why some real failures (notably "Failed to create backorder", "Failed
  /// to validate return") came out as the unhelpful fallback even though
  /// Odoo *had* returned a real reason.
  ///
  /// Order of attempts (return the first one that yields a non-empty
  /// candidate):
  ///   1. `OdooSessionExpiredException` → session-expired text.
  ///   2. `arguments`: ["..."] — modern Odoo wraps the human message here.
  ///   3. JSON `"message": "..."` — handles escaped quotes and multi-line.
  ///   4. The line containing UserError/ValidationError/AccessError/
  ///      RedirectWarning, returning the part after the *last* colon on
  ///      that line (avoids grabbing the URL or stack-trace tail).
  ///   5. `data.message` legacy XML-RPC format.
  ///   6. Fallback.
  String _extractOdooError(Object e, String fallback) {
    final raw = e.toString();

    if (raw.contains('SessionExpired') || raw.contains('Session expired')) {
      return 'Your session has expired. Please log in again.';
    }

    // 1. Modern Odoo nests the human-readable message inside `arguments`.
    final argsMatch = RegExp(
      r'"arguments":\s*\[\s*"((?:[^"\\]|\\.)*)"',
    ).firstMatch(raw);
    if (argsMatch != null) {
      final unescaped = _unescapeJsonString(argsMatch.group(1)!);
      if (unescaped.trim().isNotEmpty) return unescaped;
    }

    // 2. JSON "message" key — allow escaped quotes and newlines.
    final msgMatch = RegExp(
      r'"message":\s*"((?:[^"\\]|\\.)*)"',
    ).firstMatch(raw);
    if (msgMatch != null) {
      final unescaped = _unescapeJsonString(msgMatch.group(1)!);
      if (unescaped.trim().isNotEmpty) return unescaped;
    }

    // 3. Plain "OdooException: UserError: ..." style.
    final errorMarkers = [
      'UserError',
      'ValidationError',
      'AccessError',
      'RedirectWarning',
      'MissingError',
    ];
    for (final marker in errorMarkers) {
      final idx = raw.indexOf(marker);
      if (idx < 0) continue;
      final line = raw.substring(idx).split(RegExp(r'[\n\r]')).first;
      final colonIdx = line.indexOf(':');
      if (colonIdx >= 0 && colonIdx + 1 < line.length) {
        final candidate = line.substring(colonIdx + 1).trim();
        if (candidate.isNotEmpty && candidate.length < 400) return candidate;
      }
    }

    // 4. Legacy `data.message` pattern.
    final dataMatch = RegExp(
      r'data\.message["\s:]+([^"}\n]+)',
    ).firstMatch(raw);
    if (dataMatch != null) {
      final candidate = dataMatch.group(1)!.trim();
      if (candidate.isNotEmpty) return candidate;
    }

    return fallback;
  }

  /// Decodes JSON-string escape sequences (\n, \", \\, etc.). Lightweight
  /// — only what Odoo actually emits in error payloads.
  String _unescapeJsonString(String s) => s
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '')
      .replaceAll(r'\t', '\t')
      .replaceAll(r'\"', '"')
      .replaceAll(r'\\', r'\');

  /// Validates the picking (online → immediate, offline → queue)
  /// Prevents validation if empty or no quantities reserved
  Future<void> _validatePicking() async {
    // 1. Minimum check: picking must have moves
    if (moveProducts.isEmpty) {
      CustomSnackbar.showWarning(
        context,
        'You can’t validate an empty transfer. Please add some products to move before proceeding.',
      );
      return;
    }

    // 2. We removed the strict hasZeroQuantity check here.
    // If quantities are zero, Odoo will return an "Immediate Transfer" or "Backorder" wizard.
    // This allows the user to follow the standard Odoo workflow.

    final odooPickingFormService = OdooPickingFormService();
    await odooPickingFormService.initializeOdooClient();
    setState(() => isSaving = true);
    final pickingId = int.parse(widget.picking['id'].toString());

    try {
      final isOnline = isOnlineAvailability;
      if (isOnline) {
        final success = await odooPickingFormService
            .validatePicking(pickingId)
            .timeout(const Duration(seconds: 30));

        if (success == true) {
          try {
            await _loadSavingData().timeout(const Duration(seconds: 15));
          } catch (_) {}
          ReviewService().trackSignificantEvent();
          Future.delayed(const Duration(seconds: 3), () {
            if (!mounted) return;
            ReviewService().checkAndShowRating(context);
          });
        } else if (success is Map &&
            (success['type'] == 'ir.actions.act_window' ||
                success['type'] == 'ir.actions.client')) {
          await _handlePickingWizard(
            pickingId: pickingId,
            action: success,
            fallbackSuccessMessage: 'Transfer validated.',
          );
        } else {
          if (mounted) {
            CustomSnackbar.showError(context, 'Failed to validate picking.');
          }
        }
      } else {
        // Offline case
        try {
          final pickingData = pickings.firstWhere((p) => p.id == pickingId);
          // We don't set to 'draft', we keep current state but queue for sync
          await _hiveService.savePendingValidation(
            pickingId,
            pickingData.toJson(),
          );
          CustomSnackbar.showWarning(
            context,
            'Validation queued for sync when online.',
          );
        } catch (e) {
          if (mounted) {
            CustomSnackbar.showError(context, 'Failed to queue validation.');
          }
        }
      }
    } on TimeoutException {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Validation timed out. The operation might still be processing on the server.',
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = _extractOdooError(e, 'Failed to validate picking.');
        CustomSnackbar.showError(context, msg);
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  /// Cancels the picking (online → immediate, offline → queue).
  ///
  /// Online failures used to surface as a generic "Failed to cancel picking."
  /// even when Odoo returned a real reason (e.g. permission denied, or a
  /// confirmation wizard for done moves). The service now rethrows and we
  /// route wizard responses through the generic dispatcher.
  Future<void> _cancelPicking() async {
    final odooPickingFormService = OdooPickingFormService();
    await odooPickingFormService.initializeOdooClient();
    setState(() => isSaving = true);
    final pickingId = int.parse(widget.picking['id'].toString());
    try {
      final isOnline = isOnlineAvailability;
      if (isOnline) {
        final result = await odooPickingFormService
            .cancelPicking(pickingId)
            .timeout(const Duration(seconds: 15));
        if (result is Map &&
            (result['type'] == 'ir.actions.act_window' ||
                result['type'] == 'ir.actions.client')) {
          await _handlePickingWizard(
            pickingId: pickingId,
            action: result,
            fallbackSuccessMessage: 'Picking cancelled.',
          );
        } else if (result == true) {
          try {
            await _loadSavingData().timeout(const Duration(seconds: 15));
          } catch (_) {}
          ReviewService().trackSignificantEvent();
          Future.delayed(const Duration(seconds: 3), () {
            if (!mounted) return;
            ReviewService().checkAndShowRating(context);
          });
        } else {
          if (mounted) {
            CustomSnackbar.showError(context, 'Failed to cancel picking.');
          }
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
          if (mounted) {
            setState(() {
              pickings = [pickingData];
              isOfflineCancel = true;
            });
          }
          CustomSnackbar.showWarning(
            context,
            'Cancellation queued for sync when online.',
          );
        } catch (e) {
          if (mounted) {
            CustomSnackbar.showError(context, 'Failed to queue cancellation.');
          }
        }
      }
    } on TimeoutException {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Cancel took too long. Please check your connection and try again.',
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = _extractOdooError(e, 'Failed to cancel picking.');
        CustomSnackbar.showError(context, msg);
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  /// Loads & navigates to detailed move lines (uses Hive cache when offline)
  Future<void> _stockMoveLine() async {
    setState(() {
      isSaving = true;
    });
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
        if (mounted) {
          setState(() {
            pickingStockLine = cachedLines;
            isSaving = false;
          });
        }
      }
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              StockMoveLineListPage(pickingStockLine: pickingStockLine),
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
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
        if (mounted) {
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
            transitionDuration: const Duration(milliseconds: 300),
            reverseTransitionDuration: const Duration(milliseconds: 300),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
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
            transitionDuration: const Duration(milliseconds: 300),
            reverseTransitionDuration: const Duration(milliseconds: 300),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
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
      if (mounted) {
        CustomSnackbar.showError(context, 'Failed to check availability.');
      }
    }
  }

  /// Marks the picking as "To Do" (confirmed/ready state in Odoo).
  ///
  /// Typically called when the picking is in draft → moves it to confirmed/assigned.
  /// On success: reloads fresh picking data and clears loading state.
  /// On failure: surfaces the actual Odoo error (e.g. "No product on this
  /// transfer") instead of the previous generic "Failed to mark as todo."
  /// which masked the real reason. If Odoo returns a wizard action (rare
  /// for confirm but possible via custom modules), route it through the
  /// generic dispatcher.
  /// This action is **online only** — no offline fallback is implemented here.
  Future<void> _markAsTodoPicking() async {
    final odooPickingFormService = OdooPickingFormService();
    setState(() => isSaving = true);
    final pickingId = int.parse(widget.picking['id'].toString());
    try {
      await odooPickingFormService.initializeOdooClient();
      final result = await odooPickingFormService.markAsTodoPicking(pickingId);

      if (result is Map &&
          (result['type'] == 'ir.actions.act_window' ||
              result['type'] == 'ir.actions.client')) {
        await _handlePickingWizard(
          pickingId: pickingId,
          action: result,
          fallbackSuccessMessage: 'Picking marked as to do.',
        );
      } else if (result == true) {
        await _loadSavingData();
        ReviewService().trackSignificantEvent();
        Future.delayed(const Duration(seconds: 3), () {
          if (!mounted) return;
          ReviewService().checkAndShowRating(context);
        });
      } else {
        if (mounted) {
          CustomSnackbar.showError(
            context,
            'Could not mark this picking as to do.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = _extractOdooError(e, 'Failed to mark as todo.');
        CustomSnackbar.showError(context, msg);
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  /// Loads and navigates to the list of return pickings (reverse transfers) for this picking.
  ///
  /// Opens the create-return bottom sheet (Odoo's "Return" wizard flow)
  /// for the currently displayed picking. Only meaningful when the
  /// picking is in `done` state — the AppBar gate enforces that before
  /// this is invoked. After the wizard succeeds, reloads the picking so
  /// the "Return (count)" button reflects the new return.
  void _openCreateReturnSheet() {
    if (pickings.isEmpty || pickings[0].state != 'done') return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => PickingBottomSheet(
        picking: widget.picking,
        odooService: OdooReturnManagementService(),
        onReturnCreated: () async {
          await _loadSavingData();
        },
      ),
    );
  }

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
    final odooPickingFormService = OdooPickingFormService();

    try {
      await odooPickingFormService.initializeOdooClient();

      final pickingId = int.parse(widget.picking['id'].toString());
      final box = await Hive.openBox<ReturnPicking>('return_pickings');

      if (!isOnlineAvailability) {
        final cachedReturns = box.values
            .where((item) => item.pickingId == pickingId)
            .toList();

        if (cachedReturns.isNotEmpty) {
          final loadedReturnData =
              cachedReturns.map((e) => e.data).toList();
          if (mounted) {
            setState(() {
              returnDataList = loadedReturnData;
            });
          }
        }
      } else {
        final returnData = await odooPickingFormService.loadReturnPickings(
          pickingId,
        );
        for (var data in returnData) {
          final rawPartner = data['partner_id'];
          final partner =
              rawPartner is List ? rawPartner : const <dynamic>[];
          String stringOr(dynamic v, String fallback) =>
              (v is String && v.isNotEmpty) ? v : fallback;
          final returnPicking = ReturnPicking(
            id: data['id'] is int ? data['id'] as int : 0,
            pickingId: pickingId,
            name: stringOr(data['name'], ''),
            partnerId: partner.isNotEmpty ? partner[0] : 0,
            scheduledDate: stringOr(data['scheduled_date'], ''),
            origin: stringOr(data['origin'], ''),
            state: stringOr(data['state'], ''),
            data: data,
          );
          await box.put('${pickingId}', returnPicking);
        }

        if (mounted) {
          setState(() {
            returnDataList = returnData;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => isSaving = false);
        CustomSnackbar.showError(
          context,
          'Failed to load return list. Please try again.',
        );
      }
      return;
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }

    if (!mounted) return;

    final sourcePickingId = int.parse(widget.picking['id'].toString());
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => ReturnListPage(
          returnDataList: returnDataList,
          odooService: odooPickingFormService,
          sourcePickingId: sourcePickingId,
        ),
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  /// Clears edit-mode selection caches after a save so a subsequent edit
  /// session starts from the freshly reloaded picking instead of reusing
  /// stale per-session selections.
  void _resetEditSelections() {
    selectedPartnerId = null;
    _selectedUserId = null;
    _selectedShippingPolicy = null;
    _selectedPickingTypeId = null;
    _selectedLocationId = null;
    _selectedLocationDestId = null;
  }

  void _syncControllersFromPicking() {
    if (pickings.isEmpty) return;
    final p = pickings[0];
    scheduledDateController.text = formatDateTimeForDisplay(p.scheduledDate);
    deadlineController.text = formatDateTimeForDisplay(p.dateDeadline);
    dateDoneController.text = formatDateTimeForDisplay(p.dateDone);
    sourceDocController.text = p.origin ?? '';
    _noteController.text =
        (p.note ?? '').replaceAll(RegExp(r'<[^>]*>'), '');
  }

  PickingForm? get _currentPicking =>
      pickings.isEmpty ? null : pickings[0];

  Map<String, dynamic>? _buildHeaderUpdates() {
    if (pickings.isEmpty) return null;
    final p = pickings[0];
    final int? existingPartnerId =
        (p.partnerId?.isNotEmpty ?? false) ? p.partnerId![0] as int? : null;
    final int? existingUserId =
        (p.userId?.isNotEmpty ?? false) ? p.userId![0] as int? : null;

    final updates = <String, dynamic>{
      'partner_id': selectedPartnerId ?? existingPartnerId,
      'scheduled_date': formatToOdooDatetime(scheduledDateController.text),
      'date_deadline': deadlineController.text.trim().isEmpty
          ? false
          : formatToOdooDatetime(deadlineController.text),
      'origin': sourceDocController.text,
      'date_done': dateDoneController.text.trim().isEmpty
          ? false
          : formatToOdooDatetime(dateDoneController.text),
      'move_type':
          _selectedShippingPolicy ?? p.moveType ?? 'direct',
      'user_id': _selectedUserId ?? existingUserId,
      'note': _noteController.text,
      'picking_type_id': _selectedPickingTypeId ??
          ((p.pickingTypeId?.isNotEmpty ?? false)
              ? p.pickingTypeId![0]
              : null),
    };

    if (_selectedPickingTypeId != null) {
      if (_selectedLocationId != null) {
        updates['location_id'] = _selectedLocationId;
      }
      if (_selectedLocationDestId != null) {
        updates['location_dest_id'] = _selectedLocationDestId;
      }
    }

    updates.removeWhere((_, value) => value == null);
    return updates;
  }

  /// Saves edited picking header fields (online → Odoo, offline → Hive queue)
  Future<void> _saveChanges(
    Map<String, dynamic> listOfUpdates,
    String title,
  ) async {
    final int pickingId;
    try {
      pickingId = int.parse(widget.picking['id'].toString());
    } catch (e) {
      debugPrint(
        '[PickingDetail] Save aborted — bad picking id: ${widget.picking['id']} ($e)',
      );
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Could not save: this picking has an invalid id.',
        );
      }
      return;
    }

    debugPrint(
      '[PickingDetail] Save START id=$pickingId fields=${listOfUpdates.keys.toList()}',
    );
    final odooPickingFormService = OdooPickingFormService();

    try {
      await odooPickingFormService.initializeOdooClient();
    } catch (e) {
      debugPrint('[PickingDetail] Save init failed for id=$pickingId: $e');
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Could not save: session is not ready. Please try again.',
        );
      }
      return;
    }

    if (mounted) setState(() => isSaving = true);

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

    try {
      final isOnline = isOnlineAvailability;
      debugPrint(
        '[PickingDetail] Save id=$pickingId online=$isOnline',
      );
      if (isOnline) {
        final success = await odooPickingFormService
            .saveChanges(pickingId, updatedListOfUpdates)
            .timeout(const Duration(seconds: 15));
        debugPrint(
          '[PickingDetail] Save RPC id=$pickingId result=$success',
        );
        if (success) {
          try {
            await _loadSavingData().timeout(const Duration(seconds: 15));
            debugPrint(
              '[PickingDetail] Reload after save id=$pickingId OK '
              '(pickings=${pickings.length}, moves=${moveProducts.length})',
            );
          } catch (e, st) {
            debugPrint(
              '[PickingDetail] Reload after save id=$pickingId FAILED: $e\n$st',
            );
            if (mounted) {
              CustomSnackbar.showWarning(
                context,
                'Saved, but failed to reload latest data. Pull to refresh.',
              );
            }
          }
          if (mounted) {
            setState(() {
              _isEditing = false;
              _resetEditSelections();
            });
            _syncControllersFromPicking();
          }
        } else {
          await _hiveService.savePendingUpdates(pickingId, {
            'title': title,
            'partner_name': selectedPartnerName,
            'user_name': selectedUserName,
            'updates': updatedListOfUpdates,
          });
          debugPrint(
            '[PickingDetail] Save id=$pickingId queued offline (RPC returned false)',
          );
          if (mounted) {
            setState(() {
              _isEditing = false;
              _resetEditSelections();
            });
            CustomSnackbar.showWarning(
              context,
              'Changes saved offline. Will sync when online.',
            );
          }
          ReviewService().trackSignificantEvent();
          Future.delayed(const Duration(seconds: 3), () {
            if (!mounted) return;
            ReviewService().checkAndShowRating(context);
          });
        }
      } else {
        await _hiveService.savePendingUpdates(pickingId, {
          'title': title,
          'partner_name': selectedPartnerName,
          'user_name': selectedUserName,
          'updates': updatedListOfUpdates,
        });
        debugPrint(
          '[PickingDetail] Save id=$pickingId queued offline (offline path)',
        );
        if (mounted) {
          setState(() {
            _isEditing = false;
            _resetEditSelections();
          });
          CustomSnackbar.showWarning(
            context,
            'Changes saved offline. Will sync when online.',
          );
        }
      }
    } catch (e, st) {
      debugPrint('[PickingDetail] Save id=$pickingId EXCEPTION: $e\n$st');
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Could not save changes. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
      debugPrint('[PickingDetail] Save END id=$pickingId');
    }
  }

  Widget _buildSkeleton(bool isDark, ThemeData theme) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSkeletonCard(
            isDark,
            children: const [
              sk.SkeletonLine(width: 140, height: 18),
              SizedBox(height: 16),
              sk.SkeletonLine(width: 200),
              SizedBox(height: 8),
              sk.SkeletonLine(width: 160),
              SizedBox(height: 8),
              sk.SkeletonLine(width: 120),
            ],
          ),
          const SizedBox(height: 16),
          _buildSkeletonCard(
            isDark,
            children: const [
              sk.SkeletonLine(width: 120, height: 18),
              SizedBox(height: 16),
              sk.SkeletonLine(width: double.infinity),
              SizedBox(height: 8),
              sk.SkeletonLine(width: double.infinity),
            ],
          ),
          const SizedBox(height: 16),
          _buildSkeletonCard(
            isDark,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  sk.SkeletonLine(width: 120, height: 18),
                  sk.SkeletonBox(height: 20, width: 40),
                ],
              ),
              const SizedBox(height: 16),
              for (int i = 0; i < 3; i++) ...[
                Row(
                  children: const [
                    sk.SkeletonBox(
                      height: 36,
                      width: 36,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    SizedBox(width: 12),
                    Expanded(child: sk.SkeletonLine()),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonCard(bool isDark, {required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: sk.Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  /// Routes any wizard action returned by `button_validate`/`action_confirm`/
  /// `action_cancel` to the matching dialog. Mirrors the Odoo web flow:
  ///   • Backorder confirmation → "Create Backorder?" dialog
  ///   • Immediate transfer → "Validate without quantities?" dialog
  ///   • SMS confirmation (`confirm.stock.sms` / `stock.sms.confirmation`)
  ///     → "Send SMS?" dialog with Send / Skip buttons
  ///   • Scrap / insufficient-qty warnings → confirm-and-proceed dialog
  ///   • Cancel confirmation → "Cancel anyway?" dialog
  ///   • Any other model → generic "Yes / No" dialog that just calls the
  ///     wizard's `process` (or its declared button method) so custom
  ///     modules behave reasonably without app updates.
  ///
  /// The picking is reloaded after each successful wizard action.
  Future<void> _handlePickingWizard({
    required int pickingId,
    required Map action,
    required String fallbackSuccessMessage,
  }) async {
    final resModel = action['res_model']?.toString() ?? '';
    final wizardId =
        action['res_id'] is int ? action['res_id'] as int : null;
    final context0 = action['context'] is Map
        ? Map<String, dynamic>.from(action['context'] as Map)
        : <String, dynamic>{};

    switch (resModel) {
      case 'stock.backorder.confirmation':
        await _showBackorderDialog(pickingId, action);
        return;
      case 'stock.immediate.transfer':
        await _showImmediateTransferDialog(pickingId, action);
        return;
      case 'confirm.stock.sms':
      case 'stock.sms.confirmation':
        await _showSmsConfirmationDialog(
          pickingId: pickingId,
          wizardModel: resModel,
          wizardId: wizardId,
          context0: context0,
        );
        return;
      case 'stock.warn.insufficient.qty.scrap':
      case 'stock.warn.insufficient.qty':
        await _showGenericConfirmDialog(
          pickingId: pickingId,
          wizardModel: resModel,
          wizardId: wizardId,
          context0: context0,
          title: 'Insufficient quantity',
          message:
              'There is not enough quantity for one or more products. Confirm to proceed anyway, or cancel and adjust the picking.',
          confirmLabel: 'Proceed',
          confirmMethod: 'action_done',
          successMessage: fallbackSuccessMessage,
        );
        return;
      default:
        // Unknown / custom-module wizard. Best effort: call `process` (the
        // Odoo convention for "OK" on most stock wizards) when the user
        // accepts. If a module needs a different method the user can still
        // open the wizard in the Odoo web UI.
        await _showGenericConfirmDialog(
          pickingId: pickingId,
          wizardModel: resModel,
          wizardId: wizardId,
          context0: context0,
          title: action['name']?.toString().isNotEmpty == true
              ? action['name'].toString()
              : 'Confirmation required',
          message:
              'Odoo needs to confirm this action before continuing. Tap Confirm to proceed.',
          confirmLabel: 'Confirm',
          confirmMethod: 'process',
          successMessage: fallbackSuccessMessage,
        );
        return;
    }
  }

  /// SMS confirmation wizard (Odoo `stock_sms` module). Two buttons:
  ///   • Send SMS → tries `send_sms` then `action_send_sms` (renamed across
  ///     Odoo versions — the older `stock_sms` add-on used `send_sms`,
  ///     newer / enterprise variants use the `action_*` prefix).
  ///   • Don't Send → tries `dont_send_sms` then `action_cancel`.
  /// The wizard returns `button_validate`'s result internally so the
  /// picking is validated either way.
  Future<void> _showSmsConfirmationDialog({
    required int pickingId,
    required String wizardModel,
    required int? wizardId,
    required Map<String, dynamic> context0,
  }) async {
    if (wizardId == null) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Cannot process SMS confirmation: wizard id missing.',
        );
      }
      return;
    }

    Future<void> callWizardWithFallback(List<String> methodCandidates) async {
      setState(() => isSaving = true);
      Object? lastError;
      try {
        for (final method in methodCandidates) {
          try {
            await CompanySessionManager.callKwWithCompany({
              'model': wizardModel,
              'method': method,
              'args': [
                [wizardId],
              ],
              'kwargs': {'context': context0},
            });
            lastError = null;
            break;
          } catch (e) {
            // Most likely "AttributeError: method not found" on this Odoo
            // version. Try the next candidate before surfacing the error.
            final raw = e.toString();
            final looksLikeMissingMethod =
                raw.contains('AttributeError') ||
                    raw.contains('does not exist') ||
                    raw.contains('has no attribute');
            if (!looksLikeMissingMethod) {
              lastError = e;
              break;
            }
            lastError = e;
          }
        }
        if (lastError != null) throw lastError;
        await _loadSavingData();
        if (mounted) {
          CustomSnackbar.showSuccess(
            context,
            methodCandidates.first.contains('send_sms') &&
                    !methodCandidates.first.startsWith('dont')
                ? 'Transfer validated and SMS sent.'
                : 'Transfer validated.',
          );
        }
      } catch (e) {
        if (mounted) {
          CustomSnackbar.showError(
            context,
            _extractOdooError(e, 'Failed to process SMS confirmation.'),
          );
        }
      } finally {
        if (mounted) setState(() => isSaving = false);
      }
    }

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Send SMS?'),
        content: const Text(
          'Odoo can notify the customer that this delivery has been processed. '
          'Send an SMS now, or validate without notifying?',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await callWizardWithFallback(
                const ['dont_send_sms', 'action_cancel'],
              );
            },
            child: const Text("Don't Send"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await callWizardWithFallback(
                const ['send_sms', 'action_send_sms'],
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Send SMS'),
          ),
        ],
      ),
    );
  }

  /// Generic "Yes / No" confirm-and-proceed dialog for unknown or simple
  /// stock wizards. Calls [confirmMethod] on the wizard record (Odoo's
  /// convention is `process` / `action_done` / `action_confirm`) when the
  /// user confirms. Used as the catch-all fallback so custom modules
  /// behave gracefully without app updates.
  Future<void> _showGenericConfirmDialog({
    required int pickingId,
    required String wizardModel,
    required int? wizardId,
    required Map<String, dynamic> context0,
    required String title,
    required String message,
    required String confirmLabel,
    required String confirmMethod,
    required String successMessage,
  }) async {
    if (wizardId == null) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Cannot process $wizardModel: wizard id missing. '
          'Please complete this step in the Odoo web interface.',
        );
      }
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              setState(() => isSaving = true);
              try {
                await CompanySessionManager.callKwWithCompany({
                  'model': wizardModel,
                  'method': confirmMethod,
                  'args': [
                    [wizardId],
                  ],
                  'kwargs': {'context': context0},
                });
                await _loadSavingData();
                if (mounted) {
                  CustomSnackbar.showSuccess(context, successMessage);
                }
              } catch (e) {
                if (mounted) {
                  CustomSnackbar.showError(
                    context,
                    _extractOdooError(
                      e,
                      'Failed to complete $wizardModel.',
                    ),
                  );
                }
              } finally {
                if (mounted) setState(() => isSaving = false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  /// Builds the kwargs context for a stock wizard's button method.
  ///
  /// Defensive: `stock.backorder.confirmation.process()` and
  /// `stock.immediate.transfer.process()` both read
  /// `button_validate_picking_ids` from context to know which pickings
  /// to validate. Odoo includes it in the action context, but if any
  /// proxy or custom override strips it, the wizard silently no-ops and
  /// the user sees a success snackbar with nothing happening on the
  /// server. We re-inject the current picking id so the wizard always
  /// has something to work with.
  Map<String, dynamic> _wizardContext(int pickingId, dynamic action) {
    final raw = action is Map ? action['context'] : null;
    final ctx = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final existing = ctx['button_validate_picking_ids'];
    if (existing is! List || existing.isEmpty) {
      ctx['button_validate_picking_ids'] = [pickingId];
    }
    return ctx;
  }

  Future<void> _showImmediateTransferDialog(int pickingId, success) async {
    // Odoo already created the wizard record and returned its ID in res_id.
    // We must call process() on that specific record, not on picking IDs.
    final int? wizardId = success['res_id'] is int ? success['res_id'] as int : null;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Immediate Transfer?'),
        content: const Text(
          'You have not recorded any quantities. Odoo will mark all products as done immediately. Do you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              setState(() => isSaving = true);
              try {
                if (wizardId == null) {
                  throw Exception(
                    'Cannot process immediate transfer: wizard record ID not found. '
                    'Please validate from the Odoo web interface.',
                  );
                }
                await CompanySessionManager.callKwWithCompany({
                  'model': 'stock.immediate.transfer',
                  'method': 'process',
                  'args': [[wizardId]],
                  'kwargs': {
                    'context': _wizardContext(pickingId, success),
                  },
                });
                await _loadSavingData();
                if (mounted) {
                  CustomSnackbar.showSuccess(context, 'Transfer validated successfully.');
                }
              } catch (e) {
                if (mounted) {
                  final msg = _extractOdooError(e, 'Failed to process immediate transfer.');
                  CustomSnackbar.showError(context, msg);
                }
              } finally {
                if (mounted) setState(() => isSaving = false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _showBackorderDialog(int pickingId, success) async {
    // Odoo already created the wizard record and returned its ID in res_id.
    // Both "No Backorder" and "Create Backorder" must call methods on that record.
    final int? wizardId = success['res_id'] is int ? success['res_id'] as int : null;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Create Backorder?'),
        content: const Text(
          'Some products are not fully available. Would you like to create a backorder for the remaining quantities, or validate only what is available?',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              setState(() => isSaving = true);
              try {
                if (wizardId == null) {
                  throw Exception(
                    'Cannot process: backorder wizard record ID not found. '
                    'Please validate from the Odoo web interface.',
                  );
                }
                await CompanySessionManager.callKwWithCompany({
                  'model': 'stock.backorder.confirmation',
                  'method': 'process_cancel_backorder',
                  'args': [[wizardId]],
                  'kwargs': {
                    'context': _wizardContext(pickingId, success),
                  },
                });
                await _loadSavingData();
                if (mounted) setState(() => isSaving = false);
                if (mounted) {
                  CustomSnackbar.showWarning(
                    context,
                    'Picking validated without backorder.',
                  );
                }
              } catch (e) {
                if (mounted) setState(() => isSaving = false);
                if (mounted) {
                  final msg = _extractOdooError(e, 'Failed to validate without backorder.');
                  CustomSnackbar.showError(context, msg);
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('No Backorder'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              setState(() => isSaving = true);
              try {
                if (wizardId == null) {
                  throw Exception(
                    'Cannot process: backorder wizard record ID not found. '
                    'Please validate from the Odoo web interface.',
                  );
                }
                await CompanySessionManager.callKwWithCompany({
                  'model': 'stock.backorder.confirmation',
                  'method': 'process',
                  'args': [[wizardId]],
                  'kwargs': {
                    'context': _wizardContext(pickingId, success),
                  },
                });
                await _loadSavingData();
                if (mounted) setState(() => isSaving = false);
                if (mounted) {
                  CustomSnackbar.showSuccess(
                    context,
                    'Backorder created successfully.',
                  );
                }
              } catch (e) {
                if (mounted) setState(() => isSaving = false);
                if (mounted) {
                  final msg = _extractOdooError(e, 'Failed to create backorder.');
                  CustomSnackbar.showError(context, msg);
                }
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

  String formatToOdooDatetime(String input) =>
      OdooDateTimeFormat.toOdooStorage(input);

  String formatDateTimeForDisplay(String? input) =>
      OdooDateTimeFormat.formatForDisplay(input);

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


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !_isEditing && !isSaving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _handleBackNavigation();
        if (shouldPop && mounted && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Stack(
        children: [
          if (_errorMessage.isNotEmpty)
            ErrorStateWidget(
              title: 'Something went wrong',
              message: _errorMessage,
              onRetry: _fetchData,
            )
          else if (isDataAvailable) ...[
            Scaffold(
              backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
              appBar: AppBar(
                forceMaterialTransparency: true,
                backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
                title: Text(
                  widget.picking['item'] ?? "Loading Details...",
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
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              body: _buildSkeleton(isDark, Theme.of(context)),
            ),
          ] else if (pickings.isEmpty)
            EmptyState(
              title: 'No picking details found',
              subtitle: 'We couldn\'t find any information for this picking.',
              onAction: _fetchData,
              actionLabel: 'Retry',
            )
          else ...[
            Scaffold(
              backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],

              appBar: AppBar(
                forceMaterialTransparency: true,
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
                          setState(() => _isEditing = true);
                          // If dropdowns never loaded (background fetch failed),
                          // trigger a reload now so they're available in edit mode.
                          if (partnerList.isEmpty || operationTypesList.isEmpty || userList.isEmpty || products.isEmpty) {
                            unawaited(() async {
                              final svc = OdooPickingFormService();
                              await svc.initializeOdooClient();
                              await _loadEditModeDropdowns(svc);
                            }());
                          }
                        },
                        tooltip: 'Edit Picking',
                        icon: Icon(
                          HugeIcons.strokeRoundedPencilEdit02,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                    if (pickings.isNotEmpty &&
                        pickings[0].state == 'done' &&
                        isOnlineAvailability)
                      IconButton(
                        onPressed: _openCreateReturnSheet,
                        tooltip: 'Create Return',
                        icon: Icon(
                          HugeIcons.strokeRoundedDeliveryReturn02,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
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
                              // Validate is only valid for confirmed/assigned states.
                              // Draft pickings must use "Mark as Todo" first.
                              if (!['draft'].contains(pickings[0].state))
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
                          "This picking was validated while offline. It will sync automatically once the device is back online.",
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
                          "This picking was cancelled while offline. It will sync automatically once the device is back online.",
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
                                  ? Colors.black.withValues(alpha: 0.18)
                                  : Colors.black.withValues(alpha: 0.06),
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
                                        : AppStyle.primaryColor.withValues(
                                            alpha: 0.7,
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
                                          : AppStyle.primaryColor.withValues(
                                              alpha: 0.7,
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
                                ? Colors.black.withValues(alpha: 0.18)
                                : Colors.black.withValues(alpha: 0.06),
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
                                    isEditing: _isEditing,
                                    controller: operationTypeController,
                                    dropdownItems: operationTypesList,
                                    selectedId: _selectedPickingTypeId ??
                                        ((pickings[0].pickingTypeId?.isNotEmpty ??
                                                false)
                                            ? pickings[0].pickingTypeId![0]
                                            : null),
                                    onDropdownChanged: (value) {
                                      setState(() {
                                        _selectedPickingTypeId = value?['id'];
                                        _selectedLocationId = value?[
                                            'default_location_src_id_int'];
                                        _selectedLocationDestId = value?[
                                            'default_location_dest_id_int'];
                                      });
                                    },
                                    prefixIcon: FontAwesomeIcons.tasks,
                                  ),
                                  InfoRow(
                                    label: "Scheduled Date",
                                    value: formatDateTimeForDisplay(
                                      pickings[0].scheduledDate,
                                    ),
                                    isEditing: _isEditing,
                                    controller: scheduledDateController,
                                    color: getScheduledDateColor(
                                      pickings[0].scheduledDate ??
                                          DateTime.now().toString(),
                                    ),
                                    prefixIcon: FontAwesomeIcons.calendarAlt,
                                    onTapEditing: () async {
                                      final initial = DateTime.tryParse(
                                        pickings[0].scheduledDate ?? '',
                                      ) ?? DateTime.now();
                                      DateTime? pickedDate = await showDatePicker(
                                        context: context,
                                        initialDate: initial,
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime(2100),
                                      );
                                      if (pickedDate != null && context.mounted) {
                                        TimeOfDay? pickedTime = await showTimePicker(
                                          context: context,
                                          initialTime: TimeOfDay.fromDateTime(initial),
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
                                            scheduledDateController.text =
                                                formatDateTimeForDisplay(
                                              combined.toIso8601String(),
                                            );
                                          });
                                        }
                                      }
                                    },
                                  ),
                                  if (pickings[0].dateDeadline != null &&
                                      pickings[0].dateDeadline!.isNotEmpty)
                                    InfoRow(
                                      label: "Deadline",
                                      value: formatDateTimeForDisplay(
                                        pickings[0].dateDeadline,
                                      ),
                                      isEditing: _isEditing,
                                      prefixIcon: FontAwesomeIcons.calendarAlt,
                                      controller: deadlineController,
                                      color: getScheduledDateColor(
                                        pickings[0].dateDeadline ??
                                            DateTime.now().toString(),
                                      ),
                                      onTapEditing: () async {
                                        final initial = DateTime.tryParse(
                                          pickings[0].dateDeadline ?? '',
                                        ) ?? DateTime.now();
                                        DateTime? pickedDate = await showDatePicker(
                                          context: context,
                                          initialDate: initial,
                                          firstDate: DateTime(2000),
                                          lastDate: DateTime(2100),
                                        );
                                        if (pickedDate != null && context.mounted) {
                                          TimeOfDay? pickedTime = await showTimePicker(
                                            context: context,
                                            initialTime: TimeOfDay.fromDateTime(initial),
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
                                              deadlineController.text =
                                                  formatDateTimeForDisplay(
                                                combined.toIso8601String(),
                                              );
                                            });
                                          }
                                        }
                                      },
                                    ),
                                  if (pickings[0].state == 'done')
                                    InfoRow(
                                      label: "Effective Date",
                                      value: formatDateTimeForDisplay(
                                        pickings[0].dateDone,
                                      ),
                                      isEditing: _isEditing,
                                      controller: dateDoneController,
                                      prefixIcon: FontAwesomeIcons.calendarAlt,
                                      color: getScheduledDateColor(
                                        pickings[0].dateDone ??
                                            DateTime.now().toString(),
                                      ),
                                      onTapEditing: _isEditing
                                          ? () async {
                                              final initial = DateTime.tryParse(
                                                pickings[0].dateDone ?? '',
                                              ) ?? DateTime.now();
                                              DateTime? pickedDate = await showDatePicker(
                                                context: context,
                                                initialDate: initial,
                                                firstDate: DateTime(2000),
                                                lastDate: DateTime(2100),
                                              );
                                              if (pickedDate != null && context.mounted) {
                                                TimeOfDay? pickedTime = await showTimePicker(
                                                  context: context,
                                                  initialTime: TimeOfDay.fromDateTime(initial),
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
                                                    dateDoneController.text =
                                                        formatDateTimeForDisplay(
                                                      combined.toIso8601String(),
                                                    );
                                                  });
                                                }
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
                                ? Colors.black.withValues(alpha: 0.18)
                                : Colors.black.withValues(alpha: 0.06),
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
                                  DefaultTabController.of(context);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    padding: const EdgeInsets.all(4),
                                    child: AnimatedBuilder(
                                      animation: tabController.animation!,
                                      builder: (context, _) {
                                        final double animValue =
                                            tabController.animation!.value;
                                        return TabBar(
                                          controller: tabController,
                                          indicator: BoxDecoration(
                                            color: Colors.transparent,
                                          ),
                                          dividerColor: Colors.transparent,
                                          labelPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          overlayColor:
                                              WidgetStateProperty.all(
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
                                            final double selectedness =
                                                (1.0 -
                                                        (animValue - index)
                                                            .abs())
                                                    .clamp(0.0, 1.0);
                                            return _buildStyledTab(
                                              text,
                                              selectedness,
                                            );
                                          }),
                                        );
                                      },
                                    ),
                                  ),
                                  SizedBox(
                                    height: 300,
                                    child: TabBarView(
                                      controller: tabController,
                                      children: [
                                        _KeepAliveTab(child: _productTable(isDark)),
                                        _KeepAliveTab(child: _additionalInfo()),
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
                                final listOfUpdates = _buildHeaderUpdates();
                                if (listOfUpdates == null) return;
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
          ],
          if (_isLoading || isSaving || isCreateSaving) const LoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildStyledTab(String text, double selectedness) {
    final bgColor =
        Color.lerp(Colors.transparent, Colors.black, selectedness)!;
    final textColor =
        Color.lerp(Colors.grey[600], Colors.white, selectedness)!;
    final borderColor = Color.lerp(
      Colors.grey.shade400,
      Colors.transparent,
      selectedness,
    )!;
    return Tab(
      child: Container(
        width: 120,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: textColor,
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
      if (!discard) return false;
      setState(() {
        _isEditing = false;
        _resetEditSelections();
      });
      _syncControllersFromPicking();
      return true;
    }
    return true;
  }


  Widget _editProductLine(
    BuildContext context,
    StockMove product,
    int index,
    TextEditingController qtyController,
  ) {
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
                            itemAsString: (item) => item['name'] ?? '',
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
                      child: LoadingWidget(
                        size: 60,
                        variant: LoadingVariant.staggeredDots,
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
                        CustomSnackbar.showError(
                          context,
                          'Please select a product.',
                        );
                        return;
                      } else if (enteredQty > 0) {
                        if (pickings.isNotEmpty &&
                            ['done', 'cancel'].contains(pickings[0].state)) {
                          CustomSnackbar.showError(
                            context,
                            'Cannot edit a line on a ${pickings[0].state} picking.',
                          );
                          return;
                        }

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
                        final isOnline = isOnlineAvailability;
                        if (isOnline) {
                          try {
                            await odooPickingFormService.updateProductMove(
                              product.id,
                              selectedPicking!,
                              enteredQty,
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
                            if (!context.mounted) return;
                            setStateDialog(() => _isLoading = false);
                            Navigator.of(context).pop();
                            CustomSnackbar.showSuccess(
                              context,
                              'Product line updated.',
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            setStateDialog(() => _isLoading = false);
                            CustomSnackbar.showError(
                              context,
                              'Failed to update product: ${e.toString().replaceFirst('Exception: ', '')}',
                            );
                          }
                          return;
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
                        CustomSnackbar.showError(
                          context,
                          'Quantity must be greater than zero.',
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

  Widget _addProductLine(
    BuildContext context,
    TextEditingController qtyController,
  ) {
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
                          itemAsString: (item) => item['name'] ?? '',
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
                        if (selectedPicking == null || selectedPicking == 0) {
                          setState(() => isCreateSaving = false);
                          if (context.mounted) {
                            CustomSnackbar.showError(
                              context,
                              'Please select a product.',
                            );
                          }
                          return;
                        } else if (enteredQty > 0) {
                          if (pickings.isNotEmpty &&
                              ['done', 'cancel'].contains(pickings[0].state)) {
                            setState(() => isCreateSaving = false);
                            if (context.mounted) {
                              CustomSnackbar.showError(
                                context,
                                'Cannot add products to a ${pickings[0].state} picking.',
                              );
                            }
                            return;
                          }

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
                          final isOnline = isOnlineAvailability;

                          if (isOnline) {
                            try {
                              int? srcId;
                              int? destId;
                              
                              if (pickings.isNotEmpty) {
                                srcId = pickings[0].locationIdInt;
                                destId = pickings[0].locationDestIdInt;
                              }
                              
                              if (srcId == null || destId == null) {
                                srcId = int.tryParse(widget.picking['location_id_int']?.toString() ?? '');
                                destId = int.tryParse(widget.picking['location_dest_id_int']?.toString() ?? '');
                              }
                              
                              if (srcId == null || destId == null) {
                                final locations = await odooPickingFormService
                                    .getPickingLocations(pickingId);
                                srcId = locations.locationId;
                                destId = locations.locationDestId;
                              }

                              if (srcId == null || destId == null) {
                                throw Exception(
                                  'This picking has no source or destination location configured.',
                                );
                              }

                              if (_isEditing) {
                                final headerUpdates = _buildHeaderUpdates();
                                if (headerUpdates != null &&
                                    headerUpdates.isNotEmpty) {
                                  try {
                                    final saved = await odooPickingFormService
                                        .saveChanges(pickingId, headerUpdates)
                                        .timeout(
                                            const Duration(seconds: 15));
                                    if (!saved) {
                                      throw Exception(
                                        'Could not save your changes before '
                                        'adding the product.',
                                      );
                                    }
                                  } catch (e) {
                                    rethrow;
                                  }
                                }
                              }

                              final pickingState = pickings.isNotEmpty
                                  ? pickings[0].state
                                  : null;
                              await odooPickingFormService.addProductToLine(
                                pickingId,
                                selectedPicking!,
                                selectedPickingName ?? 'Unnamed',
                                selectedPickingUom ?? 1,
                                enteredQty,
                                srcId,
                                destId,
                                pickingState: pickingState,
                              );

                              if (pickings.isNotEmpty &&
                                  !['draft', 'cancel', 'done'].contains(pickings[0].state)) {
                                try {
                                  await odooPickingFormService
                                      .checkAvailability(pickingId);
                                } catch (e) {
                                  debugPrint('Check availability failed: $e');
                                }
                              }
                              await _loadSavingData();
                              if (!mounted) return;
                              setState(() {
                                isCreateSaving = false;
                                selectedPicking = 0;
                                selectedPickingName = null;
                              });
                              if (_isEditing) {
                                _syncControllersFromPicking();
                              }
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                CustomSnackbar.showSuccess(
                                  context,
                                  'Product added to the picking.',
                                );
                              }
                            } catch (e) {
                              if (!mounted) return;
                              setState(() => isCreateSaving = false);
                              if (context.mounted) {
                                CustomSnackbar.showError(
                                  context,
                                  'Failed to add product: ${e.toString().replaceFirst('Exception: ', '')}',
                                );
                              }
                            }
                            return;
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

                            if (_isEditing) {
                              final headerUpdates = _buildHeaderUpdates();
                              if (headerUpdates != null &&
                                  headerUpdates.isNotEmpty) {
                                await hiveService.savePendingUpdates(
                                  pickingId,
                                  {
                                    'title': widget.picking['item'] ??
                                        widget.picking['name'] ??
                                        'Picking Details',
                                    'partner_name': null,
                                    'user_name': null,
                                    'updates': headerUpdates,
                                  },
                                );
                              }
                            }
                          }
                          if (!mounted) return;
                          setState(() {
                            isCreateSaving = false;
                          });
                          if (!context.mounted) return;
                          Navigator.of(context).pop();
                          CustomSnackbar.showWarning(
                            context,
                            'No internet. Product addition queued for sync when online.',
                          );
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
                child: LoadingWidget(
                  size: 30,
                  color: AppStyle.primaryColor,
                  variant: LoadingVariant.staggeredDots,
                ),
              ),
            ),
        ],
      ),
    );
  }


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
            final qtyController =
                TextEditingController(text: product.quantity.toString());
            showDialog(
              context: context,
              builder: (context) =>
                  _editProductLine(context, product, index, qtyController),
            ).whenComplete(() {
              Future.delayed(
                const Duration(milliseconds: 400),
                qtyController.dispose,
              );
            });
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
            // Show a visible warning when moves are empty but the picking
            // is in a state that normally has products (assigned / confirmed).
            if (productRows.isEmpty &&
                ['assigned', 'confirmed', 'waiting'].contains(pickings[0].state) &&
                isOnlineAvailability)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.orange[700], size: 32),
                    const SizedBox(height: 8),
                    Text(
                      'Products could not be loaded from the server.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.orange[800],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This picking has products on the backend. '
                      'Tap Retry to try again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.grey[700],
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _fetchData,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ...productRows,
            const SizedBox(height: 12),
            if (pickings[0].state != 'done' && pickings[0].state != 'cancel')
              GestureDetector(
                onTap: () {
                  setState(() {
                    _errorMessage = "";
                    selectedPicking = 0;
                    selectedPickingName = null;
                    selectedPickingUom = null;
                  });
                  final qtyController = TextEditingController(text: '1');
                  showDialog(
                    context: context,
                    builder: (context) =>
                        _addProductLine(context, qtyController),
                  ).whenComplete(() {
                    Future.delayed(
                      const Duration(milliseconds: 400),
                      qtyController.dispose,
                    );
                  });
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
                          value:
                              _selectedShippingPolicy ??
                              (pickings.isNotEmpty
                                      ? pickings[0].moveType
                                      : null) ??
                              'direct',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'direct',
                              child: Text("As soon as possible"),
                            ),
                            DropdownMenuItem(
                              value: 'one',
                              child: Text("When all products are ready"),
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
                        picking.moveType == 'one'
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
          if (picking.groupId != null && picking.groupId!.length > 1) ...[
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
                  picking.groupId![1].toString(),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final String rawNote =
        (pickings.isNotEmpty ? (pickings[0].note ?? '') : '');
    final String plainNote =
        rawNote.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    final bool hasNote = plainNote.isNotEmpty;

    Widget body;
    if (_isEditing) {
      body = InfoRow(
        label: "Note",
        value: pickings.isNotEmpty ? pickings[0].note : '',
        isEditing: _isEditing,
        controller: _noteController,
        readOnly: pickings.isNotEmpty &&
            ['done', 'cancel'].contains(pickings[0].state),
        onTap: () {},
      );
    } else if (hasNote) {
      body = Text(
        plainNote,
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Colors.white : Colors.black87,
          height: 1.4,
        ),
      );
    } else {
      return _KeepAliveTab(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                HugeIcons.strokeRoundedNote,
                size: 32,
                color: isDark ? Colors.grey[600] : Colors.grey[400],
              ),
              const SizedBox(height: 8),
              Text(
                'No notes added for this delivery',
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: isDark ? Colors.grey[500] : Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _KeepAliveTab(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [body],
          ),
        ),
      ),
    );
  }
}

class _KeepAliveTab extends StatefulWidget {
  final Widget child;
  const _KeepAliveTab({required this.child});

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
