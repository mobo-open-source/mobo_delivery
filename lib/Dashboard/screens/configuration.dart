import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../LoginPage/models/session_model.dart';
import '../../LoginPage/services/storage_service.dart';
import '../../core/company/services/connectivity_service.dart';
import '../../core/company/session/company_session_manager.dart';
import '../../shared/utils/app_theme.dart';
import '../../shared/widgets/action_tile.dart';
import '../../shared/widgets/buttons/mobo_button.dart';
import '../../shared/widgets/odoo_avatar.dart';
import '../../shared/widgets/snackbar.dart';
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
  ///
  /// Always completes within the timeout so `_isLoading` cannot stick true
  /// on a slow / unreachable Odoo. The page renders without waiting for
  /// this — only the profile header card relies on the result.
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
      }).timeout(const Duration(seconds: 15));

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
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
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
    final imageData = profile?['image_1920'];

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
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (profile == null && !_isLoading) _buildOfflineBanner(isDark),

              const SizedBox(height: 12),

              ProfileHeaderCard(
                name:
                    profile?['name']?.toString() ??
                    widget.userName ??
                    'Unknown User',
                email:
                    (profile?['email'] != null && profile?['email'] != false)
                        ? profile!['email'].toString()
                        : widget.mail ?? '',
                jobFunction: '',
                avatarBase64: _userAvatarBase64,
                showCameraButton: false,
                onTap: () async {
                  await Navigator.push(
                    context,
                    _buildPageRoute(
                      const ProfileDetailScreen(),
                    ),
                  );
                  _loadProfile();
                },
              ),
              const SizedBox(height: 12),

              _buildQuickActionsSection(context),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionsSection(
    BuildContext context,
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
          ActionTile(
            title: 'Settings',
            subtitle: 'App preferences and sync options',
            icon: HugeIcons.strokeRoundedSettings02,
            onTap: () {
              Navigator.push(
                context,
                _buildPageRoute(const SettingsPage()),
              );
            },
          ),
          _buildDivider(isDark),

          _buildSwitchAccountsTile(context, isDark),
          _buildDivider(isDark),

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
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(HugeIcons.strokeRoundedUserSwitch, color: iconColor),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          'Switch Accounts',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          'Manage and switch between accounts',
          style: TextStyle(color: subtitleColor),
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
                      ),
                  ),
                  _buildAddAccountButton(context, isDark),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyAccountState(bool isDark) {
    // Matches the sales app: a simple text-only empty state (no illustration).
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryColor.withOpacity(isDark ? 0.18 : 0.10),
            ),
            child: Icon(
              HugeIcons.strokeRoundedUserAdd01,
              size: 32,
              color: AppTheme.primaryColor,
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            user['database'] ?? 'Unknown Database',
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(
            Icons.more_vert,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            size: 20,
          ),
          tooltip: 'Account options',
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          onSelected: (value) {
            if (value == 'remove') _confirmRemoveAccount(user);
          },
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: 'remove',
              child: Row(
                children: [
                  Icon(
                    HugeIcons.strokeRoundedDelete02,
                    size: 18,
                    color: Colors.red[600],
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Remove',
                    style: TextStyle(
                      color: Colors.red[600],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        onTap: () => _switchAccount(user),
      ),
    );
  }

  Future<void> _confirmRemoveAccount(Map<String, dynamic> user) async {
    final confirmed = await CommonDialog.confirm(
      context,
      title: 'Remove Account?',
      message:
          'Remove ${user['userName'] ?? 'this account'} from this device? You can add it back later by signing in again.',
      confirmText: 'Remove',
      cancelText: 'Cancel',
      centered: false,
    );
    if (confirmed != true || !mounted) return;

    try {
      await storageService.removeAccount(
        userLogin: user['userLogin'] ?? '',
        userName: user['userName'] ?? '',
        userId: user['userId'] ?? 0,
        url: user['url'] ?? '',
        database: user['database'] ?? '',
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(context, 'Failed to remove account: $e');
      }
    }
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
    ) {
    return Container(
      margin: const EdgeInsets.all(16),
      width: double.infinity,
      child: MoboButton.primary(
        label: 'Add Account',
        icon: HugeIcons.strokeRoundedUserAdd01,
        onPressed: () async {
          final prefs = await SharedPreferences.getInstance();
          final url = prefs.getString('url') ?? '';
          final database = prefs.getString('selectedDatabase') ?? '';
          final session = await CompanySessionManager.getCurrentSession();
          if (!mounted || session == null) return;

          Navigator.push(
            this.context,
            _buildPageRoute(
              ServerUrlScreen(
                serverUrl: url,
                database: database,
                session: session,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOfflineBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(HugeIcons.strokeRoundedLocationOffline01, size: 16, color: Colors.orange[700]),
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

  PageRoute _buildPageRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  Future<void> _switchAccount(
    Map<String, dynamic> user,
    ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: isDark ? Colors.grey[900] : Colors.white,
            surfaceTintColor: Colors.transparent,
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

    final url = (user['url'] as String? ?? '').trim();
    final database = (user['database'] as String? ?? '').trim();
    final userLogin = (user['userLogin'] as String? ?? '').trim();
    final displayName = (user['userName'] as String?)?.trim().isNotEmpty == true
        ? user['userName'] as String
        : userLogin;

    Future<void> abort(String message) async {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      CustomSnackbar.showError(context, message);
    }

    if (url.isEmpty || database.isEmpty || userLogin.isEmpty) {
      await abort(
        'Cannot switch: this account is missing server URL, database, '
        'or username. Please remove it and add again.',
      );
      return;
    }

    final storedPassword = await SecureStorageService().getPassword(
      url: url,
      database: database,
      username: userLogin,
    );
    if (storedPassword == null || storedPassword.isEmpty) {
      await abort(
        'Cannot switch to $displayName: saved password not found. '
        'Please remove this account and sign in again.',
      );
      return;
    }

    final prevSession = await CompanySessionManager.getCurrentSession();
    final prefs = await SharedPreferences.getInstance();
    final prevUrl = prefs.getString('url');
    final prevDatabase =
        prefs.getString('selectedDatabase') ?? prefs.getString('database');

    try {
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
      await prefs.remove('selected_company_id');
      await prefs.remove('selected_allowed_company_ids');
      await CompanySessionManager.clearSessionCache();
    } catch (e) {
      await _rollbackSwitch(prevSession, prevUrl, prevDatabase);
      await abort('Could not prepare account switch: ${_extractReason(e)}');
      return;
    }

    bool reauthOk = false;
    String? reauthReason;
    try {
      reauthOk = await CompanySessionManager.loginAndSaveSession(
        serverUrl: url,
        database: database,
        userLogin: userLogin,
        password: storedPassword,
      ).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      reauthReason =
          'Server took too long to confirm the session. Account was not switched.';
    } on NoInternetException {
      reauthReason =
          'No internet connection. Connect and try switching again.';
    } on ServerUnreachableException {
      reauthReason =
          'Could not reach $url. Verify the server and try again.';
    } catch (e) {
      reauthReason =
          'Could not sign in to $displayName: ${_extractReason(e)}';
    }

    if (!reauthOk) {
      await _rollbackSwitch(prevSession, prevUrl, prevDatabase);
      await abort(
        reauthReason ??
            'Could not sign in to $displayName. Account was not switched.',
      );
      return;
    }

    await HiveService().clearAllData();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      _buildPageRoute(const Dashboard()),
      (route) => false,
    );
  }

  /// Restores the previous account's session prefs after a failed switch.
  Future<void> _rollbackSwitch(
    SessionModel? prevSession,
    String? prevUrl,
    String? prevDatabase,
  ) async {
    try {
      if (prevSession != null) {
        await storageService.saveSession(prevSession);
      }
      if (prevUrl != null && prevDatabase != null) {
        await storageService.saveLoginState(
          isLoggedIn: true,
          database: prevDatabase,
          url: prevUrl,
          password: '',
        );
      }
      await CompanySessionManager.clearSessionCache();
    } catch (_) {
    }
  }

  /// Extracts a short, user-readable reason from an arbitrary exception.
  String _extractReason(Object e) {
    final raw = e.toString().toLowerCase();
    if (raw.contains('wrong login') ||
        raw.contains('invalid login') ||
        raw.contains('access denied') ||
        raw.contains('accessdenied') ||
        raw.contains('wrong credentials')) {
      return 'wrong saved password — remove and add this account again.';
    }
    if (raw.contains('database') && raw.contains('not found')) {
      return 'database no longer exists on this server.';
    }
    if (raw.contains('socket') || raw.contains('network')) {
      return 'network error — check your connection.';
    }
    if (raw.contains('certificate') || raw.contains('ssl')) {
      return 'SSL/certificate problem reaching the server.';
    }
    return 'unexpected error. Please try again.';
  }
}
