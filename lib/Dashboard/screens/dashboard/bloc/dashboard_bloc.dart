import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../NavBars/GoogleMap/pages/route_visualization_page.dart';
import '../../../../NavBars/OfflineSync/pages/offline_sync_page.dart';
import '../../../../NavBars/Pickings/PickingListPage/pages/pickings_grouped_page.dart';
import '../../../../NavBars/ReturnManagement/pages/return_management_page.dart';
import '../../../../StoreToOffline/attachment_and_notes.dart';
import '../../../../StoreToOffline/picking_form.dart';
import '../../../../StoreToOffline/picking_list.dart';
import '../../../../StoreToOffline/return.dart';
import '../../../models/profile.dart';
import '../../../services/hive_profile_service.dart';
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

  // Offline storage handlers (static to share across the app)
  static final pickingListToOffline pickingList = pickingListToOffline();
  static final PickingFormToOffline PickingForm = PickingFormToOffline();
  static final ReturnToOffline Return = ReturnToOffline();
  static final AttachmentAndNotesToOffline attachmentAndNotes =
  AttachmentAndNotesToOffline();

  DashboardBloc(this.storageService, this.serviceFactory)
      : super(const DashboardState(isLoading: true)) {
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
    await _loadUserProfile(emit);

    emit(state.copyWith(
      isLoading: false,
      currentIndex: event.initialIndex,
      pages: [
        {
          'title': 'Pickings by Location',
          'label': 'Pickings',
          'icon': HugeIcons.strokeRoundedShoppingBasket01,
          'route': const PickingsGroupedPage(),
        },
        {
          'title': 'Route Visualization',
          'label': 'Route',
          'icon': HugeIcons.strokeRoundedRoute02,
          'route': const RouteVisualizationPage(),
        },
        {
          'title': 'Return Management',
          'label': 'Return',
          'icon': HugeIcons.strokeRoundedReturnRequest,
          'route': const ReturnManagementPage(),
        },
        {
          'title': 'Offline Sync',
          'label': 'Offline',
          'icon': HugeIcons.strokeRoundedHotspotOffline,
          'route': const OfflineSyncPage(),
        },
        {
          'title': 'Others',
          'label': 'Others',
          'icon': HugeIcons.strokeRoundedMore,
          'route': null,
        },
      ],
    ));
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
  }

  /// Core method: Load or refresh user profile data
  ///   - Online: fetch from Odoo → save to storage + Hive
  ///   - Offline: use cached data from storage
  ///   - Updates state with name, email, profile picture bytes
  ///   - Also saves image to account list for quick access
  Future<void> _loadUserProfile(Emitter<DashboardState> emit) async {
    final sessionData = await storageService.getSessionData();
    final userId = sessionData['userId'];
    final isOnline = await odooService.checkNetworkConnectivity();
    Map<String, dynamic>? userDetails;
    final prefs = await SharedPreferences.getInstance();
    int version = prefs.getInt('version') ?? 0;

    if (isOnline) {
      Profile? profile;
      userDetails = await odooService.getUserProfile(userId);
      if (userDetails != null) {
        await storageService.saveUserProfile(userDetails);
        String mobile = '';
        if (userDetails != null) {
          if (version < 18) {
            mobile = (userDetails['mobile'] is String) ? userDetails['mobile']! : '';
          } else {
            mobile = (userDetails['mobile_phone'] is String) ? userDetails['mobile_phone']! : '';
          }
        }
        String? profileImage;
        final imgValue = userDetails?['image_1920'];
        if (imgValue is String) {
          profileImage = imgValue;
        } else {
          profileImage = null;
        }
        profile = Profile(
            name: userDetails?['name'],
            email: userDetails?['email'],
            phone: userDetails?['phone'],
            mobile: mobile,
            company: userDetails?['company_id'] != null &&
                (userDetails!['company_id'] as List).isNotEmpty
                ? userDetails['company_id'][1].toString()
                : '',
            website: userDetails?['website'],
            jobTitle: userDetails?['position'],
            profileImage: profileImage,
            mapToken: (await storageService.getSessionData())['mapToken']
                ?.toString() ?? ''
        );

        await HiveProfileService().saveProfile(profile);
      }
    } else {
      userDetails = await storageService.getSavedUserProfile();
    }

    if (userDetails != null) {
      // Prepare profile picture bytes for UI
      final imageBase64 = userDetails['image_1920']?.toString();
      final profilePicBytes = (imageBase64 != null &&
          imageBase64.isNotEmpty &&
          imageBase64 != 'false')
          ? base64Decode(imageBase64)
          : null;

      emit(state.copyWith(
        userName: userDetails['name'],
        mail: userDetails['email'],
        profilePicBytes: profilePicBytes,
      ));
    }

    // Also update account list with latest image
   final base64Image = userDetails?['image_1920'];

    final currentAccounts = await storageService.getAccounts();

    final existing = currentAccounts.firstWhere(
          (a) => a['userId'] == userDetails?['id'],
      orElse: () => {},
    );

    final accountWithImage = {...existing, 'image': base64Image};

    await storageService.saveAccount(accountWithImage);
  }
}
