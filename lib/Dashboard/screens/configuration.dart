import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:odoo_delivery_app/Dashboard/screens/profile/pages/profile_page.dart';
import 'package:odoo_delivery_app/Dashboard/screens/settings/pages/settings_page.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../LoginPage/models/session_model.dart';
import '../../LoginPage/services/storage_service.dart';
import '../../core/company/session/company_session_manager.dart';
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
  String? currentUrl;
  String? currentDatabase;

  /// Initializes storage services and sets up Odoo client session.
  ///
  /// Called once when the screen is first created.
  @override
  void initState() {
    super.initState();
    storageService = DashboardStorageService();
    loginStorageService = StorageService();
    _initializeOdooClient();
    _loadStoredAccounts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadStoredAccounts();
  }

  /// Loads the list of stored accounts from SharedPreferences.
  Future<void> _loadStoredAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      currentUrl = prefs.getString('url')??"";
      currentDatabase = prefs.getString('selectedDatabase')??"";
      setState(() {});
    } catch (_) {}
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


  /// Checks if base64 string represents an SVG image
  bool isSvgBase64(String data) {
    try {
      final decoded = utf8.decode(base64Decode(data), allowMalformed: true);
      return decoded.contains('<svg');
    } catch (_) {
      return false;
    }
  }

  /// Checks if bytes represent an SVG image (looks for `<svg` tag)
  bool isSvgBytes(Uint8List bytes) {
    final str = utf8.decode(bytes, allowMalformed: true);
    return str.contains('<svg');
  }

  String safeString(dynamic value, {String fallback = "Unknown"}) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return fallback;
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
    final imageData = profile?['image_1920'];

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
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: ClipOval(
                        child: SizedBox(
                          width: 100,
                          height: 100,
                          child: (imageData != null && imageData is String && imageData.isNotEmpty)
                              ? isSvgBase64(imageData)
                              ? SvgPicture.memory(
                            base64Decode(imageData),
                            fit: BoxFit.cover,
                          )
                              : Image.memory(
                            base64Decode(imageData),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              HugeIcons.strokeRoundedUser,
                              color: Colors.white,
                              size: 30,
                            ),
                          )
                              : widget.profileImageBytes != null
                              ? isSvgBytes(widget.profileImageBytes!)
                              ? SvgPicture.memory(
                            widget.profileImageBytes!,
                            fit: BoxFit.cover,
                          )
                              : Image.memory(
                            widget.profileImageBytes!,
                            fit: BoxFit.cover,
                          )
                              : const Icon(
                            HugeIcons.strokeRoundedUser,
                            size: 30,
                            color: Colors.white,
                          ),
                        ),
                      ),
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
                            safeString(profile?['email'], fallback: widget.mail ?? "Unknown"),                            style: TextStyle(
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
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
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

                            final otherAccounts = accounts.where((user) {
                              final userUrl = user['url'] ?? '';
                              final userDatabase = user['database'] ?? '';
                              final userName = user['userName'] ?? '';
                              final userId = user['userId'] ?? '';

                              final isSameAccount =
                                  userUrl == currentUrl &&
                                      userDatabase == currentDatabase &&
                                      userId ==  profile?['id'];

                              return !isSameAccount &&
                                  userName.isNotEmpty;
                            }).toList();

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
                                  try {
                                    if (user['image'] != null &&
                                        (user['image'] as String).isNotEmpty) {
                                      avatar = base64Decode(user['image']);
                                    }
                                  } catch (_) {}

                                  return Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF434242) : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.08),
                                          offset: const Offset(0, -2),
                                          blurRadius: 6,
                                        ),
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.08),
                                          offset: const Offset(0, 3),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: AppStyle.primaryColor,
                                          child: avatar == null
                                              ? const Icon(
                                            HugeIcons.strokeRoundedUser,
                                            color: Colors.white,
                                          )
                                              : isSvgBytes(avatar)
                                              ? ClipOval(
                                            child: SvgPicture.memory(
                                              avatar,
                                              width: 40,
                                              height: 40,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                              : ClipOval(
                                            child: Image.memory(
                                              avatar,
                                              width: 40,
                                              height: 40,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                        title: Builder(
                                          builder: (_) {
                                            final name = user['userName'] ?? '';
                                            final url = user['url'] ?? '';
                                            final db = user['database'] ?? '';

                                            String suffix = "";

                                            if (url != currentUrl) {
                                              suffix = " ($url)";
                                            } else if (db != currentDatabase) {
                                              suffix = " ($db)";
                                            }

                                            return Text.rich(
                                              TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text: name,
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w500,
                                                      fontSize: 16,
                                                      color: isDark ? Colors.white : Colors.black87,
                                                    ),
                                                  ),
                                                  if (suffix.isNotEmpty)
                                                    TextSpan(
                                                      text: suffix,
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w400,
                                                        fontSize: 13,
                                                        color: Colors.blue[700],
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            );
                                          },
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
                                        trailing: OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                            minimumSize: const Size(50, 28),
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            side: BorderSide(
                                              color: isDark ? Colors.white : AppStyle.primaryColor,
                                              width: 1,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                          ),
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
                                      ),
                                    ),
                                  );
                                }).toList(),

                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 16
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
                                        final session = await CompanySessionManager.getCurrentSession();

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
                                                      session: session!,
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
      password: user['password']??"",
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
