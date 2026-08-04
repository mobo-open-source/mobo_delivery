import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import '../../../../NavBars/Home/pages/home_page.dart';
import '../../../../NavBars/MapBox/pages/route_visualization_page.dart';

import '../../../../NavBars/Pickings/PickingListPage/pages/pickings_grouped_page.dart';
import '../../../../NavBars/ReturnManagement/pages/return_management_page.dart';
import '../../../../NavBars/AttachDocument/pages/attach_documents_page.dart';
import '../../../../StoreToOffline/attachment_and_notes.dart';
import '../../../../StoreToOffline/picking_form.dart';
import '../../../../StoreToOffline/picking_list.dart';
import '../../../../StoreToOffline/return.dart';
import '../../../../shared/utils/odoo_datetime_format.dart';
import '../../../services/odoo_dashboard_service.dart';
import '../../../services/storage_service.dart';
import 'dashboard_event.dart';
import 'dashboard_state.dart';

/// Central business logic for the main dashboard screen.
///
/// Responsibilities:
///   • Initialize session and Odoo connection
///   • Manage bottom navigation tabs
///   • Load and refresh user profile (online + offline support)
///   • Initialize offline storage/sync clients
///   • Handle company/profile image updates
class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  final DashboardStorageService storageService;
  final OdooDashboardService Function(String url, OdooSession session)
  serviceFactory;

  late OdooDashboardService odooService;

  /// Guards the one-shot retry after a profile fetch that didn't populate
  /// (e.g. the early RPC raced with session refresh and came back empty).
  bool _didProfileAutoRetry = false;

  static final pickingListToOffline pickingList = pickingListToOffline();
  static final PickingFormToOffline PickingForm = PickingFormToOffline();
  static final ReturnToOffline Return = ReturnToOffline();
  static final AttachmentAndNotesToOffline attachmentAndNotes =
  AttachmentAndNotesToOffline();

  /// Bottom-nav tabs — static so they render before the session finishes loading.
  static const List<Map<String, dynamic>> navPages = [
    {
      'title': 'Home',
      'label': 'Home',
      'icon': HugeIcons.strokeRoundedHome01,
      'route': HomePage(),
    },
    {
      'title': 'Pickings',
      'label': 'Pickings',
      'icon': HugeIcons.strokeRoundedShoppingBasket01,
      'route': PickingsGroupedPage(),
    },
    {
      'title': 'Route',
      'label': 'Route',
      'icon': HugeIcons.strokeRoundedRoute02,
      'route': RouteVisualizationPage(),
    },
    {
      'title': 'Returns',
      'label': 'Return',
      'icon': HugeIcons.strokeRoundedReturnRequest,
      'route': ReturnManagementPage(),
    },
    {
      'title': 'Documents',
      'label': 'Documents',
      'icon': HugeIcons.strokeRoundedDocumentAttachment,
      'route': AttachDocumentsPage(),
    },
  ];

  DashboardBloc(this.storageService, this.serviceFactory)
      : super(const DashboardState(isLoading: true, pages: navPages)) {
    on<InitializeDashboard>(_onInitializeDashboard);
    on<ChangeTab>(_onChangeTab);
    on<LoadUserProfile>(_onLoadUserProfile);
    on<RefreshUserProfile>(_onRefreshUserProfile);
  }

  /// Handles app/dashboard initialization
  ///   - Loads saved session
  ///   - Creates Odoo service
  ///   - Initializes offline clients
  ///   - Loads user profile
  ///   - Sets up navigation pages
  Future<void> _onInitializeDashboard(
      InitializeDashboard event, Emitter<DashboardState> emit) async {
    emit(state.copyWith(isLoading: true));

    final sessionData = await storageService.getSessionData();
    final url = sessionData['url'];
    final session = OdooSession(
      id: sessionData['sessionId'],
      userId: sessionData['userId'],
      partnerId: sessionData['partnerId'],
      userLogin: sessionData['userLogin'],
      userName: sessionData['userName'],
      userLang: sessionData['userLang'],
      userTz: '',
      isSystem: sessionData['isSystem'],
      dbName: sessionData['db'],
      serverVersion: sessionData['serverVersion'],
      companyId: sessionData['companyId'],
      allowedCompanies: storageService.parseCompanies(
        sessionData['allowedCompanies'],
      ),
    );

    odooService = serviceFactory(url, session);
    await _initializeOfflineClients();

    emit(state.copyWith(
      isLoading: false,
      currentIndex: event.initialIndex,
      pages: navPages,
    ));

    add(LoadUserProfile());
  }

  /// Simply updates the current tab index
  void _onChangeTab(ChangeTab event, Emitter<DashboardState> emit) {
    emit(state.copyWith(currentIndex: event.index));
  }

  /// Public event handler to (re)load user profile
  Future<void> _onLoadUserProfile(
      LoadUserProfile event, Emitter<DashboardState> emit) async {
    await _loadUserProfile(emit);
  }

  /// Public event handler to refresh profile (usually after settings/company change)
  Future<void> _onRefreshUserProfile(
      RefreshUserProfile event, Emitter<DashboardState> emit) async {
    await _loadUserProfile(emit);
  }

  /// Initializes all offline storage/sync handlers with current Odoo client
  Future<void> _initializeOfflineClients() async {
    pickingList.initializeOdooClient();
    PickingForm.initializeOdooClient();
    Return.initializeOdooClient();
    attachmentAndNotes.initializeOdooClient();
    await OdooDateTimeFormat.loadCached();
    unawaited(OdooDateTimeFormat.ensureFetched());
  }

  String safeString(dynamic value) =>
      value is String ? value : '';

  /// Core method: Load or refresh user profile data
  ///   - Online: fetch from Odoo → save to storage
  ///   - Offline: use cached data from storage
  ///   - Updates state with name, email, profile picture bytes
  ///   - Also saves image to account list for quick access
  Future<void> _loadUserProfile(Emitter<DashboardState> emit) async {
    final sessionData = await storageService.getSessionData();
    final userId = sessionData['userId'];
    final isOnline = await odooService.checkNetworkConnectivity();
    if (!emit.isDone) {
      emit(state.copyWith(isServerReachable: isOnline));
    }
    Map<String, dynamic>? userDetails;
    bool liveFetchSucceeded = false;

    if (isOnline) {
      try {
        userDetails = await odooService
            .getUserProfile(userId)
            .timeout(const Duration(seconds: 15));
        if (userDetails != null) {
          await storageService.saveUserProfile(userDetails);
          liveFetchSucceeded = true;
        }
      } on OdooSessionExpiredException {
        userDetails = await storageService.getSavedUserProfile();
      } on TimeoutException {
        userDetails = await storageService.getSavedUserProfile();
      } catch (e) {
        userDetails = await storageService.getSavedUserProfile();
      }
    } else {
      userDetails = await storageService.getSavedUserProfile();
    }

    if (userDetails != null) {
      final imageBase64 = userDetails['image_1920']?.toString();
      final profilePicBytes = (imageBase64 != null &&
          imageBase64.isNotEmpty &&
          imageBase64 != 'false')
          ? base64Decode(imageBase64)
          : null;

      emit(state.copyWith(
        userName: safeString(userDetails['name']),
        mail: safeString(userDetails['email']),
        profilePicBytes: profilePicBytes,
      ));
    }

   final base64Image = userDetails?['image_1920'];

    final currentAccounts = await storageService.getAccounts();

    final existing = currentAccounts.firstWhere(
          (a) => a['userId'] == userDetails?['id'],
      orElse: () => {},
    );

    final accountWithImage = {...existing, 'image': base64Image};

    await storageService.saveAccount(accountWithImage);

    if (isOnline && !liveFetchSucceeded && !_didProfileAutoRetry) {
      final stillEmpty = (userDetails?['name'] == null ||
          userDetails!['name'].toString().trim().isEmpty);
      if (stillEmpty) {
        _didProfileAutoRetry = true;
        Timer(const Duration(seconds: 3), () {
          if (isClosed) return;
          add(RefreshUserProfile());
        });
      }
    } else if (liveFetchSucceeded) {
      _didProfileAutoRetry = false;
    }
  }
}
