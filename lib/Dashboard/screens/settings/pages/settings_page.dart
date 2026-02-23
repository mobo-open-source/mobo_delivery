import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_switch/flutter_switch.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:local_auth/local_auth.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/providers/motion_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../shared/utils/globals.dart';
import '../../../../shared/widgets/snackbar.dart';
import '../../../services/odoo_dashboard_service.dart';
import '../../../services/settings_storage_service.dart';
import '../../../services/storage_service.dart';
import '../../../widgets/settings/app_web.dart';
import '../bloc/settings_bloc.dart';
import '../bloc/settings_event.dart';
import '../bloc/settings_state.dart';

/// Main settings screen of the delivery app.
///
/// Features:
///   • Appearance: dark mode & reduce motion toggles
///   • Security: biometric app lock (fingerprint/face)
///   • Language & Region: language, currency, timezone selection
///   • Data & Storage: cache clearing
///   • Help & Support: links to Odoo resources
///   • About: company links, social media, copyright
///
/// Uses Bloc for state management of dynamic settings (language/currency/timezone)
/// and Provider for theme/motion preferences.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool isOnline = true;
  late OdooDashboardService odooService;
  late DashboardStorageService storageService;
  int? userId;
  int? companyId;
  bool? isSystem;
  bool _biometricEnabled = false;
  final LocalAuthentication _auth = LocalAuthentication();

  /// Initializes the Odoo client using stored session data.
  ///
  /// Retrieves session information from local storage and creates
  /// an Odoo session used for API communication.
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
  }
  @override
  void initState() {
    super.initState();
    _loadBiometricPreference();
    storageService = DashboardStorageService();
    _initAll();
  }

  /// Loads the saved biometric preference from local storage.
  ///
  /// Reads the biometric enabled state from SharedPreferences
  /// and updates the UI state accordingly.
  Future<void> _loadBiometricPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _biometricEnabled = prefs.getBool('biometricEnabled') ?? false;
    });
  }

  /// Enables or disables biometric authentication.
  ///
  /// When enabling:
  ///   • Checks device biometric capability
  ///   • Prompts user authentication
  ///   • Saves preference if successful
  ///
  /// When disabling:
  ///   • Updates preference and UI state
  Future<void> _toggleBiometric(bool value) async {
    final prefs = await SharedPreferences.getInstance();

    if (value) {
      bool canCheck = await _auth.canCheckBiometrics;
      bool isSupported = await _auth.isDeviceSupported();
      if (canCheck || isSupported) {
        bool authenticated = await _auth.authenticate(
          localizedReason: 'Enable biometric authentication',
          options: const AuthenticationOptions(
            biometricOnly: true,
            stickyAuth: true,
          ),
        );

        if (authenticated) {
          setState(() => _biometricEnabled = true);
          await prefs.setBool('biometricEnabled', true);
        }
      } else {
        CustomSnackbar.showError(context, 'Biometric authentication not supported on this device.');
        setState(() => _biometricEnabled = false);
        await prefs.setBool('biometricEnabled', false);
      }
    } else {
      setState(() => _biometricEnabled = false);
      await prefs.setBool('biometricEnabled', false);
    }

    if (mounted) {
      _biometricEnabled
          ? CustomSnackbar.showSuccess(context, 'Biometric authentication enabled.')
          : CustomSnackbar.showError(context, 'Biometric authentication disabled.');

    }
  }

  /// Initializes all required services and configurations.
  ///
  /// Includes:
  ///   • Odoo client initialization
  ///   • Network and service setup
  Future<void> _initAll() async {
    await _initializeOdooClient();
    await _initializeServices();
  }

  /// Initializes service-level dependencies.
  ///
  /// Currently checks network connectivity status
  /// and updates online/offline state.
  Future<void> _initializeServices() async {
    isOnline = await odooService.checkNetworkConnectivity();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocProvider(
      create: (context) => SettingsBloc(
        settingsStorageService: SettingsStorageService(),
        dashboardStorageService: DashboardStorageService(),
      ),
      child: Scaffold(
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
            'Settings',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 22,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          automaticallyImplyLeading: false,
        ),
        body: BlocConsumer<SettingsBloc, SettingsState>(
          listener: (context, state) {
            if (state.error != null) {
              CustomSnackbar.showError(context, state.error!);
            }
          },
          builder: (context, state) {
            final uniqueCurrencyItems = state.currencies
                .map((e) => e['full_name'].toString())
                .toSet()
                .map((e) => {'full_name': e})
                .toList();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildAppearanceSection(context, state),
                _buildSecuritySection(context, state),
                if(isOnline)
                  _buildLanguageAndRegionSection(context, state, uniqueCurrencyItems),
                _buildDataAndStorageSection(context),
                _buildHelpAndSupportSection(context, isDark),
                _buildAboutSection(context, isDark),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Builds the Appearance settings section.
  ///
  /// Includes:
  ///   • Dark mode toggle
  ///   • Reduce motion toggle
  ///
  /// Uses Provider and Bloc for state synchronization.
  Widget _buildAppearanceSection(BuildContext context, SettingsState state) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.themeMode == ThemeMode.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Appearance',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.dark_mode_outlined,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dark Mode',
                        style: TextStyle(
                          fontWeight: FontWeight.normal,
                          fontSize: 15,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      Text(
                        'Switch between light and dark themes',
                        style: TextStyle(
                          fontWeight: FontWeight.normal,
                          color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
                        ),
                      ),
                    ],
                  ),
                ),
                FlutterSwitch(
                  width: 60,
                  activeColor: isDark ? Colors.grey[400]! : AppStyle.primaryColor,
                  inactiveColor: isDark ? Colors.black : Colors.white,
                  value: state.isDarkMode,
                  onToggle: (value) {
                    context.read<SettingsBloc>().add(ToggleDarkModeEvent(value));
                    themeProvider.toggleTheme();
                  },
                  activeToggleColor: isDark ? Colors.black : Colors.white,
                  inactiveToggleColor: isDark ? Colors.grey[400]! : AppStyle.primaryColor,
                  showOnOff: false,
                  switchBorder: Border.all(
                    color: isDark ? Colors.grey[400]! : AppStyle.primaryColor,
                    width: 1.5,
                  ),
                  borderRadius: 30.0,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.visibility_off,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reduce Motion',
                        style: TextStyle(
                          fontWeight: FontWeight.normal,
                          fontSize: 15,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        'Minimize animations and motion effect',
                        style: TextStyle(
                          fontWeight: FontWeight.normal,
                          color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
                        ),
                      ),
                    ],
                  ),
                ),
                FlutterSwitch(
                  width: 60,
                  activeColor: isDark ? Colors.grey[400]! : AppStyle.primaryColor,
                  inactiveColor: isDark ? Colors.black : Colors.white,
                  value: state.reduceMotion,
                  onToggle: (val) {
                    context.read<SettingsBloc>().add(ToggleReduceMotionEvent(val));
                    Provider.of<MotionProvider>(context, listen: false)
                        .setReduceMotion(val);
                  },
                  activeToggleColor: isDark ? Colors.black : Colors.white,
                  inactiveToggleColor: isDark ? Colors.grey[400]! : AppStyle.primaryColor,
                  showOnOff: false,
                  switchBorder: Border.all(
                    color: isDark ? Colors.grey[400]! : AppStyle.primaryColor,
                    width: 1.5,
                  ),
                  borderRadius: 30.0,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the Security settings section.
  ///
  /// Provides biometric app lock toggle functionality.
  Widget _buildSecuritySection(BuildContext context, SettingsState state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Security',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  HugeIcons.strokeRoundedFingerprintScan,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'App Lock',
                        style: TextStyle(
                          fontWeight: FontWeight.normal,
                          fontSize: 15,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      Text(
                        'Enable biometric lock to keep your app secure.',
                        softWrap: true,
                        overflow: TextOverflow.visible,
                        style: TextStyle(
                          fontWeight: FontWeight.normal,
                          color: isDark
                              ? Colors.grey[400]!
                              : Colors.grey[600]!,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 10,),
                FlutterSwitch(
                  width: 60,
                  activeColor: isDark
                      ? Colors.grey[400]!
                      : const Color(0xFFC03355),
                  inactiveColor: isDark ? Colors.black : Colors.white,
                  value: _biometricEnabled,
                  onToggle: (val) async {
                    await _toggleBiometric(val);
                  },
                  activeToggleColor: isDark ? Colors.black : Colors.white,
                  inactiveToggleColor: isDark
                      ? Colors.grey[400]!
                      : const Color(0xFFC03355),
                  showOnOff: false,
                  switchBorder: Border.all(
                    color: isDark
                        ? Colors.grey[400]!
                        : const Color(0xFFC03355).withOpacity(0.7),
                    width: 1.5,
                  ),
                  borderRadius: 30.0,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the Language & Region settings section.
  ///
  /// Allows user to configure:
  ///   • Language
  ///   • Currency
  ///   • Timezone
  ///
  /// Values are fetched dynamically from server settings.
  Widget _buildLanguageAndRegionSection(
      BuildContext context, SettingsState state, List<Map<String, dynamic>> uniqueCurrencyItems) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String? localLanguageCode = state.languages.isNotEmpty
        ? state.languages.firstWhere(
          (lang) => lang['name'] == state.language,
      orElse: () => {'code': 'en_US'},
    )['code']
        : 'en_US';


    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Language & Region',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.refresh,
                  color: isDark ? Colors.grey[300] : Colors.grey[600],
                  size: 20,
                ),
                onPressed: () {
                  context.read<SettingsBloc>().add(RefreshLanguageAndRegionEvent());
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildDropdownTile(
            context: context,
            icon: HugeIcons.strokeRoundedTranslate,
            title: 'Language',
            subtitle: 'Select your preferred language',
            value: state.language,
            items: state.languages,
            displayKey: 'name',
            onChanged: (selectedName) {
              if (selectedName != null) {
                final selectedLang = state.languages.firstWhere(
                      (lang) => lang['name'] == selectedName,
                  orElse: () => {},
                );
                if (selectedLang.isNotEmpty) {
                  localLanguageCode = selectedLang['code'];
                  context.read<SettingsBloc>().add(
                    UpdateLanguageEvent(selectedName, selectedLang['code']),
                  );
                }
              }
            },
          ),
          _buildDropdownTile(
            context: context,
            icon: HugeIcons.strokeRoundedDollar01,
            title: 'Currency',
            subtitle: 'Default currency for transactions',
            value: state.currency,
            items: uniqueCurrencyItems,
            displayKey: 'full_name',
            onChanged: (selected) {
              if (selected != null) {
                context.read<SettingsBloc>().add(UpdateCurrencyEvent(selected));
              }
            },
          ),
          _buildDropdownTile(
            context: context,
            icon: HugeIcons.strokeRoundedClock01,
            title: 'Timezone',
            subtitle: 'Your local timezone',
            value: state.timezone,
            items: state.timezones,
            displayKey: 'name',
            onChanged: (selectedName) {
              if (selectedName != null) {
                final selectedTz = state.timezones.firstWhere(
                      (tz) => tz['name'] == selectedName,
                  orElse: () => {},
                );
                if (selectedTz.isNotEmpty) {
                  context.read<SettingsBloc>().add(
                    UpdateTimezoneEvent(selectedName, selectedTz['code'], localLanguageCode!),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  /// Builds the Data & Storage settings section.
  ///
  /// Provides cache usage information and cache clearing option.
  Widget _buildDataAndStorageSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Data & Storage',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_sweep_outlined,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            title: Text(
              'Clear Cache',
              style: TextStyle(
                fontWeight: FontWeight.normal,
                fontSize: 15,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            subtitle: FutureBuilder<int>(
              future: _getCacheSize(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return Text('Calculating...');
                final sizeInMB = (snapshot.data! / (1024 * 1024)).toStringAsFixed(2);
                return Text(
                  sizeInMB == '0.00' ? 'No cache data' : '$sizeInMB MB • Free up space by clearing temporary data',
                  style: TextStyle(
                    fontWeight: FontWeight.normal,
                    color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
                  ),
                );
              },
            ),
            onTap: () {
              context.read<SettingsBloc>().add(ClearCacheEvent());
              CustomSnackbar.showSuccess(context, 'Cache cleared successfully');
            },
          ),
        ],
      ),
    );
  }

  /// Builds the Help & Support section.
  ///
  /// Contains links to:
  ///   • Documentation
  ///   • Support portal
  ///   • Community forum
  Widget _buildHelpAndSupportSection(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Help & Support',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          ListTile(
            leading: Icon(
              HugeIcons.strokeRoundedHelpCircle,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            title: Text(
              'Odoo Help Center',
              style: TextStyle(
                fontWeight: FontWeight.normal,
                fontSize: 15,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            subtitle: Text(
              'Documentation, guides and resources',
              style: TextStyle(
                fontWeight: FontWeight.normal,
                color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
              ),
            ),
            onTap: () => _launchUrl(context, "https://www.odoo.com/documentation"),
          ),
          ListTile(
            leading: Icon(
              HugeIcons.strokeRoundedCustomerSupport,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            title: Text(
              'Odoo Support',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.normal,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            subtitle: Text(
              'Create a ticket with Odoo Support',
              style: TextStyle(
                fontWeight: FontWeight.normal,
                color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
              ),
            ),
            onTap: () => _launchUrl(context, "https://www.odoo.com/help"),
          ),
          ListTile(
            leading: Icon(
              HugeIcons.strokeRoundedUserGroup,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            title: Text(
              'Odoo Community Forum',
              style: TextStyle(
                fontWeight: FontWeight.normal,
                fontSize: 15,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            subtitle: Text(
              'Ask the community for help',
              style: TextStyle(
                fontWeight: FontWeight.normal,
                color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
              ),
            ),
            onTap: () => _launchUrl(context, "https://www.odoo.com/forum/help-1"),
          ),
        ],
      ),
    );
  }

  /// Builds the About section.
  ///
  /// Includes:
  ///   • Company website
  ///   • Contact details
  ///   • Social media links
  ///   • Copyright information
  Widget _buildAboutSection(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          ListTile(
            leading: Icon(
              HugeIcons.strokeRoundedGlobe02,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            title: Text(
              'Visit Website',
              style: TextStyle(
                fontWeight: FontWeight.normal,
                fontSize: 15,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            subtitle: Text(
              'www.cybrosys.com',
              style: TextStyle(
                fontWeight: FontWeight.normal,
                color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
              ),
            ),
            onTap: () => _launchUrl(context, "https://www.cybrosys.com"),
          ),
          ListTile(
            leading: Icon(
              HugeIcons.strokeRoundedMail01,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            title: Text(
              'Contact Us',
              style: TextStyle(
                fontWeight: FontWeight.normal,
                fontSize: 15,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            subtitle: Text(
              'info@cybrosys.com',
              style: TextStyle(
                fontWeight: FontWeight.normal,
                color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
              ),
            ),
            onTap: () => _launchUrl(context, "mailto:info@cybrosys.com"),
          ),
          ListTile(
            leading: Icon(
              HugeIcons.strokeRoundedPlayStore,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            title: Text(
              'More Apps',
              style: TextStyle(
                fontWeight: FontWeight.normal,
                fontSize: 15,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            subtitle: Text(
              'View our other apps on Play Store',
              style: TextStyle(
                fontWeight: FontWeight.normal,
                color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
              ),
            ),
            onTap: () => _launchUrl(
              context,
              "https://play.google.com/store/apps/developer?id=Cybrosys",
            ),
          ),
          const SizedBox(height: 12),
          Divider(color: isDark ? Colors.grey[800] : Colors.grey[200]),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Follow Us',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 18,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSocialButton(
                  context,
                  'assets/facebook.png',
                  const Color(0xFF1877F2),
                      () => _launchUrlSmart(
                    context,
                    'https://www.facebook.com/cybrosystechnologies',
                    title: 'Facebook',
                  ),
                ),
                const SizedBox(width: 16),
                _buildSocialButton(
                  context,
                  'assets/linkedin.png',
                  const Color(0xFF0077B5),
                      () => _launchUrlSmart(
                    context,
                    'https://www.linkedin.com/company/cybrosys/',
                    title: 'LinkedIn',
                  ),
                ),
                const SizedBox(width: 16),
                _buildSocialButton(
                  context,
                  'assets/instagram.png',
                  const Color(0xFFE4405F),
                      () => _launchUrlSmart(
                    context,
                    'https://www.instagram.com/cybrosystech/',
                    title: 'Instagram',
                  ),
                ),
                const SizedBox(width: 16),
                _buildSocialButton(
                  context,
                  'assets/youtube.png',
                  const Color(0xFFFF0000),
                      () => _launchUrlSmart(
                    context,
                    'https://www.youtube.com/channel/UCKjWLm7iCyOYINVspCSanjg',
                    title: 'YouTube',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              '© ${DateTime.now().year} Cybrosys Technologies',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white : AppStyle.primaryColor,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a social media icon button with underline indicator.
  ///
  /// Used in About section for social links.
  Widget _buildSocialButton(
      BuildContext context, String assetPath, Color underlineColor, VoidCallback onPressed) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(.8) : AppStyle.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
          ),
          child: IconButton(
            onPressed: onPressed,
            icon: Image.asset(
              assetPath,
              width: 24,
              height: 24,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 48,
          height: 3,
          decoration: BoxDecoration(
            color: underlineColor,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
      ],
    );
  }

  /// Launches the given URL in an external application.
  ///
  /// Shows error snackbar if launch fails.
  Future<void> _launchUrl(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      CustomSnackbar.showError(context, 'Could not launch $url');
    }
  }

  /// Attempts to launch URL externally.
  ///
  /// If external launch fails, opens URL in in-app web view.
  Future<void> _launchUrlSmart(BuildContext context, String url, {String? title}) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _openInAppWebPage(context, uri, title: title);
    }
  }

  /// Opens URL inside the app using in-app web view.
  ///
  /// Applies transition animation based on motion settings.
  Future<void> _openInAppWebPage(BuildContext context, Uri url, {String? title}) async {
    final motionProvider = Provider.of<MotionProvider>(context, listen: false);
    try {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => InAppWebPage(url: url, title: title),
          transitionDuration:
          motionProvider.reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
          reverseTransitionDuration:
          motionProvider.reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (motionProvider.reduceMotion) return child;
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } catch (e) {
      CustomSnackbar.showError(context, 'Could not open page: ${e.toString()}');
    }
  }

  /// Builds a reusable dropdown settings tile.
  ///
  /// Used for language, currency, and timezone selection.
  Widget _buildDropdownTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    required List<Map<String, dynamic>> items,
    required String displayKey,
    required ValueChanged<String?> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      leading: Icon(icon, color: isDark ? Colors.grey[400] : Colors.grey[600]),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.normal,
          fontSize: 15,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontWeight: FontWeight.normal,
          color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
        ),
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 120),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey[200],
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButton<String>(
            value: value,
            items: items.map((item) {
              final itemValue = item[displayKey].toString();
              return DropdownMenuItem<String>(
                value: itemValue,
                child: Text(
                  itemValue,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 12,
                  ),
                ),
              );
            }).toList(),
            onChanged: onChanged,
            underline: const SizedBox(),
            dropdownColor: isDark ? Color(0xFF1F1F1F) : Colors.white,
            isDense: true,
            isExpanded: true,
          ),
        ),
      ),
    );
  }

  /// Calculates total cache size from temporary directory.
  ///
  /// Returns total size in bytes.
  Future<int> _getCacheSize() async {
    Directory cacheDir = await getTemporaryDirectory();
    return _getTotalSizeOfFilesInDir(cacheDir);
  }

  Future<int> _getTotalSizeOfFilesInDir(final FileSystemEntity file) async {
    if (file is File) {
      return await file.length();
    }
    if (file is Directory) {
      final List<FileSystemEntity> children = file.listSync();
      int total = 0;
      for (final child in children) {
        total += await _getTotalSizeOfFilesInDir(child);
      }
      return total;
    }
    return 0;
  }
}