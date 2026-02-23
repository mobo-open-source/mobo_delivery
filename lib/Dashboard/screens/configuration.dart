import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:odoo_delivery_app/Dashboard/screens/profile/pages/profile_page.dart';
import 'package:odoo_delivery_app/Dashboard/screens/settings/pages/settings_page.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../LoginPage/models/session_model.dart';
import '../../LoginPage/services/storage_service.dart';
import '../../core/providers/motion_provider.dart';
import '../../shared/utils/app_theme.dart';
import '../../shared/utils/globals.dart';
import '../services/odoo_dashboard_service.dart';
import '../services/storage_service.dart';
import '../widgets/dashboard/logout_dialog.dart';
import 'SwitchAccount/server_url_screen.dart';
import 'dashboard/pages/dashboard.dart';

/// Configuration screen for managing user account settings.
///
/// Displays:
/// • User profile summary
/// • App settings navigation
/// • Account switching options
/// • Logout functionality
///
/// Accepts optional profile image, username, and email for fallback display.
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

/// Handles state, session initialization, and data loading for [Configuration].
///
/// Responsibilities:
/// • Initialize Odoo session client
/// • Load and update user profile data
/// • Manage stored accounts and switching
/// • Handle logout and navigation flows
class _ConfigurationState extends State<Configuration> {
  late DashboardStorageService storageService;
  late StorageService loginStorageService;
  Map<String, dynamic>? profile;
  int? userId;
  int? companyId;
  bool? isSystem;
  late OdooDashboardService odooService;

  /// Initializes storage services and sets up Odoo client session.
  ///
  /// Called once when the screen is first created.
  @override
  void initState() {
    super.initState();
    storageService = DashboardStorageService();
    loginStorageService = StorageService();
    _initializeOdooClient();
  }

  /// Initializes Odoo client using stored session data.
  ///
  /// Creates an Odoo session instance and dashboard service,
  /// then loads the user profile from server.
  Future<void> _initializeOdooClient() async {
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
    await loadProfile();
  }

  /// Fetches and updates user profile details from Odoo server.
  ///
  /// Updates UI state with latest profile information.
  Future<void> loadProfile() async {
    final fetchedProfile = await odooService.getUserProfile(userId ?? 0);
    if (!mounted) return;
    setState(() {
      profile = fetchedProfile;
    });
  }

  /// Builds the Configuration screen UI.
  ///
  /// Includes:
  /// • Profile summary card
  /// • Settings navigation
  /// • Account switching expansion list
  /// • Add account action
  /// • Logout option
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final motionProvider = Provider.of<MotionProvider>(context, listen: false);

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        leading: IconButton(
          icon: Icon(
            HugeIcons.strokeRoundedArrowLeft01,
            color: isDark ? Colors.white : Colors.black,
            size: 28,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Configuration',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 22,
          ),
        ),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        ProfileSettingsPage(refreshProfile: loadProfile),
                    transitionDuration: motionProvider.reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    reverseTransitionDuration: motionProvider.reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          if (motionProvider.reduceMotion) return child;
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundImage:
                          (profile?['image_1920'] is String &&
                              (profile!['image_1920'] as String).isNotEmpty)
                          ? MemoryImage(
                              base64Decode(profile?['image_1920'] as String),
                            )
                          : (widget.profileImageBytes != null
                                ? MemoryImage(widget.profileImageBytes!)
                                : null),

                      child:
                          ((profile?['image_1920'] == null ||
                                  !(profile?['image_1920'] is String) ||
                                  (profile?['image_1920'] as String).isEmpty) &&
                              widget.profileImageBytes == null)
                          ? const Icon(
                              Icons.person,
                              size: 30,
                              color: AppStyle.primaryColor,
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile?['name'] ?? widget.userName ?? "Unknown",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            profile?['email'] ?? widget.mail ?? "Unknown",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.settings_outlined,
                      color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
                    ),
                    title: Text(
                      "Settings",
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.normal,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      "App preferences and sync options",
                      style: TextStyle(
                        color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  const SettingsPage(),
                          transitionDuration: motionProvider.reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 300),
                          reverseTransitionDuration: motionProvider.reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 300),
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                                if (motionProvider.reduceMotion) return child;
                                return FadeTransition(
                                  opacity: animation,
                                  child: child,
                                );
                              },
                        ),
                      );
                    },
                  ),

                  Divider(
                    height: 1,
                    thickness: 1,
                    color: isDark ? Colors.grey[800] : Colors.grey[200],
                    indent: 20,
                    endIndent: 20,
                  ),

                  Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      leading: Icon(
                        HugeIcons.strokeRoundedUserSwitch,
                        color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
                      ),
                      title: Text(
                        'Switch Accounts',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.normal,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        "Manage and switch between accounts",
                        style: TextStyle(
                          color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
                        ),
                      ),
                      children: [
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: storageService.getAccounts(),
                          builder: (context, snapshot) {
                            final accounts = snapshot.data ?? [];
                            if (accounts.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  "No accounts",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              );
                            }
                            final otherAccounts = accounts
                                .where(
                                  (user) =>
                                      user['userId'] != profile?['id'] &&
                                      user['userName'] != null &&
                                      (user['userName'] as String).isNotEmpty,
                                )
                                .toList();

                            return Column(
                              children: [
                                if (otherAccounts.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      children: [
                                        Icon(
                                          HugeIcons.strokeRoundedUserAdd01,
                                          size: 30,
                                          color: isDark
                                              ? Colors.grey[600]
                                              : Colors.grey[400],
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          "No Additional Accounts",
                                          style: TextStyle(
                                            color: isDark ? Colors.white : Colors.black87,
                                            fontSize: 16,
                                          ),
                                        ),
                                        SizedBox(height: 5,),
                                        Text(
                                          'Add multiple accounts to switch between them quickly',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ...otherAccounts.map((user) {
                                  Uint8List? avatar;
                                  if (user['image'] != null &&
                                      (user['image'] as String).isNotEmpty) {
                                    try {
                                      avatar = base64Decode(user['image']);
                                    } catch (_) {}
                                  }

                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundImage: avatar != null
                                          ? MemoryImage(avatar)
                                          : null,
                                      child: avatar == null
                                          ? const Icon(Icons.person)
                                          : null,
                                    ),
                                    title: Text(
                                      user['userName']!,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 16,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                    subtitle: Text(
                                      user['userLogin'] ?? "",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w400,
                                        fontSize: 13,
                                        color: isDark
                                            ? Colors.grey[400]!
                                            : Colors.grey[600]!,
                                      ),
                                    ),
                                    trailing: TextButton(
                                      onPressed: () async {
                                        await switchAccount(user);
                                      },
                                      child: Text(
                                        "Switch",
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.white
                                              : AppTheme.primaryColor,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),

                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: () async{
                                        final prefs =
                                            await SharedPreferences
                                            .getInstance();
                                        final url =
                                            prefs.getString('url') ??
                                                '';
                                        final database =
                                            prefs.getString(
                                                'selectedDatabase') ??
                                                '';
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          PageRouteBuilder(
                                            pageBuilder:
                                                (
                                                  context,
                                                  animation,
                                                  secondaryAnimation,
                                                ) =>
                                                    ServerUrlScreen(
                                                      serverUrl: url,
                                                      database: database,
                                                    ),
                                            transitionDuration:
                                                motionProvider.reduceMotion
                                                ? Duration.zero
                                                : const Duration(
                                                    milliseconds: 300,
                                                  ),
                                            reverseTransitionDuration:
                                                motionProvider.reduceMotion
                                                ? Duration.zero
                                                : const Duration(
                                                    milliseconds: 300,
                                                  ),
                                            transitionsBuilder:
                                                (
                                                  context,
                                                  animation,
                                                  secondaryAnimation,
                                                  child,
                                                ) {
                                                  if (motionProvider
                                                      .reduceMotion)
                                                    return child;
                                                  return FadeTransition(
                                                    opacity: animation,
                                                    child: child,
                                                  );
                                                },
                                          ),
                                        );
                                      },
                                      icon: const Icon(
                                        HugeIcons.strokeRoundedUserAdd01,
                                      ),
                                      label: Text(
                                        "Add Account",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? Colors.black
                                              : Colors.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isDark
                                            ? Colors.white
                                            : AppTheme.primaryColor,
                                        foregroundColor: isDark
                                            ? Colors.black
                                            : Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  Divider(
                    height: 1,
                    thickness: 1,
                    color: isDark ? Colors.grey[800] : Colors.grey[200],
                    indent: 20,
                    endIndent: 20,
                  ),

                  ListTile(
                    leading: const Icon(Icons.logout, color: Color(0xFFD32F2F)),
                    title: Text(
                      "Logout",
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFFD32F2F),
                        fontWeight: FontWeight.normal,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      "Sign out from this device",
                      style: TextStyle(
                        color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
                      ),
                    ),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) =>
                            LogoutDialog(storageService: loginStorageService),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Switches active session to selected account.
  ///
  /// Steps:
  /// 1. Saves selected account session locally
  /// 2. Updates login state
  /// 3. Navigates to dashboard
  ///
  /// [user] Map containing selected account session data.
  Future<void> switchAccount(Map<String, dynamic> user) async {
    final motionProvider = Provider.of<MotionProvider>(context, listen: false);
    final storageService = DashboardStorageService();

    await storageService.saveSession(
      SessionModel(
        sessionId: user['sessionId'],
        userName: user['userName'],
        userLogin: user['userLogin'],
        userId: user['userId'],
        serverVersion: user['serverVersion'],
        userLang: user['userLang'],
        partnerId: user['partnerId'],
        userTimezone: user['userTimezone'],
        companyId: user['companyId'],
        companyName: user['companyName'],
        isSystem: user['isSystem'] ?? false,
      ),
    );

    await storageService.saveLoginState(
      isLoggedIn: true,
      database: user['database'],
      url: user['url'],
      password: user['password'],
    );

    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const Dashboard(),
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
        (route) => false,
      );
    }
  }
}
