import '../../../../core/navigation/data_loss_warning_dialog.dart';
import '../../../../shared/widgets/snackbar.dart';
import '../../../../shared/widgets/loaders/loading_widget.dart';
import '../../../../shared/widgets/odoo_avatar.dart';
import '../../../../shared/widgets/forms/custom_dropdown_field.dart';
import '../../../../shared/widgets/forms/custom_text_field.dart';
import '../../../../core/company/session/company_session_manager.dart';
import 'package:image_picker/image_picker.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import '../../../services/storage_service.dart';
import '../../../services/encryption_service.dart';
import '../../../../NavBars/MapBox/services/odoo_map_service.dart';

/// Profile detail/edit screen — self-contained, matches mobo_inv_app's UI exactly.
///
/// Fetches data directly via CompanySessionManager (no external bloc).
/// Pattern: res.users.read for user fields, res.partner.read for partner fields.
class ProfileDetailScreen extends StatefulWidget {
  const ProfileDetailScreen({super.key});

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  bool _isLoading = true;
  bool _isEditMode = false;
  bool _isSaving = false;
  bool _isShowingLoadingDialog = false;
  bool _saveSuccess = false;
  String? _pickedImageBase64;

  Map<String, dynamic>? _userData;
  int? _partnerId;

  int? _relatedCompanyId;
  String? _relatedCompanyName;

  List<Map<String, dynamic>> _countries = [];
  List<Map<String, dynamic>> _states = [];
  bool _isLoadingCountries = false;
  bool _isLoadingStates = false;

  String _loadedMapToken = '';

  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _mobileController = TextEditingController();
  final _websiteController = TextEditingController();
  final _functionController = TextEditingController();
  final _mapTokenController = TextEditingController();

  double _rs(BuildContext context, double size) {
    final w = MediaQuery.of(context).size.width;
    final scale = (w / 390.0).clamp(0.85, 1.2);
    return size * scale;
  }

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
    _loadCountries();
    _loadMapToken();
  }

  Future<void> _loadMapToken() async {
    // Show locally cached token immediately for responsiveness.
    // _fetchUserProfile() will overwrite with the latest server value once it completes.
    final sessionData = await DashboardStorageService().getSessionData();
    if (mounted) {
      setState(() {
        _loadedMapToken = sessionData['mapToken']?.toString() ?? '';
        _mapTokenController.text = _loadedMapToken;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _mobileController.dispose();
    _websiteController.dispose();
    _functionController.dispose();
    _mapTokenController.dispose();
    super.dispose();
  }

  // ─── Data helpers ───

  String _normalizeForEdit(dynamic value) {
    if (value == null) return '';
    if (value is bool) return value ? 'true' : '';
    final s = value.toString().trim();
    if (s.isEmpty) return '';
    if (s.toLowerCase() == 'false') return '';
    return s;
  }

  String? get _userAvatarBase64 {
    final v = _userData?['image_1920'];
    if (v is String && v.isNotEmpty && v != 'false') return v;
    return null;
  }

  void _updateControllers() {
    if (_userData == null) return;
    _nameController.text = _normalizeForEdit(_userData!['name']);
    _emailController.text = _normalizeForEdit(_userData!['email']);
    _phoneController.text = _normalizeForEdit(_userData!['phone']);
    _mobileController.text = _normalizeForEdit(_userData!['mobile']);
    _websiteController.text = _normalizeForEdit(_userData!['website']);
    _functionController.text = _normalizeForEdit(_userData!['function']);
    _mapTokenController.text = _loadedMapToken;
  }

  String formatAddress(Map<String, dynamic> data) {
    final parts = <String>[];
    for (final key in ['street', 'street2', 'city']) {
      final v = _normalizeForEdit(data[key]);
      if (v.isNotEmpty) parts.add(v);
    }
    if (data['state_id'] is List && (data['state_id'] as List).length > 1) {
      final s = _normalizeForEdit(data['state_id'][1]);
      if (s.isNotEmpty) parts.add(s);
    }
    final zip = _normalizeForEdit(data['zip']);
    if (zip.isNotEmpty) parts.add(zip);
    if (data['country_id'] is List && (data['country_id'] as List).length > 1) {
      final c = _normalizeForEdit(data['country_id'][1]);
      if (c.isNotEmpty) parts.add(c);
    }
    return parts.join(', ');
  }

  // ─── Fetch profile ───

  Future<void> _fetchUserProfile({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() => _isLoading = _userData == null);

    try {
      final session = await CompanySessionManager.getCurrentSession();
      if (session == null || session.userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final res = await CompanySessionManager.callKwWithCompany({
        'model': 'res.users',
        'method': 'read',
        'args': [
          [session.userId],
          ['name', 'email', 'image_1920', 'company_id', 'partner_id', 'website', 'function'],
        ],
        'kwargs': {},
      });

      if (res is List && res.isNotEmpty) {
        final data = res.first as Map<String, dynamic>;

        final partner = data['partner_id'];
        if (partner is List && partner.isNotEmpty) {
          _partnerId = partner[0] as int?;
          try {
            final partnerRes = await CompanySessionManager.callKwWithCompany({
              'model': 'res.partner',
              'method': 'read',
              'args': [
                [partner[0]],
                ['phone', 'mobile', 'street', 'street2', 'city', 'zip', 'state_id', 'country_id', 'parent_id'],
              ],
              'kwargs': {},
            });
            if (partnerRes is List && partnerRes.isNotEmpty) {
              final pd = partnerRes.first as Map<String, dynamic>;
              data['phone'] = pd['phone'];
              data['mobile'] = pd['mobile'];
              data['street'] = pd['street'];
              data['street2'] = pd['street2'];
              data['city'] = pd['city'];
              data['zip'] = pd['zip'];
              data['state_id'] = pd['state_id'];
              data['country_id'] = pd['country_id'];
              data['parent_id'] = pd['parent_id'];
            }
          } catch (_) {}
        }

        try {
          final odooMapService = OdooMapService();
          final serverMapToken = await odooMapService.getMapToken();
          if (serverMapToken.isNotEmpty) {
            await DashboardStorageService().saveMapToken(serverMapToken);
            _loadedMapToken = serverMapToken;
            _mapTokenController.text = _isEditMode ? _loadedMapToken : '••••••••••••••••';
          }
        } catch (_) {
          // Map key not configured yet — expected on first run, ignore silently
        }

        if (mounted) {
          setState(() {
            _userData = data;
            _isLoading = false;
          });
          _updateControllers();
          _loadRelatedCompanyFromData(data);
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (e is OdooSessionExpiredException && mounted) {
        CompanySessionManager.logout(context);
        return;
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _loadRelatedCompanyFromData(Map<String, dynamic> data) {
    final parentId = data['parent_id'];
    if (parentId is List && parentId.length > 1) {
      setState(() {
        _relatedCompanyId = parentId[0] as int?;
        _relatedCompanyName = parentId[1]?.toString();
      });
    }
  }

  // ─── Countries / States ───

  Future<void> _loadCountries() async {
    setState(() => _isLoadingCountries = true);
    try {
      final res = await CompanySessionManager.callKwWithCompany({
        'model': 'res.country',
        'method': 'search_read',
        'args': [[]],
        'kwargs': {'fields': ['id', 'name'], 'order': 'name asc'},
      });
      if (res is List && mounted) {
        setState(() {
          _countries = res.cast<Map<String, dynamic>>();
          _isLoadingCountries = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingCountries = false);
    }
  }

  Future<void> _loadStates(int countryId) async {
    setState(() => _isLoadingStates = true);
    try {
      final res = await CompanySessionManager.callKwWithCompany({
        'model': 'res.country.state',
        'method': 'search_read',
        'args': [[['country_id', '=', countryId]]],
        'kwargs': {'fields': ['id', 'name'], 'order': 'name asc'},
      });
      if (res is List && mounted) {
        setState(() {
          _states = res.cast<Map<String, dynamic>>();
          _isLoadingStates = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingStates = false);
    }
  }

  // ─── Loading dialog ───

  void _showLoadingDialog(BuildContext context, String message) {
    if (_isShowingLoadingDialog || !mounted) return;
    _isShowingLoadingDialog = true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: isDark ? const Color(0xFF212121) : Colors.white,
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: LoadingWidget(size: 32, variant: LoadingVariant.staggeredDots),
              ),
              const SizedBox(height: 16),
              Text(message,
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.grey[900],
                      )),
              const SizedBox(height: 8),
              Text(
                'Please wait while we process your request',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Save ───

  Future<void> _saveAllChanges() async {
    if (!_formKey.currentState!.validate()) {
      CustomSnackbar.showError(context, 'Please fix the validation errors before saving');
      return;
    }

    setState(() => _isSaving = true);
    _showLoadingDialog(context, 'Saving Changes');

    bool isSuccess = false;
    try {
      final session = await CompanySessionManager.getCurrentSession();
      if (session == null) throw Exception('No session');

      final userUpdates = <String, dynamic>{};
      final partnerUpdates = <String, dynamic>{};

      if (_nameController.text.trim() != _normalizeForEdit(_userData?['name'])) {
        userUpdates['name'] = _nameController.text.trim();
      }
      if (_emailController.text.trim() != _normalizeForEdit(_userData?['email'])) {
        userUpdates['email'] = _emailController.text.trim();
      }
      if (_phoneController.text.trim() != _normalizeForEdit(_userData?['phone'])) {
        partnerUpdates['phone'] = _phoneController.text.trim();
      }
      if (_mobileController.text.trim() != _normalizeForEdit(_userData?['mobile'])) {
        partnerUpdates['mobile'] = _mobileController.text.trim();
      }
      if (_websiteController.text.trim() != _normalizeForEdit(_userData?['website'])) {
        partnerUpdates['website'] = _websiteController.text.trim();
      }
      if (_functionController.text.trim() != _normalizeForEdit(_userData?['function'])) {
        partnerUpdates['function'] = _functionController.text.trim();
      }
      if (_pickedImageBase64 != null) {
        userUpdates['image_1920'] = _pickedImageBase64;
      }

      if (_mapTokenController.text.trim() != _loadedMapToken) {
        final newMapToken = _mapTokenController.text.trim();
        final encryptionService = EncryptionService();
        final encryptedToken = encryptionService.encryptText(newMapToken);
        final companyId = session.companyId ?? 1;
        
        try {
          final modelResult = await CompanySessionManager.callKwWithCompany({
            'model': 'ir.model',
            'method': 'search_read',
            'args': [[['model', '=', 'res.company']]],
            'kwargs': {},
          });

          if (modelResult != null && modelResult.isNotEmpty) {
            final int modelIdInt = int.parse(modelResult[0]['id'].toString());
            final existingField = await CompanySessionManager.callKwWithCompany({
              'model': 'ir.model.fields',
              'method': 'search_read',
              'args': [[['model', '=', 'res.company'], ['name', '=', 'x_map_key_encrypted']]],
              'kwargs': {},
            });

            if (existingField == null || existingField.isEmpty) {
              await CompanySessionManager.callKwWithCompany({
                'model': 'ir.model.fields',
                'method': 'create',
                'args': [{
                  'name': 'x_map_key_encrypted',
                  'field_description': 'Google Map API Key',
                  'ttype': 'char',
                  'copied': false,
                  'model': 'res.company',
                  'model_id': modelIdInt,
                }],
                'kwargs': {},
              });
            }
          }

          await CompanySessionManager.callKwWithCompany({
            'model': 'res.company',
            'method': 'write',
            'args': [[companyId], {'x_map_key_encrypted': encryptedToken}],
            'kwargs': {},
          });
        } catch (_) {
          // Non-fatal: server write failed; key is still saved locally.
        }

        await DashboardStorageService().saveMapToken(newMapToken);
        _loadedMapToken = newMapToken;
        // Clear the map service token cache so the next map session fetches the new key
        OdooMapService().clearTokenCache();
      }

      if (userUpdates.isNotEmpty) {
        await CompanySessionManager.callKwWithCompany({
          'model': 'res.users',
          'method': 'write',
          'args': [[session.userId], userUpdates],
          'kwargs': {},
        });
      }
      if (partnerUpdates.isNotEmpty && _partnerId != null) {
        await CompanySessionManager.callKwWithCompany({
          'model': 'res.partner',
          'method': 'write',
          'args': [[_partnerId], partnerUpdates],
          'kwargs': {},
        });
      }

      isSuccess = true;
      _saveSuccess = true;
      _pickedImageBase64 = null;
      setState(() => _isEditMode = false);
      await _fetchUserProfile(forceRefresh: true);
    } catch (e) {
      isSuccess = false;
    } finally {
      setState(() => _isSaving = false);
    }
    if (!mounted) return;
    if (_isShowingLoadingDialog) {
      _isShowingLoadingDialog = false;
      Navigator.of(context).pop();
    }
    if (isSuccess) {
      CustomSnackbar.show(context: context, title: 'Success', message: 'Profile updated successfully', type: SnackbarType.success);
    } else {
      CustomSnackbar.showError(context, 'Failed to save changes');
    }
  }

  // ─── Image ───

  Future<void> _pickImageFromSource(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 80, maxWidth: 600);
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _pickedImageBase64 = base64Encode(bytes));
      await _saveImage();
    } catch (e) {
      if (mounted) CustomSnackbar.showError(context, 'Failed to pick image: $e');
    }
  }

  Future<void> _saveImage() async {
    if (_pickedImageBase64 == null || !mounted) return;
    final navigator = Navigator.of(context);
    _showLoadingDialog(context, 'Saving Image');
    try {
      final session = await CompanySessionManager.getCurrentSession();
      if (session != null) {
        await CompanySessionManager.callKwWithCompany({
          'model': 'res.users',
          'method': 'write',
          'args': [[session.userId], {'image_1920': _pickedImageBase64}],
          'kwargs': {},
        });
      }
      await _fetchUserProfile(forceRefresh: true);
      if (mounted) CustomSnackbar.show(context: context, title: 'Success', message: 'Image updated successfully', type: SnackbarType.success);
    } catch (e) {
      if (mounted) CustomSnackbar.showError(context, 'Failed to update image: $e');
    } finally {
      _isShowingLoadingDialog = false;
    }
    if (mounted && navigator.canPop()) navigator.pop();
  }

  void _showImageSourceActionSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[700] : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          InkWell(
            onTap: () { Navigator.pop(ctx); _pickImageFromSource(ImageSource.camera); },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                HugeIcon(icon: HugeIcons.strokeRoundedCamera02, size: 24, color: isDark ? Colors.white : Colors.black87),
                const SizedBox(width: 16),
                const Text('Take Photo', style: TextStyle(fontSize: 16)),
              ]),
            ),
          ),
          Divider(height: 1, thickness: 1, color: isDark ? Colors.grey[800] : Colors.grey[200]),
          InkWell(
            onTap: () { Navigator.pop(ctx); _pickImageFromSource(ImageSource.gallery); },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                HugeIcon(icon: HugeIcons.strokeRoundedImageCrop, size: 24, color: isDark ? Colors.white : Colors.black87),
                const SizedBox(width: 16),
                const Text('Choose from Gallery', style: TextStyle(fontSize: 16)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ─── Navigation ───

  void _cancelEdit() {
    _updateControllers();
    setState(() => _isEditMode = false);
  }

  bool _hasUnsavedChanges() {
    if (_userData == null) return false;
    return _nameController.text.trim() != _normalizeForEdit(_userData!['name']) ||
        _emailController.text.trim() != _normalizeForEdit(_userData!['email']) ||
        _phoneController.text.trim() != _normalizeForEdit(_userData!['phone']) ||
        _mobileController.text.trim() != _normalizeForEdit(_userData!['mobile']) ||
        _websiteController.text.trim() != _normalizeForEdit(_userData!['website']) ||
        _functionController.text.trim() != _normalizeForEdit(_userData!['function']) ||
        _mapTokenController.text.trim() != _loadedMapToken ||
        _pickedImageBase64 != null;
  }

  Future<void> _handleBack() async {
    if (_isEditMode && _hasUnsavedChanges()) {
      final result = await DataLossWarningDialog.show(
        context: context,
        title: 'Discard Changes?',
        message: 'You have unsaved changes that will be lost if you leave this page. Are you sure you want to discard these changes?',
        confirmText: 'Discard',
        cancelText: 'Keep Editing',
      );
      if ((result ?? false) && mounted) Navigator.of(context).pop(_saveSuccess);
      return;
    }
    if (mounted) Navigator.of(context).pop(_saveSuccess);
  }

  // ─── Address dialog ───

  void _showEditAddressDialog() {
    if (_userData == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    final streetCtrl = TextEditingController(text: _normalizeForEdit(_userData!['street']));
    final street2Ctrl = TextEditingController(text: _normalizeForEdit(_userData!['street2']));
    final cityCtrl = TextEditingController(text: _normalizeForEdit(_userData!['city']));
    final zipCtrl = TextEditingController(text: _normalizeForEdit(_userData!['zip']));

    int? selectedCountryId = (_userData!['country_id'] is List && (_userData!['country_id'] as List).isNotEmpty)
        ? _userData!['country_id'][0] as int? : null;
    int? selectedStateId = (_userData!['state_id'] is List && (_userData!['state_id'] as List).isNotEmpty)
        ? _userData!['state_id'][0] as int? : null;

    if (selectedCountryId != null && _states.isEmpty && !_isLoadingStates) {
      _loadStates(selectedCountryId);
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final validCountryIds = _countries.map((c) => c['id']).toSet();
          final safeCountryId = selectedCountryId != null && validCountryIds.contains(selectedCountryId) ? selectedCountryId : null;
          final validStateIds = _states.map((s) => s['id']).toSet();
          final safeStateId = selectedStateId != null && validStateIds.contains(selectedStateId) ? selectedStateId : null;

          final countryItems = _isLoadingCountries
              ? [const DropdownMenuItem<String>(value: null, child: Text('Loading...'))]
              : [
                  const DropdownMenuItem<String>(value: null, child: Text('Select Country', style: TextStyle(fontStyle: FontStyle.italic))),
                  ..._countries.map((c) => DropdownMenuItem<String>(value: c['id'].toString(), child: Text(c['name']))),
                ];

          final stateEnabled = safeCountryId != null;
          final stateItems = !stateEnabled
              ? [const DropdownMenuItem<String>(value: null, child: Text('Select country first', style: TextStyle(fontStyle: FontStyle.italic)))]
              : _isLoadingStates
                  ? [const DropdownMenuItem<String>(value: null, child: Text('Loading...'))]
                  : [
                      const DropdownMenuItem<String>(value: null, child: Text('Select State/Province', style: TextStyle(fontStyle: FontStyle.italic))),
                      ..._states.map((s) => DropdownMenuItem<String>(value: s['id'].toString(), child: Text(s['name']))),
                    ];

          return AlertDialog(
            backgroundColor: isDark ? Colors.grey[850] : Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Edit Address',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600)),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomTextField(
                      controller: streetCtrl, labelText: 'Street Address',
                      hintText: 'Enter street address', isDark: isDark,
                      validator: (value) => value == null || value.trim().isEmpty ? 'This field is required' : null,
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(controller: street2Ctrl, labelText: 'Street Address 2',
                      hintText: 'Apartment, suite, etc. (optional)', isDark: isDark),
                    const SizedBox(height: 16),
                    CustomTextField(controller: cityCtrl, labelText: 'City', hintText: 'Enter city', isDark: isDark),
                    const SizedBox(height: 16),
                    CustomTextField(controller: zipCtrl, labelText: 'ZIP Code', hintText: 'Enter ZIP code',
                      isDark: isDark, keyboardType: TextInputType.number),
                    const SizedBox(height: 16),
                    CustomDropdownField(
                      value: safeCountryId?.toString(),
                      labelText: 'Country', hintText: 'Select Country', isDark: isDark,
                      items: countryItems,
                      onChanged: _isLoadingCountries ? null : (val) {
                        setDlg(() { selectedCountryId = val != null ? int.tryParse(val) : null; selectedStateId = null; _states = []; });
                        if (selectedCountryId != null) {
                          _loadStates(selectedCountryId!).then((_) { if (ctx.mounted) setDlg(() {}); });
                        }
                      },
                      validator: (value) => value == null ? 'Please select a country' : null,
                    ),
                    const SizedBox(height: 16),
                    CustomDropdownField(
                      value: safeStateId?.toString(),
                      labelText: 'State/Province',
                      hintText: stateEnabled ? (_isLoadingStates ? 'Loading...' : 'Select State/Province') : 'Select country first',
                      isDark: isDark,
                      items: stateItems,
                      onChanged: (!stateEnabled || _isLoadingStates) ? null : (val) {
                        setDlg(() => selectedStateId = val != null ? int.tryParse(val) : null);
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  streetCtrl.dispose(); street2Ctrl.dispose(); cityCtrl.dispose(); zipCtrl.dispose();
                },
                style: TextButton.styleFrom(
                  foregroundColor: isDark ? Colors.grey[400] : Colors.grey[700],
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w500)),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (streetCtrl.text.trim().isEmpty) {
                    CustomSnackbar.showError(ctx, 'Street address is required');
                    return;
                  }
                  final addressData = {
                    'street': streetCtrl.text.trim(),
                    'street2': street2Ctrl.text.trim().isEmpty ? false : street2Ctrl.text.trim(),
                    'city': cityCtrl.text.trim().isEmpty ? false : cityCtrl.text.trim(),
                    'zip': zipCtrl.text.trim().isEmpty ? false : zipCtrl.text.trim(),
                    'country_id': selectedCountryId ?? false,
                    'state_id': selectedStateId ?? false,
                  };
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  streetCtrl.dispose(); street2Ctrl.dispose(); cityCtrl.dispose(); zipCtrl.dispose();
                  _showLoadingDialog(context, 'Updating Address');
                  try {
                    if (_partnerId != null) {
                      await CompanySessionManager.callKwWithCompany({
                        'model': 'res.partner', 'method': 'write',
                        'args': [[_partnerId], addressData], 'kwargs': {},
                      });
                    }
                    await _fetchUserProfile(forceRefresh: true);
                    if (mounted) {
                      _isShowingLoadingDialog = false;
                      navigator.pop();
                      CustomSnackbar.show(context: context, title: 'Success', message: 'Address updated successfully', type: SnackbarType.success);
                    }
                  } catch (e) {
                    if (mounted) {
                      _isShowingLoadingDialog = false;
                      navigator.pop();
                      CustomSnackbar.showError(context, 'Failed to update address: $e');
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor, foregroundColor: Colors.white, elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w500)),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Related Company picker ───

  Future<void> _showRelatedCompanyPicker() async {
    if (_userData == null) return;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final TextEditingController searchCtrl = TextEditingController();
    List<Map<String, dynamic>> companies = [];
    bool loading = true;

    Future<void> loadCompanies([String q = '']) async {
      try {
        final domain = [['is_company', '=', true]];
        if (q.trim().isNotEmpty) domain.add(['name', 'ilike', q.trim()]);
        final res = await CompanySessionManager.callKwWithCompany({
          'model': 'res.partner',
          'method': 'search_read',
          'args': [domain],
          'kwargs': {'fields': ['id', 'name'], 'limit': 20, 'order': 'name asc'},
        });
        companies = (res as List).cast<Map<String, dynamic>>();
      } catch (e) {
        companies = [];
      } finally {
        loading = false;
      }
    }

    await loadCompanies();
    if (!mounted) return;

    final selected = await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: isDark ? Colors.grey[850] : Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text('Select Related Company',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search companies...',
                    isDense: true,
                  ),
                  onChanged: (val) async {
                    setDlg(() => loading = true);
                    await loadCompanies(val);
                    if (ctx.mounted) setDlg(() {});
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 320,
                  width: double.infinity,
                  child: loading
                      ? Center(child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(theme.primaryColor)))
                      : companies.isEmpty
                          ? Center(child: Text('No companies found', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])))
                          : ListView.separated(
                              itemCount: companies.length,
                              separatorBuilder: (_, __) => Divider(height: .01, thickness: .01, color: isDark ? Colors.grey[800] : Colors.grey[200]),
                              itemBuilder: (ctx, i) {
                                final c = companies[i];
                                final selected = c['id'] == _relatedCompanyId;
                                return ListTile(
                                  dense: true,
                                  title: Text(c['name'] ?? ''),
                                  trailing: selected ? Icon(Icons.check, color: theme.primaryColor, size: 18) : null,
                                  onTap: () => Navigator.of(ctx).pop(c),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || selected is! Map<String, dynamic>) return;

    try {
      _showLoadingDialog(context, 'Updating Related Company');
      if (_partnerId != null) {
        await CompanySessionManager.callKwWithCompany({
          'model': 'res.partner', 'method': 'write',
          'args': [[_partnerId], {'parent_id': selected['id']}], 'kwargs': {},
        });
      }
      if (!mounted) return;
      _isShowingLoadingDialog = false;
      Navigator.of(context).pop();
      setState(() {
        _relatedCompanyId = selected['id'] as int?;
        _relatedCompanyName = selected['name']?.toString();
      });
      CustomSnackbar.show(context: context, title: 'Success', message: 'Related Company updated', type: SnackbarType.success);
    } catch (e) {
      if (mounted) {
        _isShowingLoadingDialog = false;
        Navigator.of(context).pop();
        CustomSnackbar.showError(context, 'Failed to update related company: $e');
      }
    }
  }

  // ─── BUILD ───

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          forceMaterialTransparency: true,
          title: Text(
            'Profile Details',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
              fontSize: _rs(context, 18),
            ),
          ),
          leading: IconButton(
            onPressed: _handleBack,
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedArrowLeft01,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          actions: [
            if (_isEditMode)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: TextButton(
                  onPressed: _isSaving ? null : _cancelEdit,
                  child: Text('Cancel',
                      style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: 0.2,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      )),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 4.0),
              child: TextButton(
                onPressed: _isSaving
                    ? null
                    : () {
                        if (_isEditMode) {
                          _saveAllChanges();
                        } else {
                          setState(() => _isEditMode = true);
                        }
                      },
                child: Text(
                  _isEditMode ? 'Save' : 'Edit',
                  style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2,
                    color: _isEditMode
                        ? (isDark ? Colors.white : Colors.black)
                        : isDark ? Colors.white : Theme.of(context).primaryColor,
                  ),
                ),
              ),
            ),
          ],
          backgroundColor: isDark ? Colors.grey[900]! : Colors.white,
          elevation: 0,
        ),
        backgroundColor: isDark ? Colors.grey[900]! : Colors.white,
        body: _isLoading && _userData == null
            ? Center(child: LoadingWidget(size: 40, variant: LoadingVariant.staggeredDots))
            : _userData == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.error_outline, size: 40, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text('Failed to load profile'),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _fetchUserProfile, child: const Text('Retry')),
                      ]),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _fetchUserProfile(forceRefresh: true),
                    child: SingleChildScrollView(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildProfileImageSection(context, isDark),
                              const SizedBox(height: 32),
                              const Text('Personal Information',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 20),
                              _buildCustomTextField(context, 'Full Name', _userData!['name']?.toString(),
                                  HugeIcons.strokeRoundedUserAccount, controller: _nameController),
                              const SizedBox(height: 16),
                              _buildCustomTextField(context, 'Email', _userData!['email']?.toString(),
                                  HugeIcons.strokeRoundedMail01, controller: _emailController,
                                  keyboardType: TextInputType.emailAddress),
                              const SizedBox(height: 16),
                              _buildCustomTextField(context, 'Phone', _userData!['phone']?.toString(),
                                  HugeIcons.strokeRoundedCall02, controller: _phoneController,
                                  keyboardType: TextInputType.phone),
                              const SizedBox(height: 16),
                              _buildCustomTextField(context, 'Mobile', _userData!['mobile']?.toString(),
                                  HugeIcons.strokeRoundedSmartPhone01, controller: _mobileController,
                                  keyboardType: TextInputType.phone),
                              const SizedBox(height: 16),
                              _buildCustomTextField(context, 'Website', _userData!['website']?.toString(),
                                  HugeIcons.strokeRoundedWebDesign02, controller: _websiteController,
                                  keyboardType: TextInputType.url),
                              const SizedBox(height: 16),
                              _buildCustomTextField(context, 'Job Title', _userData!['function']?.toString(),
                                  HugeIcons.strokeRoundedWorkHistory, controller: _functionController),
                              const SizedBox(height: 16),
                              _buildCustomTextField(
                                context,
                                'Company',
                                _userData!['company_id'] is List && (_userData!['company_id'] as List).length > 1
                                    ? (_userData!['company_id'][1]?.toString() ?? '')
                                    : '',
                                HugeIcons.strokeRoundedBuilding05,
                                showNonEditableMessage: true,
                              ),
                              const SizedBox(height: 16),
                              _buildCustomTextField(
                                context,
                                'Related Company',
                                _relatedCompanyName ?? '',
                                HugeIcons.strokeRoundedBuilding01,
                                onEdit: _isEditMode ? _showRelatedCompanyPicker : null,
                              ),
                              const SizedBox(height: 16),
                              _buildCustomTextField(
                                context,
                                'Google Maps API Key',
                                _loadedMapToken.isNotEmpty ? (_isEditMode ? _loadedMapToken : '••••••••••••••••') : '',
                                Icons.map_outlined,
                                controller: _mapTokenController,
                              ),
                              const SizedBox(height: 20),
                              _buildCustomTextField(
                                context,
                                'Address',
                                formatAddress(_userData!),
                                HugeIcons.strokeRoundedLocation05,
                                onEdit: _isEditMode ? _showEditAddressDialog : null,
                              ),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }

  // ─── UI Helpers ───

  Widget _buildCustomTextField(
    BuildContext context,
    String labelText,
    String? value,
    dynamic icon, {
    VoidCallback? onEdit,
    TextEditingController? controller,
    TextInputType? keyboardType,
    bool showNonEditableMessage = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayValue =
        (value == null || value.trim().isEmpty || value.trim().toLowerCase() == 'false')
            ? 'Not set'
            : value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: TextStyle(
            fontFamily: GoogleFonts.manrope(fontWeight: FontWeight.w400).fontFamily,
            color: isDark ? Colors.white70 : const Color(0xff7F7F7F),
          ),
        ),
        const SizedBox(height: 8),
        _isEditMode && controller != null
            ? _buildEditableField(context, controller, keyboardType, labelText, isDark)
            : _buildDisplayField(context, displayValue, icon, isDark,
                onEdit: onEdit,
                labelText: labelText,
                showNonEditableMessage: showNonEditableMessage),
      ],
    );
  }

  Widget _buildDisplayField(
    BuildContext context,
    String displayValue,
    dynamic icon,
    bool isDark, {
    VoidCallback? onEdit,
    String? labelText,
    bool showNonEditableMessage = false,
  }) {
    return GestureDetector(
      onTap: onEdit ??
          (showNonEditableMessage && labelText != null
              ? () {
                  if (mounted) {
                    CustomSnackbar.showInfo(context, '$labelText cannot be modified from this screen');
                  }
                }
              : null),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isDark ? const Color(0xFF2A2A2A) : const Color(0xffF8FAFB),
          border: Border.all(color: Colors.transparent, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _buildIcon(icon, isDark ? Colors.white70 : Colors.black, 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  displayValue,
                  style: TextStyle(
                    fontFamily: GoogleFonts.manrope(fontWeight: FontWeight.w600).fontFamily,
                    color: displayValue == 'Not set'
                        ? Colors.grey[500]
                        : (isDark ? Colors.white70 : const Color(0xff000000)),
                    fontSize: 14,
                    height: 1.2,
                    letterSpacing: 0.0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditableField(
    BuildContext context,
    TextEditingController controller,
    TextInputType? keyboardType,
    String labelText,
    bool isDark,
  ) {
    return Focus(
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isDark ? const Color(0xFF2A2A2A) : const Color(0xffF8FAFB),
                  border: Border.all(
                    color: hasFocus ? Theme.of(context).primaryColor : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      _buildIcon(_getIconForField(labelText), isDark ? Colors.white70 : Colors.black, 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: controller,
                          keyboardType: keyboardType,
                          validator: _getValidatorForField(labelText),
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          style: TextStyle(
                            fontFamily: GoogleFonts.manrope(fontWeight: FontWeight.w600).fontFamily,
                            color: isDark ? Colors.white70 : const Color(0xff000000),
                            fontSize: 14,
                            height: 1.2,
                            letterSpacing: 0.0,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            hintText: controller.text.isEmpty ? 'Enter $labelText' : null,
                            hintStyle: TextStyle(
                              fontFamily: GoogleFonts.manrope(fontWeight: FontWeight.w600).fontFamily,
                              color: isDark ? Colors.grey[500] : Colors.grey[500],
                              fontStyle: FontStyle.italic,
                              fontSize: 14,
                              height: 1.2,
                              letterSpacing: 0.0,
                            ),
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            errorStyle: const TextStyle(height: 0, fontSize: 0),
                          ),
                          cursorColor: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_getValidatorForField(labelText) != null)
                _buildErrorMessage(controller, labelText, isDark),
            ],
          );
        },
      ),
    );
  }

  dynamic _getIconForField(String labelText) {
    switch (labelText.toLowerCase()) {
      case 'full name': return HugeIcons.strokeRoundedUserAccount;
      case 'email': return HugeIcons.strokeRoundedMail01;
      case 'phone': return HugeIcons.strokeRoundedCall02;
      case 'mobile': return HugeIcons.strokeRoundedSmartPhone01;
      case 'website': return HugeIcons.strokeRoundedWebDesign02;
      case 'job title': return HugeIcons.strokeRoundedWorkHistory;
      case 'google maps api key': return Icons.map_outlined;
      default: return HugeIcons.strokeRoundedUserAccount;
    }
  }

  String? Function(String?)? _getValidatorForField(String labelText) {
    switch (labelText.toLowerCase()) {
      case 'email':
        return (value) {
          if (value == null || value.trim().isEmpty) return null;
          final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
          if (!emailRegex.hasMatch(value.trim())) return 'Please enter a valid email address';
          return null;
        };
      case 'website':
        return (value) {
          if (value == null || value.trim().isEmpty) return null;
          final urlRegex = RegExp(r'^(https?:\/\/)?(www\.)?[a-zA-Z0-9-]+(\.[a-zA-Z]{2,})+(\/.*)?$');
          if (!urlRegex.hasMatch(value.trim())) return 'Please enter a valid website URL';
          return null;
        };
      default:
        return null;
    }
  }

  Widget _buildErrorMessage(TextEditingController controller, String labelText, bool isDark) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final validator = _getValidatorForField(labelText);
        final errorMessage = validator?.call(value.text);
        if (errorMessage == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text(
            errorMessage,
            style: TextStyle(color: Colors.red[400], fontSize: 12, fontWeight: FontWeight.w400),
          ),
        );
      },
    );
  }

  Widget _buildProfileImageSection(BuildContext context, bool isDark) {
    Widget photoWidget;
    if (_pickedImageBase64 != null) {
      photoWidget = ClipOval(
        child: Image.memory(base64Decode(_pickedImageBase64!), width: 120, height: 120, fit: BoxFit.cover),
      );
    } else {
      photoWidget = OdooAvatar(
        imageBase64: _userAvatarBase64,
        size: 120, iconSize: 60,
        borderRadius: BorderRadius.circular(60),
        placeholderColor: isDark ? Colors.grey[700] : Colors.grey[300],
        iconColor: isDark ? Colors.grey[500] : Colors.grey[600],
      );
    }

    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: null,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: isDark ? Colors.grey[600]! : Colors.grey[300]!, width: 3),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 16, offset: const Offset(0, 6), spreadRadius: 2),
                    ],
                  ),
                  child: photoWidget,
                ),
                if (_isEditMode)
                  Positioned(
                    bottom: 8, right: 8,
                    child: InkWell(
                      onTap: _showImageSourceActionSheet,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: isDark ? Colors.grey[900]! : Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: const HugeIcon(icon: HugeIcons.strokeRoundedCamera02, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (_normalizeForEdit(_userData?['name']).isNotEmpty)
            Text(
              _normalizeForEdit(_userData!['name']),
              style: TextStyle(
                fontSize: _rs(context, 15),
                fontWeight: FontWeight.w400,
                color: isDark ? Colors.grey[400] : Colors.grey[800],
                letterSpacing: 0.1,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  Widget _buildIcon(dynamic icon, Color color, double size) {
    if (icon is IconData) return Icon(icon, color: color, size: size);
    return HugeIcon(icon: icon, color: color, size: size);
  }
}
