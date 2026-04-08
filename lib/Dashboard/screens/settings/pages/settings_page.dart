import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:local_auth/local_auth.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../shared/widgets/snackbar.dart';
import '../../../../shared/widgets/section_card.dart';
import '../../../../shared/widgets/action_tile.dart';
import '../../../services/odoo_dashboard_service.dart';
import '../../../services/settings_storage_service.dart';
import '../../../services/storage_service.dart';
import '../bloc/settings_bloc.dart';
import '../bloc/settings_event.dart';
import '../bloc/settings_state.dart';
import '../widgets/switch_tile.dart';
import '../widgets/odoo_dropdown_tile.dart';

/// Main settings screen of the delivery app.
///
/// Matches the exact UI of mobo_inv_app with:
///   • Appearance: dark mode & reduce motion toggles (MoboToggle style)
///   • Security: biometric app lock
///   • Language & Region: OdooDropdownTile with loading state
///   • Data & Storage: cache clearing
///   • Help & Support: links to Odoo resources
///   • Account: logout with confirmation dialog + loading progress
///   • About: company links, social media, copyright
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

  Future<void> _loadBiometricPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _biometricEnabled = prefs.getBool('biometricEnabled') ?? false;
    });
  }

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
        if (mounted) {
          CustomSnackbar.showError(
            context,
            'Biometric authentication not supported on this device.',
          );
        }
        setState(() => _biometricEnabled = false);
        await prefs.setBool('biometricEnabled', false);
      }
    } else {
      setState(() => _biometricEnabled = false);
      await prefs.setBool('biometricEnabled', false);
    }

    if (mounted) {
      _biometricEnabled
          ? CustomSnackbar.showSuccess(
              context,
              'Biometric authentication enabled.',
            )
          : CustomSnackbar.showError(
              context,
              'Biometric authentication disabled.',
            );
    }
  }

  Future<void> _initAll() async {
    await _initializeOdooClient();
    isOnline = await odooService.checkNetworkConnectivity();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.grey[900]! : Colors.grey[50]!;

    return BlocProvider(
      create: (context) => SettingsBloc(
        settingsStorageService: SettingsStorageService(),
        dashboardStorageService: DashboardStorageService(),
      ),
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          forceMaterialTransparency: true,
          backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
          elevation: 0,
          leading: IconButton(
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedArrowLeft01,
              color: isDark ? Colors.white : Colors.black,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'Settings',
            style: TextStyle(
              fontWeight: FontWeight.bold,
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
                const SizedBox(height: 16),
                _buildSecuritySection(context),
                const SizedBox(height: 16),
                if (isOnline) ...[
                  _buildLanguageAndRegionSection(
                    context,
                    state,
                    uniqueCurrencyItems,
                  ),
                  const SizedBox(height: 16),
                ],
                _buildDataAndStorageSection(context),
                const SizedBox(height: 16),
                _buildHelpAndSupportSection(context),
                const SizedBox(height: 16),
                _buildAboutSection(context, isDark),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppearanceSection(BuildContext context, SettingsState state) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;

    return SectionCard(
      title: 'Appearance',
      icon: HugeIcons.strokeRoundedPaintBoard,
      children: [
        SwitchTile(
          title: 'Dark Mode',
          subtitle: isDarkMode ? 'Dark theme is active' : 'Light theme is active',
          icon: isDarkMode
              ? HugeIcons.strokeRoundedMoon02
              : HugeIcons.strokeRoundedSun03,
          value: isDarkMode,
          onChanged: (value) {
            context.read<SettingsBloc>().add(ToggleDarkModeEvent(value));
            themeProvider.toggleTheme();
          },
        ),
      ],
    );
  }

  Widget _buildSecuritySection(BuildContext context) {
    return SectionCard(
      title: 'Security',
      icon: HugeIcons.strokeRoundedSecurity,
      children: [
        SwitchTile(
          title: 'App Lock',
          subtitle: 'Enable biometric lock to keep your app secure',
          icon: HugeIcons.strokeRoundedFingerprintScan,
          value: _biometricEnabled,
          onChanged: (val) => _toggleBiometric(val),
        ),
      ],
    );
  }

  Widget _buildLanguageAndRegionSection(
    BuildContext context,
    SettingsState state,
    List<Map<String, dynamic>> uniqueCurrencyItems,
  ) {
    String? localLanguageCode = state.languages.isNotEmpty
        ? state.languages.firstWhere(
            (lang) => lang['name'] == state.language,
            orElse: () => {'code': 'en_US'},
          )['code']
        : 'en_US';

    return SectionCard(
      title: 'Language & Region',
      icon: HugeIcons.strokeRoundedSettings02,
      headerTrailing: IconButton(
        tooltip: 'Refresh',
        onPressed: () {
          context.read<SettingsBloc>().add(RefreshLanguageAndRegionEvent());
        },
        icon: const Icon(Icons.refresh, size: 18),
      ),
      children: [
        OdooDropdownTile(
          title: 'Language',
          subtitle: 'Select your preferred language',
          icon: HugeIcons.strokeRoundedTranslate,
          selectedValue: state.language,
          options: state.languages,
          isLoading: state.isLanguageLoading,
          displayKey: 'name',
          valueKey: 'name',
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
        OdooDropdownTile(
          title: 'Currency',
          subtitle: 'Default currency for transactions',
          icon: HugeIcons.strokeRoundedDollar01,
          selectedValue: state.currency,
          options: uniqueCurrencyItems,
          isLoading: state.isLanguageLoading,
          displayKey: 'full_name',
          valueKey: 'full_name',
          onChanged: (selected) {
            if (selected != null) {
              context.read<SettingsBloc>().add(UpdateCurrencyEvent(selected));
            }
          },
        ),
        OdooDropdownTile(
          title: 'Timezone',
          subtitle: 'Your local timezone',
          icon: HugeIcons.strokeRoundedClock01,
          selectedValue: state.timezone,
          options: state.timezones,
          isLoading: state.isLanguageLoading,
          displayKey: 'name',
          valueKey: 'name',
          onChanged: (selectedName) {
            if (selectedName != null) {
              final selectedTz = state.timezones.firstWhere(
                (tz) => tz['name'] == selectedName,
                orElse: () => {},
              );
              if (selectedTz.isNotEmpty) {
                context.read<SettingsBloc>().add(
                  UpdateTimezoneEvent(
                    selectedName,
                    selectedTz['code'],
                    localLanguageCode!,
                  ),
                );
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildDataAndStorageSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SectionCard(
      title: 'Data & Storage',
      icon: HugeIcons.strokeRoundedDatabase,
      children: [
        ActionTile(
          title: 'Clear Cache',
          subtitle: '',
          icon: Icons.delete_sweep_outlined,
          trailing: FutureBuilder<int>(
            future: _getCacheSize(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Text(
                  'Calculating...',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                );
              }
              final sizeInMB =
                  (snapshot.data! / (1024 * 1024)).toStringAsFixed(2);
              return Text(
                sizeInMB == '0.00' ? 'No cache' : '$sizeInMB MB',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
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
    );
  }

  Widget _buildHelpAndSupportSection(BuildContext context) {
    return SectionCard(
      title: 'Help & Support',
      icon: HugeIcons.strokeRoundedCustomerSupport,
      children: [
        ActionTile(
          title: 'Odoo Help Center',
          subtitle: 'Documentation, guides and resources',
          icon: HugeIcons.strokeRoundedHelpCircle,
          onTap: () => _launchUrlSmart(
            'https://www.odoo.com/documentation',
            title: 'Odoo Help Center',
          ),
        ),
        ActionTile(
          title: 'Odoo Support',
          subtitle: 'Create a ticket with Odoo Support',
          icon: HugeIcons.strokeRoundedCustomerSupport,
          onTap: () => _launchUrlSmart(
            'https://www.odoo.com/help',
            title: 'Odoo Support',
          ),
        ),
        ActionTile(
          title: 'Odoo Community Forum',
          subtitle: 'Ask the community for help',
          icon: HugeIcons.strokeRoundedUserGroup,
          onTap: () => _launchUrlSmart(
            'https://www.odoo.com/forum/help-1',
            title: 'Odoo Forum',
          ),
        ),
      ],
    );
  }

  Widget _buildAboutSection(BuildContext context, bool isDark) {
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return SectionCard(
      title: 'About',
      icon: HugeIcons.strokeRoundedBuilding06,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ActionTile(
                title: 'Visit Website',
                subtitle: 'www.cybrosys.com',
                icon: HugeIcons.strokeRoundedGlobe02,
                onTap: () => _launchUrlSmart(
                  'https://www.cybrosys.com/',
                  title: 'Our Website',
                ),
              ),
              ActionTile(
                title: 'Contact Us',
                subtitle: 'info@cybrosys.com',
                icon: HugeIcons.strokeRoundedMail01,
                onTap: () => _launchUrlSmart('mailto:info@cybrosys.com'),
              ),
              if (Theme.of(context).platform == TargetPlatform.android)
                ActionTile(
                  title: 'More Apps',
                  subtitle: 'View our other apps on Play Store',
                  icon: HugeIcons.strokeRoundedPlayStore,
                  onTap: () => _launchUrlSmart(
                    'https://play.google.com/store/apps/developer?id=Cybrosys',
                    title: 'Play Store',
                  ),
                ),
              if (Theme.of(context).platform == TargetPlatform.iOS)
                ActionTile(
                  title: 'More Apps',
                  subtitle: 'View our other apps on App Store',
                  icon: HugeIcons.strokeRoundedAppStore,
                  onTap: () => _launchUrlSmart(
                    'https://apps.apple.com/in/developer/cybrosys-technologies/id1805306445',
                    title: 'App Store',
                  ),
                ),
              const SizedBox(height: 16),
              Divider(color: isDark ? Colors.grey[800] : Colors.grey[200]),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Follow Us',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSocialButton(
                    context,
                    'assets/icons/facebook.png',
                    const Color(0xFF1877F2),
                    'Facebook',
                    () => _launchUrlSmart(
                      'https://www.facebook.com/cybrosystechnologies',
                      title: 'Facebook',
                    ),
                  ),
                  _buildSocialButton(
                    context,
                    'assets/icons/linkedin.png',
                    const Color(0xFF0077B5),
                    'LinkedIn',
                    () => _launchUrlSmart(
                      'https://www.linkedin.com/company/cybrosys/',
                      title: 'LinkedIn',
                    ),
                  ),
                  _buildSocialButton(
                    context,
                    'assets/icons/instagram.png',
                    const Color(0xFFE4405F),
                    'Instagram',
                    () => _launchUrlSmart(
                      'https://www.instagram.com/cybrosystech/',
                      title: 'Instagram',
                    ),
                  ),
                  _buildSocialButton(
                    context,
                    'assets/icons/youtube.png',
                    const Color(0xFFFF0000),
                    'YouTube',
                    () => _launchUrlSmart(
                      'https://www.youtube.com/channel/UCKjWLm7iCyOYINVspCSanjg',
                      title: 'YouTube',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  '© ${DateTime.now().year} Cybrosys Technologies',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSocialButton(
    BuildContext context,
    String imagePath,
    Color underlineColor,
    String label,
    VoidCallback onPressed,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 46,
            height: 46,
            padding: const EdgeInsets.all(12),
            child: Image.asset(
              imagePath,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 8),
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

  Future<void> _launchUrlSmart(String url, {String? title}) async {
    final uri = Uri.parse(url);
    try {
      if (uri.scheme == 'mailto') {
        if (await canLaunchUrl(uri)) {
          final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (ok) return;
        }
        final fallback = Uri.parse('https://www.cybrosys.com/contact/');
        final fbOk = await launchUrl(
          fallback,
          mode: LaunchMode.externalApplication,
        );
        if (!fbOk) {
          final webOk = await launchUrl(
            fallback,
            mode: LaunchMode.inAppBrowserView,
          );
          if (!webOk && mounted) {
            CustomSnackbar.showError(context, 'Could not open contact page.');
          }
        }
        return;
      }

      if (uri.scheme == 'http' || uri.scheme == 'https') {
        bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok) {
          ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
        }
        if (!ok && mounted) {
          CustomSnackbar.showError(context, 'Could not open link.');
        }
        return;
      }

      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        CustomSnackbar.showError(context, 'No app available to open this link.');
      }
    } catch (e) {
      if (!mounted) return;
      CustomSnackbar.showError(context, 'Could not open link. ${e.toString()}');
    }
  }

  Future<int> _getCacheSize() async {
    Directory cacheDir = await getTemporaryDirectory();
    return _getTotalSizeOfFilesInDir(cacheDir);
  }

  Future<int> _getTotalSizeOfFilesInDir(final FileSystemEntity file) async {
    if (file is File) return await file.length();
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
