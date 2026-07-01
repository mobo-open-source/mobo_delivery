import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:odoo_delivery_app/Dashboard/screens/profile/pages/profile_loading_shimmer.dart';
import 'package:odoo_delivery_app/shared/widgets/snackbar.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/company/session/company_session_manager.dart';
import '../../../services/encryption_service.dart';
import '../../../services/odoo_dashboard_service.dart';
import '../../../services/storage_service.dart';
import '../../../widgets/profile/profile_header_card.dart';
import '../../../../shared/widgets/action_tile.dart';
import '../../../../shared/widgets/dialogs/common_dialog.dart';
import '../../../../shared/widgets/error_state_widget.dart';
import '../bloc/profile_bloc.dart';
import '../bloc/profile_event.dart';
import '../bloc/profile_state.dart';
import 'profile_detail_screen.dart';

/// A screen that provides a high-level overview of the user's profile and app configuration.
/// Ported from mobo_inv_app style logic.
class ProfileSettingsPage extends StatefulWidget {
  final Future<void> Function()? refreshProfile;

  const ProfileSettingsPage({super.key, this.refreshProfile});

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  ProfileBloc? _profileBloc;
  int? userId;
  int? companyId;
  bool? isSystem;
  bool isOnline = true;
  bool isAdmin = false;

  late OdooDashboardService odooService;
  late EncryptionService encryptionService;
  late DashboardStorageService storageService;

  @override
  void initState() {
    super.initState();
    encryptionService = EncryptionService();
    storageService = DashboardStorageService();
    _initAll();
  }

  Future<void> _initAll() async {
    await _initBloc();
    await _initializeServices();
    await canManageSkills();
  }

  Future<void> _initializeServices() async {
    isOnline = await odooService.checkNetworkConnectivity();
    if (mounted) setState(() {});
  }

  String? _initError;

  Future<void> _initBloc() async {
    try {
      final sessionData = await storageService.getSessionData();
      userId = sessionData['userId'];
      companyId = sessionData['companyId'];
      isSystem = sessionData['isSystem'];

      final session = OdooSession(
        id: sessionData['sessionId'],
        userId: userId ?? 0,
        partnerId: sessionData['partnerId'],
        userLogin: sessionData['userLogin'],
        userName: sessionData['userName'],
        userLang: sessionData['userLang'],
        userTz: '',
        isSystem: isSystem ?? false,
        dbName: sessionData['db'],
        serverVersion: sessionData['serverVersion'],
        companyId: companyId ?? 1,
        allowedCompanies: storageService.parseCompanies(
          sessionData['allowedCompanies'],
        ),
      );

      odooService = OdooDashboardService(sessionData['url'], session);

      if (mounted) {
        setState(() {
          _profileBloc = ProfileBloc(
            odooService: odooService,
            storageService: storageService,
            encryptionService: encryptionService,
          );
        });
        _profileBloc!.add(LoadProfile());
      }
    } catch (e) {
      if (mounted) {
        setState(() => _initError = e.toString());
      }
    }
  }

  int parseMajorVersion(String serverVersion) {
    final match = RegExp(r'\d+').firstMatch(serverVersion);
    return match != null ? (int.tryParse(match.group(0)!) ?? 0) : 0;
  }

  Future<void> canManageSkills() async {
    final prefs = await SharedPreferences.getInstance();
    final String version = prefs.getString('serverVersion') ?? '0';
    final int uId = prefs.getInt('userId') ?? 0;
    final int majorVersion = parseMajorVersion(version);

    Future<bool> hasGroup(String groupExtId) async {
      final args = majorVersion >= 18 ? [uId, groupExtId] : [groupExtId];
      return await CompanySessionManager.callKwWithCompany({
        'model': 'res.users',
        'method': 'has_group',
        'args': args,
        'kwargs': {},
      }) == true;
    }

    try {
      final admin = await hasGroup('base.group_system');
      if (mounted) setState(() => isAdmin = admin);
    } catch (_) {}
  }

  @override
  void dispose() {
    _profileBloc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_profileBloc == null) {
      return Scaffold(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        appBar: AppBar(
          forceMaterialTransparency: true,
          backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
          elevation: 0,
          leading: IconButton(
            icon: Icon(HugeIcons.strokeRoundedArrowLeft01,
                color: isDark ? Colors.white : Colors.black),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: _initError != null
            ? ErrorStateWidget(
                title: 'Something went wrong',
                message:
                    'Unable to open your profile. Please try again.\n\n$_initError',
                errorType: ErrorType.general,
                onRetry: () {
                  setState(() => _initError = null);
                  _initAll();
                },
              )
            : const Center(child: ProfileShimmer()),
      );
    }

    return BlocProvider.value(
      value: _profileBloc!,
      child: Scaffold(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        appBar: AppBar(
          forceMaterialTransparency: true,
          backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
          elevation: 0,
          title: Text(
            'Configuration',
            style: GoogleFonts.manrope(
              fontWeight: FontWeight.w600,
              fontSize: 22,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          leading: IconButton(
            icon: Icon(HugeIcons.strokeRoundedArrowLeft01, color: isDark ? Colors.white : Colors.black),
            onPressed: () {
              Navigator.of(context).pop();
              if (widget.refreshProfile != null) widget.refreshProfile!();
            },
          ),
        ),
        body: BlocBuilder<ProfileBloc, ProfileState>(
          builder: (context, state) {
            if (state is ProfileLoading) {
              return const ProfileShimmer();
            } else if (state is ProfileError) {
              return ErrorStateWidget(
                title: 'Something went wrong',
                message: state.message.trim().isNotEmpty
                    ? state.message
                    : 'Unable to load your profile. Please check your '
                        'connection and try again.',
                errorType: ErrorType.general,
                onRetry: () => _profileBloc!.add(LoadProfile()),
              );
            } else if (state is ProfileLoaded) {
              final profile = state.profile;

              return RefreshIndicator(
                onRefresh: () async => _profileBloc!.add(LoadProfile()),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      ProfileHeaderCard(
                        name: profile.name ?? 'Unknown User',
                        email: profile.email ?? '',
                        jobFunction: '',
                        avatarBase64: profile.profileImage,
                        showCameraButton: false,
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProfileDetailScreen(),
                            ),
                          );
                          if (result == true && widget.refreshProfile != null) {
                            widget.refreshProfile!();
                          }
                        },
                      ),
                      const SizedBox(height: 24),
                      _buildQuickActions(context, isDark),
                    ],
                  ),
                ),
              );
            }
            // Unknown / uninitialized state: instead of a blank screen, show a
            // retryable error so the user is never left staring at nothing.
            return ErrorStateWidget(
              title: 'Something went wrong',
              message:
                  'Unable to load your profile. Please check your connection '
                  'and try again.',
              errorType: ErrorType.general,
              onRetry: () => _profileBloc!.add(LoadProfile()),
            );
          },
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        children: [
          ActionTile(
            title: 'Profile Settings',
            subtitle: 'Personal info, contact, and job details',
            icon: HugeIcons.strokeRoundedUserEdit01,
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfileDetailScreen(),
                ),
              );
              if (result == true && widget.refreshProfile != null) {
                widget.refreshProfile!();
              }
            },
          ),
          _buildDivider(isDark),
          ActionTile(
            title: 'App Settings',
            subtitle: 'App preferences and system configuration',
            icon: HugeIcons.strokeRoundedSettings02,
            onTap: () {
              CustomSnackbar.show(
                context: context,
                title: 'Settings',
                message: 'Settings coming soon',
                type: SnackbarType.info,
              );
            },
          ),
          _buildDivider(isDark),
          ActionTile(
            title: 'Logout',
            subtitle: 'Sign out from this device',
            icon: HugeIcons.strokeRoundedLogout01,
            destructive: true,
            trailing: const SizedBox.shrink(),
            onTap: () => _showLogoutConfirm(context),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1,
      indent: 56,
      endIndent: 16,
      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05),
    );
  }

  void _showLogoutConfirm(BuildContext context) async {
    final confirmed = await CommonDialog.confirm(
      context,
      title: 'Confirm Logout',
      message: 'Are you sure you want to log out? Your session will be ended.',
      confirmText: 'Log Out',
      cancelText: 'Cancel',
      centered: false,
    );

    if (confirmed == true && context.mounted) {
      CompanySessionManager.logout(context);
    }
  }
}
