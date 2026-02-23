import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:odoo_delivery_app/Dashboard/screens/profile/pages/profile_loading_shimmer.dart';
import 'package:odoo_delivery_app/shared/widgets/snackbar.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/company/session/company_session_manager.dart';
import '../../../services/encryption_service.dart';
import '../../../services/odoo_dashboard_service.dart';
import '../../../services/storage_service.dart';
import '../../../widgets/profile/profile_form.dart';
import '../../../widgets/profile/profile_image.dart';
import '../bloc/profile_bloc.dart';
import '../bloc/profile_event.dart';
import '../bloc/profile_state.dart';

/// Screen for viewing and editing the current user's profile information.
///
/// Features:
///   • Displays profile fields: name, email, phone, mobile, company, website, job title, map token
///   • Profile picture upload/change support
///   • Edit mode toggle (only visible to admins / system users)
///   • Offline detection (disables edit when offline)
///   • Encrypted map token storage per company
///   • Version-aware field handling (mobile vs mobile_phone in Odoo <18 vs ≥18)
class ProfileSettingsPage extends StatefulWidget {
  /// Optional callback to refresh profile data in parent screen
  /// (usually the dashboard's profile avatar / name)
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
  String? profileImagePath;
  bool isOnline = true;

  bool _isEdited = false;

  // Form controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _mobileController = TextEditingController();
  final _companyController = TextEditingController();
  final _websiteController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _mapTokenController = TextEditingController();
  late OdooDashboardService odooService;
  late EncryptionService encryptionService;
  late DashboardStorageService storageService;
  bool isAdmin = false;

  @override
  void initState() {
    super.initState();
    canManageSkills();
    encryptionService = EncryptionService();
    storageService = DashboardStorageService();
    _initAll();
  }

  /// Extracts major version number from Odoo server version string
  /// (e.g. "18.0" → 18, "16.0+e" → 16)
  int parseMajorVersion(String serverVersion) {
    final match = RegExp(r'\d+').firstMatch(serverVersion);
    if (match != null) {
      return int.tryParse(match.group(0)!) ?? 0;
    }
    return 0;
  }

  /// Determines if current user is system administrator (base.group_system)
  Future<void> canManageSkills() async {
    final prefs = await SharedPreferences.getInstance();
    final String version = prefs.getString('serverVersion') ?? '0';
    final int userId = prefs.getInt('userId') ?? 0;
    final int majorVersion = parseMajorVersion(version);

    Future<bool> hasGroup(String groupExtId) async {
      if (majorVersion >= 18) {
        return await CompanySessionManager.callKwWithCompany({
              'model': 'res.users',
              'method': 'has_group',
              'args': [userId, groupExtId],
              'kwargs': {},
            }) ==
            true;
      } else {
        return await CompanySessionManager.callKwWithCompany({
              'model': 'res.users',
              'method': 'has_group',
              'args': [groupExtId],
              'kwargs': {},
            }) ==
            true;
      }
    }

    final admin = await hasGroup('base.group_system');

    setState(() {
      isAdmin = admin;
    });
  }

  Future<void> _initAll() async {
    await _initBloc();
    await _initializeServices();
  }

  Future<void> _initializeServices() async {
    isOnline = await odooService.checkNetworkConnectivity();
    setState(() {});
  }

  /// Initializes ProfileBloc + Odoo service with current session
  Future<void> _initBloc() async {
    final storageService = DashboardStorageService();
    final encryptionService = EncryptionService();

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

    setState(() {
      _profileBloc = ProfileBloc(
        odooService: odooService,
        storageService: storageService,
        encryptionService: encryptionService,
      );
    });

    _profileBloc!.add(LoadProfile());
    await _loadCompanyData();
  }

  /// Loads company-specific map token (encrypted) and decrypts it
  Future<void> _loadCompanyData() async {
    final companyDetails = await odooService.getCompanyDetails(companyId ?? 1);
    if (companyDetails != null &&
        companyDetails['x_map_key_encrypted'] != null) {
      final decryptedKey = encryptionService.decryptText(
        companyDetails['x_map_key_encrypted'] as String,
      );
      setState(() {
        _mapTokenController.text = decryptedKey;
      });
    }
  }

  @override
  void dispose() {
    _profileBloc!.close();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _mobileController.dispose();
    _companyController.dispose();
    _websiteController.dispose();
    _jobTitleController.dispose();
    _mapTokenController.dispose();
    super.dispose();
  }

  void _toggleEdit() {
    setState(() {
      _isEdited = !_isEdited;
    });
  }

  /// Saves profile changes + map token (if changed)
  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    int version = prefs.getInt('version') ?? 0;
    final updateData = {
      'name': _nameController.text,
      'email': _emailController.text,
      'phone': _phoneController.text,
      if (version < 18) 'mobile': _mobileController.text.trim(),
      if (version >= 18) 'mobile_phone': _mobileController.text.trim(),
      if (profileImagePath != null) 'image_1920': profileImagePath,
    };
    _profileBloc!.add(UpdateProfile(updateData));
    final tokenText = _mapTokenController.text.trim();
    if (tokenText.isEmpty) {
      setState(() {
        _isEdited = false;
      });
      return;
    }
    final encryptedToken = encryptionService.encryptText(tokenText);
    await odooService.createMapKeyField(companyId ?? 1, encryptedToken);
    await storageService.saveMapToken(_mapTokenController.text.trim());
    setState(() => _isEdited = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Show shimmer until bloc is ready
    if (_profileBloc == null) {
      return const Scaffold(body: Center(child: ProfileShimmer()));
    }

    return BlocProvider.value(
      value: _profileBloc!,
      child: Scaffold(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        appBar: AppBar(
          backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
          title: Text(
            "Profile Details",
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
            onPressed: () {
              Navigator.of(context).pop();
              if (widget.refreshProfile != null) widget.refreshProfile!();
            },
          ),
          actions: [
            if (isAdmin) ...[
              if (isOnline) ...[
                if (!_isEdited)
                  TextButton(
                    onPressed: _toggleEdit,
                    child: Text(
                      "Edit",
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                  )
                else
                  Row(
                    children: [
                      TextButton(
                        onPressed: _toggleEdit,
                        child: Text(
                          "Cancel",
                          style: TextStyle(
                            color: isDark
                                ? Colors.grey[400]!
                                : Colors.grey[600]!,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _saveProfile,
                        child: Text(
                          "Save",
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
              ] else ...[
                TextButton(
                  onPressed: () {
                    CustomSnackbar.showError(
                      context,
                      'Cannot edit while offline. Please try again later.',
                    );
                  },
                  child: Text(
                    "Edit",
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
        body: BlocBuilder<ProfileBloc, ProfileState>(
          builder: (context, state) {
            if (state is ProfileLoading) {
              return const Center(child: ProfileShimmer());
            } else if (state is ProfileError) {
              return Center(child: Text(state.message));
            } else if (state is ProfileLoaded) {
              final profile = state.profile;

              // Fill form fields once when profile loads
              _nameController.text = profile.name ?? '';
              _emailController.text = profile.email ?? '';
              _phoneController.text = profile.phone ?? '';
              _mobileController.text = profile.mobile ?? '';
              _companyController.text = profile.company ?? '';
              _websiteController.text = profile.website ?? '';
              _jobTitleController.text = profile.jobTitle ?? '';

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    ProfileImage(
                      imagePath: profile.profileImage,
                      isEdited: _isEdited,
                      onImageChanged: (base64Image) {
                        setState(() {
                          profileImagePath = base64Image;
                        });
                        _profileBloc!.add(PickProfileImage(base64Image));
                      },
                    ),
                    const SizedBox(height: 16),
                    ProfileForm(
                      nameController: _nameController,
                      emailController: _emailController,
                      phoneController: _phoneController,
                      companyController: _companyController,
                      mobileController: _mobileController,
                      websiteController: _websiteController,
                      jobTitleController: _jobTitleController,
                      mapTokenController: _mapTokenController,
                      isSystem: isSystem ?? false,
                      isEdited: _isEdited,
                      onSave: _saveProfile,
                      onChanged: (value) {},
                      isOnline: true,
                    ),
                  ],
                ),
              );
            } else {
              return const SizedBox.shrink();
            }
          },
        ),
      ),
    );
  }
}
