import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import '../../LoginPage/models/session_model.dart';
import '../../LoginPage/services/storage_service.dart';
import '../../core/company/session/company_session_manager.dart';
import '../../core/providers/motion_provider.dart';
import '../../shared/utils/app_theme.dart';
import '../../shared/widgets/action_tile.dart';
import '../../shared/widgets/odoo_avatar.dart';
import '../services/storage_service.dart';
import '../../shared/widgets/dialogs/common_dialog.dart';
import '../widgets/profile/profile_header_card.dart';
import 'SwitchAccount/server_url_screen.dart';
import 'dashboard/pages/dashboard.dart';
import 'profile/pages/profile_detail_screen.dart';
import 'settings/pages/settings_page.dart';
import '../../NavBars/Pickings/PickingFormPage/services/hive_service.dart';
import '../../core/security/secure_storage_service.dart';
import '../../shared/widgets/loaders/loading_widget.dart';

/// Configuration screen — central hub for profile, settings, account switching, and logout.
///
/// Modeled after mobo_inv_app's ProfileScreen pattern:
///   • ProfileHeaderCard at top → navigates to ProfileDetailScreen (View/Edit)
///   • Quick actions section with ActionTile widgets
///   • Switch Accounts expansion tile with account list
///   • Logout action
///   • RefreshIndicator + shimmer loading
class Configuration extends StatefulWidget {
  final Uint8List? profileImageBytes;
  final String? userName;
  final String? mail;

  const Configuration({
    super.key,
    required this.profileImageBytes,
    required this.userName,
    required this.mail,
  });

  @override
  State<Configuration> createState() => _ConfigurationState();
}

class _ConfigurationState extends State<Configuration> {
  late DashboardStorageService storageService;
  late StorageService loginStorageService;
  Map<String, dynamic>? profile;
  String? currentUrl;
  String? currentDatabase;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    storageService = DashboardStorageService();
    loginStorageService = StorageService();
    _initialize();
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    currentUrl = prefs.getString('url') ?? '';
    currentDatabase = prefs.getString('selectedDatabase') ?? '';
    await _loadProfile();
  }

  /// Loads the user profile directly via CompanySessionManager
  /// (same pattern as mobo_inv_app's ProfileProvider.fetchUserProfile).
  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final session = await CompanySessionManager.getCurrentSession();
      if (session == null || session.userId == null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }

      final res = await CompanySessionManager.callKwWithCompany({
        'model': 'res.users',
        'method': 'read',
        'args': [
          [session.userId],
          [
            'name',
            'email',
            'phone',
            'image_1920',
            'company_id',
            'function',
            'website',
          ],
        ],
        'kwargs': {},
      });

      if (res is List && res.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          profile = res.first as Map<String, dynamic>;
          _isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() => _isLoading = false);
      }
    } catch (e) {

      // If session is expired, redirect to login
      if (e is OdooSessionExpiredException && mounted) {
        CompanySessionManager.logout(context);
        return;
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  String? get _userAvatarBase64 {
    final val = profile?['image_1920'];
    if (val is String && val.isNotEmpty && val != 'false') return val;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final motionProvider = Provider.of<MotionProvider>(context, listen: false);

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        forceMaterialTransparency: true,
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            HugeIcons.strokeRoundedArrowLeft01,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Configuration',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
      ),
      body: _isLoading && profile == null
          ? _buildLoadingShimmer(isDark)
          : RefreshIndicator(
              onRefresh: _loadProfile,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Offline banner — shown when server unreachable, uses cached data
                    if (profile == null && !_isLoading)
                      _buildOfflineBanner(isDark),

                    const SizedBox(height: 12),

                    // Profile Header Card (falls back to Dashboard cached data when offline)
                    ProfileHeaderCard(
                      name:
                          profile?['name']?.toString() ??
                          widget.userName ??
                          'Unknown User',
                      email:
                          (profile?['email'] != null &&
                              profile?['email'] != false)
                          ? profile!['email'].toString()
                          : widget.mail ?? '',
                      jobFunction: '',
                      avatarBase64: _userAvatarBase64,
                      showCameraButton: false,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          _buildPageRoute(
                            motionProvider,
                            const ProfileDetailScreen(),
                          ),
                        );
                        _loadProfile();
                      },
                    ),
                    const SizedBox(height: 12),

                    // Quick Actions always visible (Settings, Switch Accounts, Logout)
                    _buildQuickActionsSection(context, motionProvider),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildQuickActionsSection(
    BuildContext context,
    MotionProvider motionProvider,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 6),
              color: Colors.black.withValues(alpha: 0.06),
            ),
        ],
      ),
      child: Column(
        children: [
          // Settings
          ActionTile(
            title: 'Settings',
            subtitle: 'App preferences and sync options',
            icon: Icons.settings_outlined,
            onTap: () {
              Navigator.push(
                context,
                _buildPageRoute(motionProvider, const SettingsPage()),
              );
            },
          ),
          _buildDivider(isDark),

          // Switch Accounts
          _buildSwitchAccountsTile(context, isDark, motionProvider),
          _buildDivider(isDark),

          // Logout
          ActionTile(
            title: 'Logout',
            subtitle: 'Sign out from this device',
            icon: HugeIcons.strokeRoundedLogout01,
            destructive: true,
            trailing: const SizedBox.shrink(),
            onTap: () async {
              final confirmed = await CommonDialog.confirm(
                context,
                title: 'Confirm Logout',
                message:
                    'Are you sure you want to log out? Your session will be ended.',
                confirmText: 'Log Out',
                cancelText: 'Cancel',
                destructive: false,
                centered: false,
              );

              if (confirmed == true && context.mounted) {
                CompanySessionManager.logout(context);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchAccountsTile(
    BuildContext context,
    bool isDark,
    MotionProvider motionProvider,
  ) {
    final Color subtitleColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
    final Color iconColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: ExpansionTile(
        leading: Icon(HugeIcons.strokeRoundedUserSwitch, color: iconColor),
        title: Text(
          'Switch Accounts',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          'Manage and switch between accounts',
          style: TextStyle(fontSize: 13, color: subtitleColor),
        ),
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: storageService.getAccounts(),
            builder: (context, snapshot) {
              final accounts = snapshot.data ?? [];
              final otherAccounts = accounts.where((user) {
                final userUrl = user['url'] ?? '';
                final userDatabase = user['database'] ?? '';
                final accountUserId = user['userId'];

                final isSameAccount =
                    userUrl == currentUrl &&
                    userDatabase == currentDatabase &&
                    accountUserId == profile?['id'];

                final userName = user['userName'] ?? '';
                return !isSameAccount && userName.isNotEmpty;
              }).toList();

              return Column(
                children: [
                  if (otherAccounts.isEmpty) _buildEmptyAccountState(isDark),
                  ...otherAccounts.map(
                    (user) => _buildAccountTile(
                      context,
                      user,
                      isDark,
                      motionProvider,
                    ),
                  ),
                  _buildAddAccountButton(context, isDark, motionProvider),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyAccountState(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              HugeIcons.strokeRoundedUserAdd01,
              size: 30,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No Other Accounts',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add multiple accounts to switch between them quickly',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountTile(
    BuildContext context,
    Map<String, dynamic> user,
    bool isDark,
    MotionProvider motionProvider,
  ) {
    final dynamic imageVal = user['image'];
    final String? imageBase64 = imageVal is String ? imageVal : null;
    final hasImage =
        imageBase64 != null && imageBase64.isNotEmpty && imageBase64 != 'false';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? Colors.grey[800] : Colors.grey[50],
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
              width: 2,
            ),
          ),
          child: ClipOval(
            child: hasImage
                ? OdooAvatar(
                    imageBase64: imageBase64,
                    size: 40,
                    iconSize: 20,
                    placeholderColor: isDark
                        ? Colors.grey[700]
                        : Colors.grey[100],
                    iconColor: isDark ? Colors.grey[400] : Colors.grey[600],
                  )
                : _buildDefaultAvatar(user, isDark),
          ),
        ),
        title: Text(
          user['userName'] ?? 'Unknown User',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              user['userLogin'] ?? user['database'] ?? '',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
        trailing: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            minimumSize: const Size(50, 28),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            side: BorderSide(
              color: isDark ? Colors.white : AppTheme.primaryColor,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () => _switchAccount(user, motionProvider),
          child: Text(
            'Switch',
            style: TextStyle(
              color: isDark ? Colors.white : AppTheme.primaryColor,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultAvatar(Map<String, dynamic> user, bool isDark) {
    final userName = user['userName'] as String?;
    if (userName != null && userName.isNotEmpty) {
      final parts = userName.trim().split(' ');
      final initials = parts.length >= 2
          ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
          : parts[0].substring(0, 1).toUpperCase();

      return Container(
        color: isDark ? Colors.grey[700] : Colors.grey[100],
        child: Center(
          child: Text(
            initials,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[300] : Colors.grey[700],
            ),
          ),
        ),
      );
    }

    return Container(
      color: isDark ? Colors.grey[700] : Colors.grey[100],
      child: Icon(
        HugeIcons.strokeRoundedUser,
        size: 20,
        color: isDark ? Colors.grey[400] : Colors.grey[600],
      ),
    );
  }

  Widget _buildAddAccountButton(
    BuildContext context,
    bool isDark,
    MotionProvider motionProvider,
  ) {
    return Container(
      margin: const EdgeInsets.all(16),
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          final prefs = await SharedPreferences.getInstance();
          final url = prefs.getString('url') ?? '';
          final database = prefs.getString('selectedDatabase') ?? '';
          final session = await CompanySessionManager.getCurrentSession();
          if (!mounted || session == null) return;

          Navigator.push(
            this.context,
            _buildPageRoute(
              motionProvider,
              ServerUrlScreen(
                serverUrl: url,
                database: database,
                session: session,
              ),
            ),
          );
        },
        icon: const Icon(HugeIcons.strokeRoundedUserAdd01, size: 18),
        label: const Text('Add Account'),
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? Colors.white : AppTheme.primaryColor,
          foregroundColor: isDark ? Colors.black : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildOfflineBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, size: 16, color: Colors.orange[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Server unreachable. Showing cached data.',
              style: TextStyle(fontSize: 13, color: Colors.orange[700]),
            ),
          ),
          TextButton(
            onPressed: _loadProfile,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Retry',
              style: TextStyle(
                color: Colors.orange[700],
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1,
      color: isDark ? Colors.grey[800] : Colors.grey[200],
    );
  }

  Widget _buildLoadingShimmer(bool isDark) {
    final shimmerBase = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final shimmerHighlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    final placeholderColor = isDark ? Colors.grey[900]! : Colors.white;
    final cardColor = isDark ? Colors.grey[900] : Colors.white;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Shimmer.fromColors(
        baseColor: shimmerBase,
        highlightColor: shimmerHighlight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile card shimmer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: placeholderColor,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 18,
                          width: 180,
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: placeholderColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        Container(
                          height: 14,
                          width: 160,
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: placeholderColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        Container(
                          height: 12,
                          width: 120,
                          decoration: BoxDecoration(
                            color: placeholderColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Actions shimmer
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                children: List.generate(3, (index) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: index == 2 ? 0 : 16),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: placeholderColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 14,
                                width: 120,
                                margin: const EdgeInsets.only(bottom: 6),
                                decoration: BoxDecoration(
                                  color: placeholderColor,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              Container(
                                height: 12,
                                width: 180,
                                decoration: BoxDecoration(
                                  color: placeholderColor,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PageRoute _buildPageRoute(MotionProvider motionProvider, Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
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
    );
  }

  Future<void> _switchAccount(
    Map<String, dynamic> user,
    MotionProvider motionProvider,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Show blocking loading dialog immediately so the user gets feedback
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: isDark ? Colors.grey[900] : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(16),
                    child: LoadingWidget(
                      color: isDark
                          ? Colors.white
                          : Theme.of(context).primaryColor,
                      size: 50,
                      variant: LoadingVariant.fourRotatingDots,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Switching account...',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please wait while we set up your session.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      final url = (user['url'] as String? ?? '').trim();
      final database = (user['database'] as String? ?? '').trim();
      final userLogin = (user['userLogin'] as String? ?? '').trim();

      // Restore the account's session data to SharedPreferences
      await storageService.saveSession(
        SessionModel(
          sessionId: user['sessionId'] ?? '',
          userName: user['userName'],
          userLogin: userLogin,
          userId: user['userId'],
          serverVersion: user['serverVersion'],
          userLang: user['userLang'],
          partnerId: user['partnerId'],
          userTimezone: user['userTimezone'],
          companyId: user['companyId'],
          companyName: user['companyName'],
          isSystem: user['isSystem'] ?? false,
          allowedCompanyIds:
              (user['allowedCompanyIds'] as List?)?.cast<int>() ?? [],
        ),
      );

      await storageService.saveLoginState(
        isLoggedIn: true,
        database: database,
        url: url,
        password: '',
      );

      // Clear stale company selection so the account's own company is used
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('selected_company_id');
      await prefs.remove('selected_allowed_company_ids');

      // Wipe the old client/session so getClientEnsured() rebuilds from prefs
      await CompanySessionManager.clearSessionCache();

      // Re-authenticate with the stored password to get a fresh session.
      // This prevents stale/expired sessionIds from causing data mismatches
      // on the first API call after switching.
      final storedPassword = await SecureStorageService().getPassword(
        url: url,
        database: database,
        username: userLogin,
      );
      if (storedPassword != null && storedPassword.isNotEmpty) {
        await CompanySessionManager.loginAndSaveSession(
          serverUrl: url,
          database: database,
          userLogin: userLogin,
          password: storedPassword,
        );
      }

      // Clear ALL Hive caches to prevent any data leakage between accounts
      await HiveService().clearAllData();
    } catch (e) {
      // Non-fatal: if re-auth fails (e.g. no internet) the Dashboard
      // will handle the error state gracefully via its own retry logic.
    }

    if (!mounted) return;
    // pushAndRemoveUntil also dismisses the loading dialog automatically
    Navigator.pushAndRemoveUntil(
      context,
      _buildPageRoute(motionProvider, const Dashboard()),
      (route) => false,
    );
  }
}
