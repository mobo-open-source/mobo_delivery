import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:hive_ce/hive.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../../shared/widgets/loaders/delivery_shimmers.dart';
import '../../../../Rating/review_service.dart';
import '../../../../core/company/session/company_session_manager.dart';
import '../../../../core/navigation/data_loss_warning_dialog.dart';
import '../../../../shared/utils/date_picker_utils.dart';
import '../../../../shared/utils/globals.dart';
import '../../../../shared/widgets/buttons/mobo_button.dart';
import '../../../../shared/widgets/dialogs/common_dialog.dart';
import '../../../../shared/utils/odoo_datetime_format.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_state_widget.dart';
import '../../../../shared/widgets/inputs/mobo_text_field.dart';
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

  final ScrollController _tabHeaderScrollController = ScrollController();
  final List<GlobalKey> _tabItemKeys = List.generate(3, (_) => GlobalKey());

  List<Map<String, dynamic>> pickingStockLine = [];
  List<Map<String, dynamic>> returnDataList = [];

  String _errorMessage = '';
  bool _errorIsOffline = false;
  bool isDataAvailable = true;
  bool _isEditing = false;
  bool _isShippingPolicyOpen = false;

  /// Snapshot of the editable header fields taken when edit mode is entered.
  /// The "Save Delivery" button is only enabled while the current values
  /// differ from this baseline (i.e. the user actually changed something).
  String? _editBaseline;

  /// True when the header has unsaved edits relative to [_editBaseline].
  bool get _isHeaderDirty =>
      _editBaseline != null &&
      (_buildHeaderUpdates()?.toString() ?? '') != _editBaseline;

  /// Snapshot of [moveProducts] when edit mode was entered, used to revert on
  /// discard.
  List<StockMove>? _moveBaseline;

  /// Newly added (not-yet-saved) lines, identified by a negative temp id.
  final List<StockMove> _stagedNewMoves = [];

  /// Existing lines whose quantity/product was edited: backend moveId → value.
  final Map<int, StockMove> _stagedEditedMoves = {};

  /// Existing lines marked for deletion (backend move ids).
  final Set<int> _stagedDeletedMoveIds = {};

  /// Generates temp ids for staged new lines (negative, decreasing).
  int _tempMoveIdSeq = -1;

  bool get _hasStagedProductChanges =>
      _stagedNewMoves.isNotEmpty ||
      _stagedEditedMoves.isNotEmpty ||
      _stagedDeletedMoveIds.isNotEmpty;

  /// True when the picking has any unsaved edit (header OR product lines).
  bool get _isDeliveryDirty => _isHeaderDirty || _hasStagedProductChanges;

  void _clearStagedProductChanges() {
    _stagedNewMoves.clear();
    _stagedEditedMoves.clear();
    _stagedDeletedMoveIds.clear();
    _tempMoveIdSeq = -1;
    _moveBaseline = null;
  }

  /// Stages a new product line and rebuilds the page. Defined on the State so
  /// its `setState` is the page's — the add dialog's `StatefulBuilder` shadows
  /// `setState`, so mutating from inside it would only rebuild the dialog.
  void _stageNewMove(StockMove move) {
    setState(() {
      moveProducts.add(move);
      _stagedNewMoves.add(move);
    });
  }

  /// Re-evaluates the dirty state after a free-text edit (source document,
  /// note, dates). Deferred to the next frame so it is safe to fire while a
  /// controller's text is being set programmatically (sync / date pickers).
  void _onEditFieldChanged() {
    if (!_isEditing || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

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

    for (final c in [
      scheduledDateController,
      deadlineController,
      dateDoneController,
      sourceDocController,
      _noteController,
    ]) {
      c.addListener(_onEditFieldChanged);
    }
  }

  @override
  void dispose() {
    _tabHeaderScrollController.dispose();
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

  /// Scrolls the tab header ListView so the pill at [index] is fully visible.
  /// Called after any tab change (tap or swipe) via a post-frame callback so
  /// the item is already laid out before we measure its position.
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
      final available = await OdooPickingFormService()
          .checkNetworkConnectivity();
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
    final odooPickingFormService = OdooPickingFormService();
    if (mounted) {
      setState(() {
        isDataAvailable = true;
        _errorMessage = '';
        _errorIsOffline = false;
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
      } catch (_) {}

      if (isOnline) {
        try {
          await _loadOnlineData();
        } catch (_) {}
      }
    } catch (e) {
    } finally {
      if (mounted) {
        setState(() {
          isDataAvailable = false;
          if (pickings.isEmpty) {
            _errorIsOffline = !isOnline;
            _errorMessage = isOnline
                ? "Couldn't load this picking. It may have been deleted or you don't have access."
                : "You're offline and this picking isn't cached yet. Reconnect and try again.";
          }
        });
      }
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

    final results = await Future.wait<dynamic>([
      odooPickingFormService.loadPickings(pickingId),
      odooPickingFormService.loadProductMoves(pickingId).catchError((e, st) {
        return moveProducts;
      }),
    ]);

    final freshPickings = results[0] as List<PickingForm>;
    final freshMoves = results[1] as List<StockMove>;

    if (freshPickings.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    if (_cachedImage == null) {
      final partnerId = freshPickings[0].partnerId?.isNotEmpty == true
          ? freshPickings[0].partnerId![0]
          : null;
      if (partnerId != null) {
        partnerDetails = await odooPickingFormService.loadPartnerDetails(
          partnerId,
        );
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

    final partnerIdForDetails =
        (pickings.isNotEmpty &&
            pickings[0].partnerId != null &&
            pickings[0].partnerId!.isNotEmpty)
        ? pickings[0].partnerId![0]
        : null;

    final results = await Future.wait<dynamic>([
      odooPickingFormService.loadProductMoves(pickingId).catchError((e, st) {
        if (mounted) {
          final msg = _extractOdooError(
            e,
            'Could not load products. '
            'Check your connection or contact your administrator.',
          );
          CustomSnackbar.showError(context, msg);
        }
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
  Future<void> _loadEditModeDropdowns(OdooPickingFormService service) async {
    try {
      final results = await Future.wait<dynamic>([
        service.loadProducts().catchError((e) {
          return <Product>[];
        }),
        service.loadPartners().catchError((e) {
          return <Partner>[];
        }),
        service.loadUsers().catchError((e) {
          return <User>[];
        }),
        service.loadOperationTypes().catchError((e) {
          return <Map<String, dynamic>>[];
        }),
      ]);
      if (!mounted) return;
      final freshProducts =
          (results[0] as List?)?.cast<Product>() ?? <Product>[];
      final freshPartners =
          (results[1] as List?)?.cast<Partner>() ?? <Partner>[];
      final freshUsers = (results[2] as List?)?.cast<User>() ?? <User>[];
      final freshOpTypes =
          (results[3] as List?)?.cast<Map<String, dynamic>>() ??
          <Map<String, dynamic>>[];
      setState(() {
        if (freshProducts.isNotEmpty) products = freshProducts;
        if (freshPartners.isNotEmpty) partnerList = freshPartners;
        if (freshUsers.isNotEmpty) userList = freshUsers;
        if (freshOpTypes.isNotEmpty) operationTypesList = freshOpTypes;
      });
    } catch (e) {}
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
          : (pickings[0].partnerId == null || pickings[0].partnerId!.isEmpty)
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

    final argsMatch = RegExp(
      r'"arguments":\s*\[\s*"((?:[^"\\]|\\.)*)"',
    ).firstMatch(raw);
    if (argsMatch != null) {
      final unescaped = _unescapeJsonString(argsMatch.group(1)!);
      if (unescaped.trim().isNotEmpty) return unescaped;
    }

    final msgMatch = RegExp(
      r'"message":\s*"((?:[^"\\]|\\.)*)"',
    ).firstMatch(raw);
    if (msgMatch != null) {
      final unescaped = _unescapeJsonString(msgMatch.group(1)!);
      if (unescaped.trim().isNotEmpty) return unescaped;
    }

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

    final dataMatch = RegExp(r'data\.message["\s:]+([^"}\n]+)').firstMatch(raw);
    if (dataMatch != null) {
      final candidate = dataMatch.group(1)!.trim();
      if (candidate.isNotEmpty) return candidate;
    }

    const exPrefix = 'Exception: ';
    if (raw.startsWith(exPrefix)) {
      final msg = raw.substring(exPrefix.length).trim();
      if (msg.isNotEmpty && msg.length < 400) return msg;
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
    if (moveProducts.isEmpty) {
      CustomSnackbar.showWarning(
        context,
        'You can’t validate an empty transfer. Please add some products to move before proceeding.',
      );
      return;
    }

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
        try {
          final pickingData = pickings.firstWhere((p) => p.id == pickingId);
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
    setState(() => isSaving = true);
    try {
      await odooPickingFormService.initializeOdooClient();
      final pickingId = int.parse(widget.picking['id'].toString());
      final stateBefore = pickings.isNotEmpty ? pickings[0].state : '';
      final success = await odooPickingFormService.checkAvailability(pickingId);
      if (success) {
        await _loadSavingData();
        if (mounted) {
          final stateAfter = pickings.isNotEmpty ? pickings[0].state : '';
          if (stateAfter == 'assigned' && stateBefore != 'assigned') {
            CustomSnackbar.showSuccess(
              context,
              'Products reserved — picking is now Ready.',
            );
          } else {
            CustomSnackbar.showInfo(
              context,
              'No additional products could be reserved.',
            );
          }
        }
      } else {
        if (mounted) {
          CustomSnackbar.showError(context, 'Failed to check availability.');
        }
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
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
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: PickingBottomSheet(
            picking: widget.picking,
            odooService: OdooReturnManagementService(),
            onReturnCreated: () async {
              await _loadSavingData();
            },
          ),
        ),
      ),
    );
  }

  /// Behavior:
  /// - Online: fetches fresh return data from Odoo → caches each return in Hive
  /// - Offline: uses cached returns from Hive 'return_pickings' box
  ///
  /// After loading data (cached or fresh), opens the returns dialog.
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
          final loadedReturnData = cachedReturns.map((e) => e.data).toList();
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
          final partner = rawPartner is List ? rawPartner : const <dynamic>[];
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

    _showReturnsDialog(returnDataList, odooPickingFormService);
  }

  void _showReturnsDialog(
    List<Map<String, dynamic>> returns,
    OdooPickingFormService service,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 40,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Return Pickings',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                      IconButton(
                        splashRadius: 20,
                        icon: Icon(
                          HugeIcons.strokeRoundedCancel01,
                          color: isDark ? Colors.white : Colors.black54,
                        ),
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: returns.isEmpty
                        ? const EmptyState(
                            title: 'No Return Pickings Found',
                            subtitle: 'There are no return pickings available.',
                            padding: EdgeInsets.symmetric(vertical: 24),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.only(right: 8),
                            itemCount: returns.length,
                            itemBuilder: (_, i) => _buildReturnDialogCard(
                              returns[i],
                              isDark,
                              dialogCtx,
                              service,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReturnDialogCard(
    Map<String, dynamic> data,
    bool isDark,
    BuildContext dialogCtx,
    OdooPickingFormService service,
  ) {
    final state = (data['state'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.pop(dialogCtx);
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, _) => PickingDetailsPage(
                  picking: {...data, 'item': data['name'] ?? 'Return Picking'},
                  odooService: service,
                  isPickingForm: false,
                  isReturnCreate: false,
                  isReturnPicking: true,
                ),
                transitionsBuilder: (context, animation, _, child) =>
                    FadeTransition(opacity: animation, child: child),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        cleanOdooValue(data['name']),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppStyle.accentOf(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildStatusIndicator(state),
                  ],
                ),
                const SizedBox(height: 8),
                _buildReturnKv(
                  'Partner:',
                  cleanOdooValue(data['partner_id']),
                  isDark,
                ),
                const SizedBox(height: 4),
                _buildReturnKv(
                  'Scheduled:',
                  cleanOdooValue(data['scheduled_date']),
                  isDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReturnKv(String label, String value, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[500] : Colors.grey[500],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey[300] : Colors.grey[700],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  void _resetEditSelections() {
    selectedPartnerId = null;
    _selectedUserId = null;
    _selectedShippingPolicy = null;
    _selectedPickingTypeId = null;
    _selectedLocationId = null;
    _selectedLocationDestId = null;
    _clearStagedProductChanges();
  }

  void _syncControllersFromPicking() {
    if (pickings.isEmpty) return;
    final p = pickings[0];
    scheduledDateController.text = formatDateTimeForDisplay(p.scheduledDate);
    deadlineController.text = formatDateTimeForDisplay(p.dateDeadline);
    dateDoneController.text = formatDateTimeForDisplay(p.dateDone);
    sourceDocController.text = p.origin ?? '';
    _noteController.text = (p.note ?? '').replaceAll(RegExp(r'<[^>]*>'), '');

    if (_isEditing) {
      _editBaseline = _buildHeaderUpdates()?.toString() ?? '';
    }
  }

  Map<String, dynamic>? _buildHeaderUpdates() {
    if (pickings.isEmpty) return null;
    final p = pickings[0];
    final int? existingPartnerId = (p.partnerId?.isNotEmpty ?? false)
        ? p.partnerId![0] as int?
        : null;
    final int? existingUserId = (p.userId?.isNotEmpty ?? false)
        ? p.userId![0] as int?
        : null;

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
      'move_type': _selectedShippingPolicy ?? p.moveType ?? 'direct',
      'user_id': _selectedUserId ?? existingUserId,
      'note': _noteController.text,
      'picking_type_id':
          _selectedPickingTypeId ??
          ((p.pickingTypeId?.isNotEmpty ?? false) ? p.pickingTypeId![0] : null),
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
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Could not save: this picking has an invalid id.',
        );
      }
      return;
    }

    final odooPickingFormService = OdooPickingFormService();

    try {
      await odooPickingFormService.initializeOdooClient();
    } catch (e) {
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
      if (isOnline) {
        final success = await odooPickingFormService
            .saveChanges(pickingId, updatedListOfUpdates)
            .timeout(const Duration(seconds: 15));
        if (success) {
          try {
            await _loadSavingData().timeout(const Duration(seconds: 15));
          } catch (e) {
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
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Could not save changes. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  /// Resolves the source/destination location ids for a picking, trying the
  /// loaded picking, the route arguments, then a backend lookup.
  Future<({int? srcId, int? destId})> _resolvePickingLocations(
    int pickingId,
    OdooPickingFormService service,
  ) async {
    int? srcId;
    int? destId;
    if (pickings.isNotEmpty) {
      srcId = pickings[0].locationIdInt;
      destId = pickings[0].locationDestIdInt;
    }
    if (srcId == null || destId == null) {
      srcId = int.tryParse(widget.picking['location_id_int']?.toString() ?? '');
      destId = int.tryParse(
        widget.picking['location_dest_id_int']?.toString() ?? '',
      );
    }
    if (srcId == null || destId == null) {
      final locations = await service.getPickingLocations(pickingId);
      srcId = locations.locationId;
      destId = locations.locationDestId;
    }
    return (srcId: srcId, destId: destId);
  }

  /// Commits the whole delivery edit: staged product-line changes (add / edit /
  /// delete) plus the header, in one "Save Delivery" action. When there are no
  /// staged product changes it delegates to [_saveChanges] (header only).
  Future<void> _commitDelivery(String title) async {
    final headerUpdates = _buildHeaderUpdates() ?? <String, dynamic>{};

    if (!_hasStagedProductChanges) {
      await _saveChanges(headerUpdates, title);
      return;
    }

    final int pickingId;
    try {
      pickingId = int.parse(widget.picking['id'].toString());
    } catch (_) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Could not save: this picking has an invalid id.',
        );
      }
      return;
    }

    final service = OdooPickingFormService();
    try {
      await service.initializeOdooClient();
    } catch (_) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Could not save: session is not ready. Please try again.',
        );
      }
      return;
    }

    if (mounted) setState(() => isSaving = true);
    final isOnline = isOnlineAvailability;

    try {
      if (isOnline) {
        if (_isHeaderDirty && headerUpdates.isNotEmpty) {
          final ok = await service
              .saveChanges(pickingId, headerUpdates)
              .timeout(const Duration(seconds: 20));
          if (!ok) throw Exception('Failed to save the delivery details.');
        }
        for (final moveId in _stagedDeletedMoveIds) {
          await service.deleteProductMove(moveId, pickingId);
        }
        for (final entry in _stagedEditedMoves.entries) {
          await service.updateProductMove(
            entry.key,
            entry.value.productId![0] as int,
            entry.value.quantity,
          );
        }
        if (_stagedNewMoves.isNotEmpty) {
          final loc = await _resolvePickingLocations(pickingId, service);
          if (loc.srcId == null || loc.destId == null) {
            throw Exception(
              'This picking has no source or destination location configured.',
            );
          }
          final pickingState = pickings.isNotEmpty ? pickings[0].state : null;
          for (final m in _stagedNewMoves) {
            await service.addProductToLine(
              pickingId,
              m.productId![0] as int,
              (m.productId!.length > 1 ? m.productId![1] : 'Unnamed')
                  .toString(),
              m.productUomId ?? 1,
              m.productUomQty,
              loc.srcId!,
              loc.destId!,
              pickingState: pickingState,
            );
          }
          if (pickings.isNotEmpty &&
              !['draft', 'cancel', 'done'].contains(pickings[0].state)) {
            try {
              await service.checkAvailability(pickingId);
            } catch (e) {}
          }
        }
        try {
          await _loadSavingData().timeout(const Duration(seconds: 15));
        } catch (_) {
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
          CustomSnackbar.showSuccess(context, 'Delivery saved.');
        }
      } else {
        if (_isHeaderDirty && headerUpdates.isNotEmpty) {
          await _hiveService.savePendingUpdates(pickingId, {
            'title': title,
            'partner_name': null,
            'user_name': null,
            'updates': headerUpdates,
          });
        }
        final locationIdInt = int.tryParse(
          widget.picking['location_id_int']?.toString() ?? '',
        );
        final locationDestIdInt = int.tryParse(
          widget.picking['location_dest_id_int']?.toString() ?? '',
        );
        for (final m in _stagedNewMoves) {
          await _hiveService.savePendingProductUpdates(
            pickingId,
            {
              'move': {
                'product_id': m.productId,
                'quantity': m.quantity,
                'quantity_product_uom': '',
              },
              'pickingId': pickingId,
              'pickingName': title,
            },
            (m.productId!.length > 1 ? m.productId![1] : 'Unnamed').toString(),
          );
        }
        for (final entry in _stagedEditedMoves.entries) {
          await _hiveService.savePendingProductUpdates(pickingId, {
            'move': entry.value.toJson(),
            'timestamp': DateTime.now(),
            'location_id_int': locationIdInt,
            'location_dest_id_int': locationDestIdInt,
          }, title);
        }
        if (mounted) {
          final hadDeletes = _stagedDeletedMoveIds.isNotEmpty;
          setState(() {
            _isEditing = false;
            _resetEditSelections();
          });
          CustomSnackbar.showWarning(
            context,
            hadDeletes
                ? 'Saved offline. Line removals will apply once back online.'
                : 'Changes saved offline. Will sync when online.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Could not save: ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
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
    final rawResId = action['res_id'];
    final wizardId = rawResId is int
        ? rawResId
        : rawResId is double
        ? rawResId.toInt()
        : null;
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
      builder: (ctx) => CommonDialog(
        title: 'Send SMS?',
        message:
            'Odoo can notify the customer that this delivery has been processed. '
            'Send an SMS now, or validate without notifying?',
        secondaryLabel: "Don't Send",
        onSecondary: () async {
          Navigator.of(ctx).pop();
          await callWizardWithFallback(const [
            'dont_send_sms',
            'action_cancel',
          ]);
        },
        primaryLabel: 'Send SMS',
        onPrimary: () async {
          Navigator.of(ctx).pop();
          await callWizardWithFallback(const ['send_sms', 'action_send_sms']);
        },
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
      builder: (ctx) => CommonDialog(
        title: title,
        message: message,
        secondaryLabel: 'Cancel',
        onSecondary: () => Navigator.of(ctx).pop(),
        primaryLabel: confirmLabel,
        onPrimary: () async {
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
                _extractOdooError(e, 'Failed to complete $wizardModel.'),
              );
            }
          } finally {
            if (mounted) setState(() => isSaving = false);
          }
        },
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

  Future<int?> _resolveWizardId(
    String model,
    int pickingId,
    dynamic action,
  ) async {
    final rawId = action is Map ? action['res_id'] : null;
    if (rawId is int && rawId > 0) return rawId;
    if (rawId is double && rawId > 0) return rawId.toInt();

    final ctx = _wizardContext(pickingId, action);
    final created = await CompanySessionManager.callKwWithCompany({
      'model': model,
      'method': 'create',
      'args': [{}],
      'kwargs': {'context': ctx},
    });
    if (created is int && created > 0) return created;
    if (created is double && created > 0) return created.toInt();
    return null;
  }

  Future<void> _showImmediateTransferDialog(int pickingId, success) async {
    int? wizardId;
    try {
      wizardId = await _resolveWizardId(
        'stock.immediate.transfer',
        pickingId,
        success,
      );
    } catch (e) {
      if (!mounted) return;
      CustomSnackbar.showError(
        context,
        _extractOdooError(e, 'Failed to prepare immediate transfer wizard.'),
      );
      return;
    }
    if (wizardId == null) {
      if (!mounted) return;
      CustomSnackbar.showError(
        context,
        'Failed to prepare immediate transfer: wizard ID could not be resolved.',
      );
      return;
    }
    final wId = wizardId;

    await showDialog(
      context: context,
      builder: (context) => CommonDialog(
        title: 'Immediate Transfer?',
        message:
            'You have not recorded any quantities. Odoo will mark all products as done immediately. Do you want to proceed?',
        secondaryLabel: 'Cancel',
        onSecondary: () => Navigator.of(context).pop(),
        primaryLabel: 'Confirm',
        onPrimary: () async {
          Navigator.of(context).pop();
          setState(() => isSaving = true);
          try {
            await CompanySessionManager.callKwWithCompany({
              'model': 'stock.immediate.transfer',
              'method': 'process',
              'args': [
                [wId],
              ],
              'kwargs': {'context': _wizardContext(pickingId, success)},
            });
            await _loadSavingData();
            if (mounted) {
              CustomSnackbar.showSuccess(
                context,
                'Transfer validated successfully.',
              );
            }
          } catch (e) {
            if (mounted) {
              final msg = _extractOdooError(
                e,
                'Failed to process immediate transfer.',
              );
              CustomSnackbar.showError(context, msg);
            }
          } finally {
            if (mounted) setState(() => isSaving = false);
          }
        },
      ),
    );
  }

  Future<void> _showBackorderDialog(int pickingId, success) async {
    int? wizardId;
    try {
      wizardId = await _resolveWizardId(
        'stock.backorder.confirmation',
        pickingId,
        success,
      );
    } catch (e) {
      if (!mounted) return;
      CustomSnackbar.showError(
        context,
        _extractOdooError(e, 'Failed to prepare backorder wizard.'),
      );
      return;
    }
    if (wizardId == null) {
      if (!mounted) return;
      CustomSnackbar.showError(
        context,
        'Failed to prepare backorder wizard: ID could not be resolved.',
      );
      return;
    }
    final wId = wizardId;

    await showDialog(
      context: context,
      builder: (context) => CommonDialog(
        title: 'Create Backorder?',
        message:
            'Some products are not fully available. Would you like to create a backorder for the remaining quantities, or validate only what is available?',
        secondaryLabel: 'No Backorder',
        onSecondary: () async {
          Navigator.of(context).pop();
          setState(() => isSaving = true);
          try {
            await CompanySessionManager.callKwWithCompany({
              'model': 'stock.backorder.confirmation',
              'method': 'process_cancel_backorder',
              'args': [
                [wId],
              ],
              'kwargs': {'context': _wizardContext(pickingId, success)},
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
              final msg = _extractOdooError(
                e,
                'Failed to validate without backorder.',
              );
              CustomSnackbar.showError(context, msg);
            }
          }
        },
        primaryLabel: 'Create Backorder',
        onPrimary: () async {
          Navigator.of(context).pop();
          setState(() => isSaving = true);
          try {
            await CompanySessionManager.callKwWithCompany({
              'model': 'stock.backorder.confirmation',
              'method': 'process',
              'args': [
                [wId],
              ],
              'kwargs': {'context': _wizardContext(pickingId, success)},
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
      ),
    );
  }

  String formatToOdooDatetime(String input) =>
      OdooDateTimeFormat.toOdooStorage(input);

  String formatDateTimeForDisplay(String? input) =>
      OdooDateTimeFormat.formatForDisplay(input);

  /// Builds a Mobo-style status badge matching the CRM design.
  Widget _buildStatusIndicator(String status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    const Color statusGreen = Color(0xFF00A63E);
    const Color statusBlue = Color(0xFF3B82F6);
    const Color statusOrange = Color(0xFFF97316);
    const Color statusRed = Color(0xFFEF4444);
    const Color statusGrey = Color(0xFF6B7280);

    Color color;
    String label;

    switch (status.toLowerCase()) {
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
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.15)
            : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : color,
          letterSpacing: 0.1,
        ),
      ),
    );
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
            Scaffold(
              backgroundColor: isDark ? Colors.grey[900] : Colors.white,
              appBar: AppBar(
                forceMaterialTransparency: true,
                backgroundColor: isDark ? Colors.grey[900] : Colors.white,
                leading: IconButton(
                  icon: Icon(
                    HugeIcons.strokeRoundedArrowLeft01,
                    color: isDark ? Colors.white : Colors.black,
                    size: 28,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              body: ErrorStateWidget(
                errorMessage: _errorIsOffline ? null : _errorMessage,
                onRetry: _fetchData,
              ),
            )
          else if (isDataAvailable) ...[
            Scaffold(
              backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
              appBar: AppBar(
                forceMaterialTransparency: true,
                backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
                title: Text(
                  'Picking Details',
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
              body: PickingDetailShimmer(isDark: isDark),
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
              bottomNavigationBar:
                  _isEditing &&
                      pickings.isNotEmpty &&
                      !['done', 'cancel'].contains(pickings[0].state)
                  ? SafeArea(
                      top: false,
                      left: false,
                      right: false,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                            onPressed: _isDeliveryDirty
                                ? () async {
                                    await _commitDelivery(
                                      widget.picking['item'] ??
                                          widget.picking['name'] ??
                                          'Picking Details',
                                    );
                                  }
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
                              'Save Delivery',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : null,
              appBar: AppBar(
                forceMaterialTransparency: true,
                backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
                title: Text(
                  _isEditing ? 'Edit Picking' : 'Picking Details',
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
                    IconButton(
                      onPressed: _stockMoveLine,
                      tooltip: 'Detailed Operations',
                      icon: Icon(
                        HugeIcons.strokeRoundedPackageSearch,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    if (pickings.isNotEmpty && pickings[0].returnCount > 0)
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            onPressed: _returnPicking,
                            tooltip: 'View Returns',
                            icon: Icon(
                              HugeIcons.strokeRoundedDeliveryReturn02,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: AppStyle.primaryColor,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${pickings[0].returnCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    if (pickings.isNotEmpty &&
                        !['done', 'cancel'].contains(pickings[0].state)) ...[
                      IconButton(
                        onPressed: () async {
                          setState(() {
                            _isEditing = true;

                            _editBaseline =
                                _buildHeaderUpdates()?.toString() ?? '';
                            _moveBaseline = List<StockMove>.from(moveProducts);
                            _stagedNewMoves.clear();
                            _stagedEditedMoves.clear();
                            _stagedDeletedMoveIds.clear();
                            _tempMoveIdSeq = -1;
                          });
                          if (partnerList.isEmpty ||
                              operationTypesList.isEmpty ||
                              userList.isEmpty ||
                              products.isEmpty) {
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
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: TextButton(
                          onPressed: _openCreateReturnSheet,
                          style: TextButton.styleFrom(
                            foregroundColor: AppStyle.primaryColor,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Return',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
                            HugeIcons.strokeRoundedMoreVertical,
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
                                      const Icon(
                                        HugeIcons.strokeRoundedTask01,
                                        color: Colors.green,
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
                                        HugeIcons.strokeRoundedSearch01,
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
                              if (!['draft'].contains(pickings[0].state))
                                PopupMenuItem(
                                  value: 'validate',
                                  child: Row(
                                    children: [
                                      const Icon(
                                        HugeIcons
                                            .strokeRoundedCheckmarkCircle02,
                                        color: Colors.green,
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
                                    const Icon(
                                      HugeIcons.strokeRoundedCancelCircle,
                                      color: Colors.red,
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
              body: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                behavior: HitTestBehavior.opaque,
                child: RefreshIndicator(
                  onRefresh: _isEditing ? () async {} : _fetchData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
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
                                fontWeight: FontWeight.w500,
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
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
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
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      pickings[0].name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppStyle.primaryColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildStatusIndicator(pickings[0].state),
                                ],
                              ),
                              if (pickings[0].partnerId != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  pickings[0].partnerId?[1]?.toString() ??
                                      'Unknown',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                if ((partnerDetails?['address'] ?? '')
                                    .toString()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    partnerDetails!['address'].toString(),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.black54,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ],
                              if ((pickings[0].scheduledDate ?? '')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Icon(
                                      HugeIcons.strokeRoundedCalendar03,
                                      size: 13,
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.black45,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      pickings[0].scheduledDate!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
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
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
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
                                        prefixIcon:
                                            HugeIcons.strokeRoundedLocation01,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                        dropdownItems: partnerList
                                            .map((p) => p.toJson())
                                            .toList(),
                                        selectedId:
                                            selectedPartnerId ??
                                            (pickings[0]
                                                        .partnerId
                                                        ?.isNotEmpty ??
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
                                        selectedId:
                                            _selectedPickingTypeId ??
                                            ((pickings[0]
                                                        .pickingTypeId
                                                        ?.isNotEmpty ??
                                                    false)
                                                ? pickings[0].pickingTypeId![0]
                                                : null),
                                        onDropdownChanged: (value) {
                                          setState(() {
                                            _selectedPickingTypeId =
                                                value?['id'];
                                            _selectedLocationId =
                                                value?['default_location_src_id_int'];
                                            _selectedLocationDestId =
                                                value?['default_location_dest_id_int'];
                                          });
                                        },
                                        prefixIcon:
                                            HugeIcons.strokeRoundedTask01,
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
                                        prefixIcon:
                                            HugeIcons.strokeRoundedCalendar03,
                                        onTapEditing: () async {
                                          final initial =
                                              DateTime.tryParse(
                                                pickings[0].scheduledDate ?? '',
                                              ) ??
                                              DateTime.now();
                                          DateTime? pickedDate =
                                              await DatePickerUtils.showStandardDatePicker(
                                                context: context,
                                                initialDate: initial,
                                                firstDate: DateTime(2000),
                                                lastDate: DateTime(2100),
                                              );
                                          if (pickedDate != null &&
                                              context.mounted) {
                                            TimeOfDay? pickedTime =
                                                await DatePickerUtils.showStandardTimePicker(
                                                  context: context,
                                                  initialTime:
                                                      TimeOfDay.fromDateTime(
                                                        initial,
                                                      ),
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
                                                      combined
                                                          .toIso8601String(),
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
                                          prefixIcon:
                                              HugeIcons.strokeRoundedCalendar03,
                                          controller: deadlineController,
                                          color: getScheduledDateColor(
                                            pickings[0].dateDeadline ??
                                                DateTime.now().toString(),
                                          ),
                                          onTapEditing: () async {
                                            final initial =
                                                DateTime.tryParse(
                                                  pickings[0].dateDeadline ??
                                                      '',
                                                ) ??
                                                DateTime.now();
                                            DateTime? pickedDate =
                                                await DatePickerUtils.showStandardDatePicker(
                                                  context: context,
                                                  initialDate: initial,
                                                  firstDate: DateTime(2000),
                                                  lastDate: DateTime(2100),
                                                );
                                            if (pickedDate != null &&
                                                context.mounted) {
                                              TimeOfDay? pickedTime =
                                                  await DatePickerUtils.showStandardTimePicker(
                                                    context: context,
                                                    initialTime:
                                                        TimeOfDay.fromDateTime(
                                                          initial,
                                                        ),
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
                                                        combined
                                                            .toIso8601String(),
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
                                          prefixIcon:
                                              HugeIcons.strokeRoundedCalendar03,
                                          color: getScheduledDateColor(
                                            pickings[0].dateDone ??
                                                DateTime.now().toString(),
                                          ),
                                          onTapEditing: _isEditing
                                              ? () async {
                                                  final initial =
                                                      DateTime.tryParse(
                                                        pickings[0].dateDone ??
                                                            '',
                                                      ) ??
                                                      DateTime.now();
                                                  DateTime? pickedDate =
                                                      await DatePickerUtils.showStandardDatePicker(
                                                        context: context,
                                                        initialDate: initial,
                                                        firstDate: DateTime(
                                                          2000,
                                                        ),
                                                        lastDate: DateTime(
                                                          2100,
                                                        ),
                                                      );
                                                  if (pickedDate != null &&
                                                      context.mounted) {
                                                    TimeOfDay? pickedTime =
                                                        await DatePickerUtils.showStandardTimePicker(
                                                          context: context,
                                                          initialTime:
                                                              TimeOfDay.fromDateTime(
                                                                initial,
                                                              ),
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
                                                        dateDoneController
                                                                .text =
                                                            formatDateTimeForDisplay(
                                                              combined
                                                                  .toIso8601String(),
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
                                        _buildAvailabilityField(
                                          isDark: isDark,
                                          isEditing: _isEditing,
                                          availability:
                                              pickings[0].productsAvailability,
                                        ),
                                      InfoRow(
                                        label: "Source Document",
                                        value: pickings[0].origin,
                                        isEditing: _isEditing,
                                        prefixIcon:
                                            HugeIcons.strokeRoundedFile01,
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
                          margin: const EdgeInsets.only(bottom: 16),
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
                                      margin: const EdgeInsets.only(bottom: 12),
                                      height: 40,
                                      child: MediaQuery(
                                        data: MediaQuery.of(context).copyWith(
                                          textScaler: MediaQuery.of(context)
                                              .textScaler
                                              .clamp(maxScaleFactor: 1.1),
                                        ),
                                        child: ListView.separated(
                                          controller:
                                              _tabHeaderScrollController,
                                          scrollDirection: Axis.horizontal,
                                          physics:
                                              const ClampingScrollPhysics(),
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
                                                return Center(
                                                  child: GestureDetector(
                                                    key: _tabItemKeys[index],
                                                    onTap: () {
                                                      tabController.animateTo(
                                                        index,
                                                      );
                                                      _ensureTabVisible(index);
                                                    },
                                                    child: _buildPillTab(
                                                      label: labels[index],
                                                      isSelected:
                                                          tabController.index ==
                                                          index,
                                                      isDark: isDark,
                                                    ),
                                                  ),
                                                );
                                              },
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: double.infinity,

                                      constraints: const BoxConstraints(
                                        minHeight: 240,
                                      ),
                                      clipBehavior: Clip.antiAliasWithSaveLayer,
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.grey[850]
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: isDark
                                                ? Colors.black.withValues(
                                                    alpha: 0.18,
                                                  )
                                                : Colors.black.withValues(
                                                    alpha: 0.06,
                                                  ),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onHorizontalDragEnd: (details) {
                                          final v =
                                              details.primaryVelocity ?? 0;
                                          if (v < -250 &&
                                              tabController.index < 2) {
                                            final next =
                                                tabController.index + 1;
                                            tabController.animateTo(next);
                                            _ensureTabVisible(next);
                                          } else if (v > 250 &&
                                              tabController.index > 0) {
                                            final prev =
                                                tabController.index - 1;
                                            tabController.animateTo(prev);
                                            _ensureTabVisible(prev);
                                          }
                                        },
                                        child: ListenableBuilder(
                                          listenable: tabController,
                                          builder: (context, _) {
                                            switch (tabController.index) {
                                              case 1:
                                                return _additionalInfo();
                                              case 2:
                                                return _notesTab();
                                              default:
                                                return _productTable(isDark);
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
                  ),
                ),
              ),
            ),
          ],
          if (_isLoading || isSaving || isCreateSaving) const LoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildAvailabilityField({
    required bool isDark,
    required bool isEditing,
    required String? availability,
  }) {
    final isAvailable = availability?.toLowerCase() == 'available';
    final display =
        (availability == null ||
            availability.isEmpty ||
            availability.toLowerCase() == 'false')
        ? 'Not Available'
        : availability;

    if (!isEditing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Product Availability',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            Expanded(
              child: Text(
                display,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontWeight: FontWeight.normal,
                  color: isAvailable ? Colors.green : Colors.orange[700],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Product Availability',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: isDark ? Colors.white70 : const Color(0xff7F7F7F),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => CustomSnackbar.showInfo(
              context,
              'Product Availability cannot be edited here.',
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: isDark
                    ? const Color(0xFF2A2A2A)
                    : const Color(0xFFF2F4F6),
                border: Border.all(color: Colors.transparent, width: 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    HugeIcons.strokeRoundedPackage,
                    size: 20,
                    color: isDark ? Colors.white54 : const Color(0xff7F7F7F),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      display,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  Icon(
                    HugeIcons.strokeRoundedLock,
                    size: 14,
                    color: isDark ? Colors.white24 : Colors.grey[400],
                  ),
                ],
              ),
            ),
          ),
        ],
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

        if (_moveBaseline != null) {
          moveProducts = List<StockMove>.from(_moveBaseline!);
        }
        _resetEditSelections();
      });
      _syncControllersFromPicking();

      return false;
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
    bool isDropdownOpen = false;
    return StatefulBuilder(
      builder: (context, setStateDialog) {
        return AlertDialog(
          backgroundColor: isDark ? Colors.grey[850] : Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Edit Product Line',
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.95,
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RequiredLabel(
                      "Product",
                      isRequired: true,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white60 : Colors.black87,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: isDark
                            ? const Color(0xFF2A2A2A)
                            : const Color(0xFFF8FAFB),
                        border: Border.all(
                          color: isDropdownOpen
                              ? AppStyle.primaryColor
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: DropdownSearch<Product>(
                        onBeforePopupOpening: (_) async {
                          setStateDialog(() => isDropdownOpen = true);
                          return true;
                        },
                        popupProps: PopupProps.menu(
                          onDismissed: () =>
                              setStateDialog(() => isDropdownOpen = false),
                          menuProps: MenuProps(
                            backgroundColor: isDark
                                ? Colors.grey[900]
                                : Colors.white,
                            elevation: 8,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          showSearchBox: true,
                          searchFieldProps: TextFieldProps(
                            decoration: InputDecoration(
                              hintText: 'Search products...',
                              hintStyle: GoogleFonts.manrope(
                                fontWeight: FontWeight.w400,
                                color: isDark
                                    ? Colors.white54
                                    : Colors.grey[500],
                                fontStyle: FontStyle.italic,
                              ),
                              prefixIcon: Icon(
                                HugeIcons.strokeRoundedSearch01,
                                size: 20,
                                color: isDark
                                    ? Colors.white54
                                    : Colors.grey[500],
                              ),
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF2A2A2A)
                                  : const Color(0xffF8FAFB),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: AppStyle.primaryColor,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                          itemBuilder: (context, p, isSelected) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  _buildProductImage(p, size: 38),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      p.cleanName,
                                      style: GoogleFonts.manrope(
                                        fontSize: 14,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: isSelected
                                            ? AppStyle.primaryColor
                                            : (isDark
                                                  ? Colors.white
                                                  : Colors.black87),
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      Icons.check_circle_rounded,
                                      size: 18,
                                      color: AppStyle.primaryColor,
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                        items: products,
                        itemAsString: (p) => p.cleanName,
                        compareFn: (a, b) => a.id == b.id,
                        selectedItem: products.firstWhere(
                          (p) => p.id == selectedPicking,
                          orElse: () => Product(
                            id: selectedPicking ?? 0,
                            name: selectedPickingName ?? '',
                            uom_id: selectedPickingUom ?? 1,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _errorMessage = '';
                            selectedPicking = value?.id;
                            selectedPickingName = value?.name;
                            selectedPickingUom = value?.uom_id;
                          });
                        },
                        dropdownBuilder: (context, item) {
                          if (item == null || item.id == 0) {
                            return Text(
                              'Select a product',
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                fontStyle: FontStyle.italic,
                                color: isDark
                                    ? Colors.white54
                                    : Colors.grey[500],
                              ),
                            );
                          }
                          return Row(
                            children: [
                              _buildProductImage(item, size: 32),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  item.cleanName,
                                  style: GoogleFonts.manrope(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          );
                        },
                        dropdownDecoratorProps: DropDownDecoratorProps(
                          dropdownSearchDecoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            prefixIcon:
                                (selectedPicking == null ||
                                    selectedPicking == 0)
                                ? Icon(
                                    HugeIcons.strokeRoundedPackage,
                                    size: 20,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[500],
                                  )
                                : null,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                        validator: (value) =>
                            value == null ? 'Please select a product' : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    RequiredLabel(
                      "Quantity",
                      isRequired: true,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white60 : Colors.black87,
                    ),
                    const SizedBox(height: 8),
                    MoboTextField(
                      controller: qtyController,
                      hintText: 'Enter quantity',
                      keyboardType: TextInputType.number,
                      prefixIcon: Icon(
                        HugeIcons.strokeRoundedPinCode,
                        size: 20,
                        color: isDark ? Colors.grey[400] : Colors.grey[500],
                      ),
                    ),
                    if (_errorMessage.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        _errorMessage,
                        style: GoogleFonts.manrope(
                          color: Colors.red,
                          fontWeight: FontWeight.w400,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
                if (_isLoading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black26,
                      child: const Center(
                        child: LoadingWidget(
                          size: 60,
                          variant: LoadingVariant.staggeredDots,
                        ),
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
                  child: MoboButton.secondary(
                    label: 'DELETE',
                    icon: HugeIcons.strokeRoundedDelete02,
                    borderRadius: 8,
                    onPressed: () async {
                      if (_isEditing) {
                        setState(() {
                          if (product.id < 0) {
                            _stagedNewMoves.removeWhere(
                              (m) => m.id == product.id,
                            );
                          } else {
                            _stagedDeletedMoveIds.add(product.id);
                            _stagedEditedMoves.remove(product.id);
                          }
                          moveProducts.removeAt(index);
                        });
                        Navigator.of(context).pop();
                        return;
                      }
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
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: MoboButton.primary(
                    label: 'SAVE',
                    icon: HugeIcons.strokeRoundedDocumentValidation,
                    borderRadius: 10,
                    onPressed: () async {
                      final enteredQty =
                          double.tryParse(qtyController.text.trim()) ?? 0.0;
                      if (selectedPicking == null) {
                        CustomSnackbar.showError(
                          context,
                          'Please select a product.',
                        );
                        return;
                      }
                      if (enteredQty <= 0) {
                        CustomSnackbar.showError(
                          context,
                          'Quantity must be greater than zero.',
                        );
                        return;
                      }
                      if (pickings.isNotEmpty &&
                          ['done', 'cancel'].contains(pickings[0].state)) {
                        CustomSnackbar.showError(
                          context,
                          'Cannot edit a line on a ${pickings[0].state} picking.',
                        );
                        return;
                      }

                      final moveUpdate = StockMove(
                        id: product.id,
                        productId: [
                          selectedPicking!,
                          selectedPickingName ?? 'Unnamed',
                        ],
                        productUomQty: product.productUomQty,
                        quantity: enteredQty,
                        productUomId: product.productUomId,
                      );

                      if (_isEditing) {
                        setState(() {
                          moveProducts[index] = moveUpdate;
                          if (product.id < 0) {
                            final i = _stagedNewMoves.indexWhere(
                              (m) => m.id == product.id,
                            );
                            if (i != -1) _stagedNewMoves[i] = moveUpdate;
                          } else {
                            _stagedEditedMoves[product.id] = moveUpdate;
                          }
                        });
                        Navigator.of(context).pop();
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
                      final isOnline = isOnlineAvailability;
                      if (isOnline) {
                        try {
                          await odooPickingFormService.updateProductMove(
                            product.id,
                            selectedPicking!,
                            enteredQty,
                          );
                          setState(() {
                            moveProducts[index] = moveUpdate;
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
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildProductImage(Product product, {double size = 40}) {
    if (product.imageBase64 != null && product.imageBase64!.isNotEmpty) {
      try {
        final base64String = product.imageBase64!.contains(',')
            ? product.imageBase64!.split(',')[1]
            : product.imageBase64!;
        final bytes = base64Decode(base64String);
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            image: DecorationImage(
              image: MemoryImage(bytes),
              fit: BoxFit.cover,
            ),
          ),
        );
      } catch (_) {}
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppStyle.primaryColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        HugeIcons.strokeRoundedPackage,
        size: size * 0.45,
        color: AppStyle.primaryColor,
      ),
    );
  }

  Widget _addProductLine(
    BuildContext context,
    TextEditingController qtyController,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool isDropdownOpen = false;
    return StatefulBuilder(
      builder: (context, setState) => Stack(
        children: [
          AlertDialog(
            backgroundColor: isDark ? Colors.grey[850] : Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Add a Product',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width * 0.95,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RequiredLabel(
                    "Product",
                    isRequired: true,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white60 : Colors.black87,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: isDark
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFFF8FAFB),
                      border: Border.all(
                        color: isDropdownOpen
                            ? AppStyle.primaryColor
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: DropdownSearch<Product>(
                      onBeforePopupOpening: (_) async {
                        setState(() => isDropdownOpen = true);
                        return true;
                      },
                      popupProps: PopupProps.menu(
                        onDismissed: () =>
                            setState(() => isDropdownOpen = false),
                        menuProps: MenuProps(
                          backgroundColor: isDark
                              ? Colors.grey[900]
                              : Colors.white,
                          elevation: 8,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        showSearchBox: true,
                        searchFieldProps: TextFieldProps(
                          decoration: InputDecoration(
                            hintText: 'Search products...',
                            hintStyle: GoogleFonts.manrope(
                              fontWeight: FontWeight.w400,
                              color: isDark ? Colors.white54 : Colors.grey[500],
                              fontStyle: FontStyle.italic,
                            ),
                            prefixIcon: Icon(
                              HugeIcons.strokeRoundedSearch01,
                              size: 20,
                              color: isDark ? Colors.white54 : Colors.grey[500],
                            ),
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF2A2A2A)
                                : const Color(0xffF8FAFB),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: AppStyle.primaryColor,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        itemBuilder: (context, product, isSelected) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                _buildProductImage(product, size: 38),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    product.cleanName,
                                    style: GoogleFonts.manrope(
                                      fontSize: 14,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: isSelected
                                          ? AppStyle.primaryColor
                                          : (isDark
                                                ? Colors.white
                                                : Colors.black87),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 18,
                                    color: AppStyle.primaryColor,
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                      items: products,
                      itemAsString: (p) => p.cleanName,
                      compareFn: (a, b) => a.id == b.id,
                      selectedItem:
                          selectedPicking != null && selectedPicking != 0
                          ? products.firstWhere(
                              (p) => p.id == selectedPicking,
                              orElse: () => Product(
                                id: 0,
                                name: selectedPickingName ?? '',
                                uom_id: selectedPickingUom ?? 1,
                              ),
                            )
                          : null,
                      onChanged: (value) {
                        setState(() {
                          _errorMessage = '';
                          selectedPicking = value?.id;
                          selectedPickingName = value?.name;
                          selectedPickingUom = value?.uom_id ?? 1;
                        });
                      },
                      dropdownBuilder: (context, item) {
                        if (item == null) {
                          return Text(
                            'Select a product',
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              fontStyle: FontStyle.italic,
                              color: isDark ? Colors.white54 : Colors.grey[500],
                            ),
                          );
                        }
                        return Row(
                          children: [
                            _buildProductImage(item, size: 32),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item.cleanName,
                                style: GoogleFonts.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        );
                      },
                      dropdownDecoratorProps: DropDownDecoratorProps(
                        dropdownSearchDecoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          prefixIcon:
                              (selectedPicking == null || selectedPicking == 0)
                              ? Icon(
                                  HugeIcons.strokeRoundedPackage,
                                  size: 20,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[500],
                                )
                              : null,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                      validator: (value) =>
                          value == null ? 'Please select a product' : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  RequiredLabel(
                    "Quantity",
                    isRequired: true,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white60 : Colors.black87,
                  ),
                  const SizedBox(height: 8),
                  MoboTextField(
                    controller: qtyController,
                    hintText: 'Enter quantity',
                    keyboardType: TextInputType.number,
                    prefixIcon: Icon(
                      HugeIcons.strokeRoundedPinCode,
                      size: 20,
                      color: isDark ? Colors.grey[400] : Colors.grey[500],
                    ),
                  ),
                  if (_errorMessage.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _errorMessage,
                      style: GoogleFonts.manrope(
                        color: Colors.red,
                        fontWeight: FontWeight.w400,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: MoboButton.secondary(
                      label: 'CANCEL',
                      borderRadius: 8,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 10),

                  Expanded(
                    child: MoboButton.primary(
                      label: 'Add',
                      icon: HugeIcons.strokeRoundedPackageAdd,
                      borderRadius: 8,
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

                          if (_isEditing) {
                            final newMove = StockMove(
                              id: _tempMoveIdSeq--,
                              productId: [
                                selectedPicking!,
                                selectedPickingName ?? 'Unnamed',
                              ],
                              productUomQty: enteredQty,
                              quantity: enteredQty,
                              productUomId: selectedPickingUom,
                            );
                            isCreateSaving = false;
                            selectedPicking = 0;
                            selectedPickingName = null;
                            _stageNewMove(newMove);
                            Navigator.of(context).pop();
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
                                srcId = int.tryParse(
                                  widget.picking['location_id_int']
                                          ?.toString() ??
                                      '',
                                );
                                destId = int.tryParse(
                                  widget.picking['location_dest_id_int']
                                          ?.toString() ??
                                      '',
                                );
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
                                        .timeout(const Duration(seconds: 15));
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
                                  ![
                                    'draft',
                                    'cancel',
                                    'done',
                                  ].contains(pickings[0].state)) {
                                try {
                                  await odooPickingFormService
                                      .checkAvailability(pickingId);
                                } catch (e) {}
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
                                await hiveService
                                    .savePendingUpdates(pickingId, {
                                      'title':
                                          widget.picking['item'] ??
                                          widget.picking['name'] ??
                                          'Picking Details',
                                      'partner_name': null,
                                      'user_name': null,
                                      'updates': headerUpdates,
                                    });
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
    final bool canEdit =
        _isEditing &&
        pickings[0].state != 'done' &&
        pickings[0].state != 'cancel';

    if (moveProducts.isEmpty) {
      final bool showWarn =
          !_isEditing &&
          ['assigned', 'confirmed', 'waiting'].contains(pickings[0].state) &&
          isOnlineAvailability;
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showWarn)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Icon(
                      HugeIcons.strokeRoundedAlert02,
                      color: Colors.orange[700],
                      size: 32,
                    ),
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
                    MoboButton.secondary(
                      label: 'Retry',
                      icon: HugeIcons.strokeRoundedRefresh,
                      fullWidth: false,
                      onPressed: _fetchData,
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                height: 140,
                child: Center(
                  child: Text(
                    'No products added yet',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : Colors.grey[500],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            if (canEdit) _addLineButton(isDark),
          ],
        ),
      );
    }

    final borderColor = isDark ? Colors.grey[700]! : Colors.grey[300]!;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${moveProducts.length} product${moveProducts.length == 1 ? '' : 's'}',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white54 : Colors.grey[600],
                ),
              ),
              if (canEdit)
                TextButton.icon(
                  onPressed: _openAddLine,
                  icon: const Icon(HugeIcons.strokeRoundedAdd01, size: 16),
                  label: Text(
                    'Add',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : Colors.black87,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: borderColor, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Table(
                border: TableBorder(
                  horizontalInside: BorderSide(color: borderColor, width: 1),
                ),
                columnWidths: const {
                  0: FixedColumnWidth(200),
                  1: FixedColumnWidth(120),
                  2: FixedColumnWidth(130),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF3A3A3A)
                          : const Color(0xFFF8F9FA),
                    ),
                    children: [
                      _moveHeaderCell('Product', isDark),
                      _moveHeaderCell('Demand', isDark),
                      _moveHeaderCell('Quantity', isDark),
                    ],
                  ),
                  ...moveProducts.asMap().entries.map((entry) {
                    final index = entry.key;
                    final product = entry.value;
                    final name = product.productId?[1]?.toString() ?? '';
                    final VoidCallback? tap = canEdit
                        ? () => _openEditLine(product, index)
                        : null;
                    return TableRow(
                      children: [
                        _moveCell(
                          onTap: tap,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 22,
                                child: Text(
                                  '${index + 1}.',
                                  style: _moveRowStyle(isDark),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  name,
                                  style: _moveRowStyle(isDark),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _moveCell(
                          onTap: tap,
                          child: Text(
                            _fmtMoveQty(product.productUomQty),
                            style: _moveRowStyle(isDark),
                          ),
                        ),
                        _moveCell(
                          onTap: tap,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppStyle.primaryColor,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                _fmtMoveQty(product.quantity),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openEditLine(StockMove product, int index) {
    setState(() {
      _errorMessage = "";
      selectedPicking = product.productId?[0];
      selectedPickingName = product.productId?[1];
      selectedPickingUom = product.productUomId;
    });
    final qtyController = TextEditingController(
      text: product.quantity.toString(),
    );
    showDialog(
      context: context,
      builder: (context) =>
          _editProductLine(context, product, index, qtyController),
    ).whenComplete(() {
      Future.delayed(const Duration(milliseconds: 400), qtyController.dispose);
    });
  }

  void _openAddLine() {
    setState(() {
      _errorMessage = "";
      selectedPicking = 0;
      selectedPickingName = null;
      selectedPickingUom = null;
    });
    final qtyController = TextEditingController(text: '1');
    showDialog(
      context: context,
      builder: (context) => _addProductLine(context, qtyController),
    ).whenComplete(() {
      Future.delayed(const Duration(milliseconds: 400), qtyController.dispose);
    });
  }

  Widget _addLineButton(bool isDark) {
    return GestureDetector(
      onTap: _openAddLine,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white24
                : AppStyle.primaryColor.withValues(alpha: 0.5),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              HugeIcons.strokeRoundedPackageAdd,
              size: 18,
              color: AppStyle.accentOf(context),
            ),
            const SizedBox(width: 6),
            Text(
              'Add a product',
              style: TextStyle(
                color: AppStyle.accentOf(context),
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  TableCell _moveHeaderCell(String text, bool isDark) {
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.grey[800],
          ),
        ),
      ),
    );
  }

  TableCell _moveCell({required Widget child, VoidCallback? onTap}) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: child,
        ),
      ),
    );
  }

  TextStyle _moveRowStyle(bool isDark) => TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: isDark ? Colors.grey[300] : Colors.grey[700],
  );

  String _fmtMoveQty(num value) =>
      value == value.truncate() ? value.toInt().toString() : '$value';

  Widget _additionalInfo() {
    final picking = pickings[0];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(16),
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
                          fontSize: 14,
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
                            color: _isShippingPolicyOpen
                                ? AppStyle.primaryColor
                                : Colors.transparent,
                            width: 1.5,
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
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          buttonStyleData: const ButtonStyleData(
                            height: 44,
                            padding: EdgeInsets.only(left: 12, right: 4),
                          ),
                          menuItemStyleData: const MenuItemStyleData(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                          ),
                          iconStyleData: IconStyleData(
                            icon: Icon(
                              Icons.arrow_drop_down,
                              color: isDark ? Colors.white54 : Colors.grey[600],
                            ),
                            iconSize: 24,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'direct',
                              child: Text(
                                "As soon as possible",
                                style: GoogleFonts.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'one',
                              child: Text(
                                "When all products are ready",
                                style: GoogleFonts.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _selectedShippingPolicy = value;
                              });
                            }
                          },
                          onMenuStateChange: (isOpen) {
                            setState(() => _isShippingPolicyOpen = isOpen);
                          },
                          dropdownStyleData: DropdownStyleData(
                            maxHeight: 200,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: isDark
                                  ? const Color(0xFF2C2C2C)
                                  : Colors.white,
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
          const SizedBox(height: 12),
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
            const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          if (_isEditing) ...[
            Text(
              "Company",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: isDark ? Colors.white70 : const Color(0xff7F7F7F),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => CustomSnackbar.showInfo(
                context,
                'Company cannot be changed.',
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isDark
                      ? const Color(0xFF2A2A2A)
                      : const Color(0xFFF2F4F6),
                ),
                child: Row(
                  children: [
                    Icon(
                      HugeIcons.strokeRoundedBuilding01,
                      size: 20,
                      color: isDark ? Colors.white54 : const Color(0xff7F7F7F),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        (picking.companyId != null &&
                                picking.companyId!.length > 1)
                            ? picking.companyId![1]
                            : "None",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                    Icon(
                      HugeIcons.strokeRoundedLock,
                      size: 14,
                      color: isDark ? Colors.white24 : Colors.grey[400],
                    ),
                  ],
                ),
              ),
            ),
          ] else
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
    final String rawNote = (pickings.isNotEmpty
        ? (pickings[0].note ?? '')
        : '');
    final String plainNote = rawNote.replaceAll(RegExp(r'<[^>]*>'), '').trim();

    if (_isEditing) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: InfoRow(
          label: "Note",
          value: pickings.isNotEmpty ? pickings[0].note : '',
          isEditing: true,
          controller: _noteController,
          readOnly:
              pickings.isNotEmpty &&
              ['done', 'cancel'].contains(pickings[0].state),
          onTap: () {},
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Note',
            style: TextStyle(
              fontWeight: FontWeight.w400,
              color: isDark ? Colors.white70 : const Color(0xff7F7F7F),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 80),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF2F4F6),
            ),
            child: plainNote.isNotEmpty
                ? Text(
                    plainNote,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black87,
                      height: 1.5,
                    ),
                  )
                : Text(
                    'Note',
                    style: TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.white38 : Colors.grey[500],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
