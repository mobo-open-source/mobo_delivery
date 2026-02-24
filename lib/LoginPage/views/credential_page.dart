import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:local_auth/local_auth.dart';
import 'package:odoo_delivery_app/LoginPage/views/reset_password.dart';
import 'package:odoo_delivery_app/LoginPage/views/totp_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../Dashboard/screens/dashboard/pages/dashboard.dart';
import '../../Dashboard/services/storage_service.dart';
import '../../core/company/session/company_session_manager.dart';
import '../../core/providers/motion_provider.dart';
import '../../shared/utils/globals.dart';
import '../../shared/widgets/snackbar.dart';
import '../services/app_install_check.dart';
import '../services/storage_service.dart';

/// Login screen where users enter username + password after selecting server/database.
///
/// Features:
/// • Biometric authentication support (if previously enabled)
/// • Secure credential input with visibility toggle
/// • URL history saving for quick re-login
/// • Odoo-specific login via CompanySessionManager
/// • 2FA/TOTP redirection when required
/// • Friendly error messages for common failure cases
/// • Motion reduction / accessibility support
/// • Module check (Inventory required for delivery app)
class CredentialsPage extends StatefulWidget {
  final String protocol;
  final String url;
  final String database;

  const CredentialsPage({
    Key? key,
    required this.protocol,
    required this.url,
    required this.database,
  }) : super(key: key);

  @override
  State<CredentialsPage> createState() => _CredentialsPageState();
}

class _CredentialsPageState extends State<CredentialsPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  final _storageService = StorageService();
  final _dashboardStorageService = DashboardStorageService();
  String? _errorMessage;
  bool _biometricEnabled = false;
  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _loadBiometricPreference();
  }

  /// Loads whether biometric login was previously enabled by the user
  Future<void> _loadBiometricPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _biometricEnabled = prefs.getBool('biometricEnabled') ?? false;
    });
  }

  /// Attempts biometric (Face ID / Touch ID / fingerprint) authentication.
  ///
  /// Returns `true` if successful, `false` otherwise (shows snackbar on failure).
  Future<bool> _authenticateWithBiometrics() async {
    try {
      bool canAuthenticate =
          await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();
      if (!canAuthenticate) {
        if (mounted) {
          CustomSnackbar.showError(
            context,
            'Biometric authentication is not available on this device',
          );
        }
        return false;
      }

      List<BiometricType> availableBiometrics = await _localAuth
          .getAvailableBiometrics();
      String biometricType = 'biometric';
      if (Platform.isIOS && availableBiometrics.contains(BiometricType.face)) {
        biometricType = 'Face ID';
      } else if (availableBiometrics.contains(BiometricType.fingerprint)) {
        biometricType = 'Touch ID';
      }

      bool authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate with $biometricType to log in',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (!authenticated && mounted) {
        CustomSnackbar.showError(
          context,
          'Failed to authenticate with $biometricType',
        );
      }
      return authenticated;
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Error during biometric authentication, please try again later',
        );
      }
      return false;
    }
  }

  /// Saves the server + credentials to history (most recent first).
  ///
  /// Removes any previous entry for the same server/protocol before adding new one.
  Future<void> _saveUrlHistoryWithProtocol(
    String protocol,
    String url,
    String database,
    String username,
    String password,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('urlHistory') ?? [];

    final entry = {
      'protocol': protocol,
      'url': url,
      'db': database,
      'username': username,
      'password': password,
    };

    history.removeWhere((e) {
      final d = jsonDecode(e);
      return d['url'] == url && d['protocol'] == protocol;
    });

    history.insert(0, jsonEncode(entry));
    await prefs.setStringList('urlHistory', history);
  }

  /// Shows dialog informing user that the "Inventory" module is missing.
  void showModuleMissingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        title: Row(
          children: [
            const HugeIcon(
              icon: HugeIcons.strokeRoundedAlertCircle,
              color: AppStyle.primaryColor,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              'Module Missing',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.black,
              ),
            ),
          ],
        ),
        content: Text(
          'The required "Inventory" module is not installed. Please contact your administrator to enable it.',
          style: GoogleFonts.manrope(
            fontSize: 15,
            color: Colors.black87,
            height: 1.5,
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppStyle.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Back to Login',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Main login flow:
  /// 1. Validate form
  /// 2. Biometric check (if enabled)
  /// 3. Call Odoo login via CompanySessionManager
  /// 4. Save session + credentials
  /// 5. Check required modules
  /// 6. Navigate to Dashboard or show error / 2FA screen
  Future<void> _login() async {
    final motionProvider = Provider.of<MotionProvider>(context, listen: false);
    String baseUrl = widget.url.trim();

    // Clean protocol prefix if accidentally included
    if (baseUrl.startsWith("http://") || baseUrl.startsWith("https://")) {
      baseUrl = baseUrl.replaceFirst(RegExp(r'^https?://'), '');
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (widget.database == null) {
      setState(() => _errorMessage = 'Please select a database.');
      return;
    }

    // Biometric gate if user previously enabled it
    if (_biometricEnabled) {
      bool authenticated = await _authenticateWithBiometrics();
      if (!authenticated) {
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await CompanySessionManager.loginAndSaveSession(
        serverUrl: widget.protocol + baseUrl,
        database: widget.database!,
        userLogin: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (!success) {
        return;
      }
      final session = await CompanySessionManager.getCurrentSession();
      if (session != null) {

        // Save session & login state
        await _storageService.saveSession(session);
        await _storageService.saveLoginState(
          isLoggedIn: true,
          database: widget.database!,
          url: widget.protocol + baseUrl,
        );

        // Save to URL history
        await _saveUrlHistoryWithProtocol(
          widget.protocol,
          widget.url,
          widget.database,
          _usernameController.text.trim(),
          _passwordController.text.trim(),
        );

        // Save minimal account info for account switcher
        await _dashboardStorageService.saveAccount({
          'userName': session.userName,
          'userLogin': session.userLogin,
          'userId': session.userId,
          'sessionId': session.sessionId,
          'serverVersion': session.serverVersion,
          'userLang': session.userLang,
          'partnerId': session.partnerId,
          'userTimezone': session.userTimezone,
          'companyId': session.companyId,
          'companyName': session.companyName,
          'isSystem': session.isSystem,
          'url': widget.protocol + baseUrl,
          'database': widget.database!,
          'password': _passwordController.text.trim(),
          'image': '',
        });

        // Verify required modules are installed
        final checker = AppInstallCheck();
        final isInstalled = await checker.checkRequiredModules();

        if (!isInstalled) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/login',
            (route) => false,
          );
          if (mounted) {
            showModuleMissingDialog(context);
          }
          return;
        } else {
          // Success → go to main dashboard with nice transition
          Navigator.pushReplacement(
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
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
                    if (motionProvider.reduceMotion) return child;
                    return FadeTransition(opacity: animation, child: child);
                  },
            ),
          );
        }
      } else {
        setState(() => _errorMessage = 'Authentication failed.');
      }
    } catch (e) {
      final errorStr = e.toString().toLowerCase();

      // Special case: 2FA required
      if (errorStr.contains('two factor') ||
          errorStr.contains('2fa') ||
          errorStr.contains('null')) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TotpPage(
              serverUrl: widget.protocol + widget.url,
              database: widget.database,
              username: _usernameController.text.trim(),
              password: _passwordController.text.trim(),
              protocol: widget.protocol,
            ),
          ),
        );
      } else {
        setState(() => _errorMessage = _formatLoginError(e));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Converts raw error objects/strings into user-friendly messages
  String _formatLoginError(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('accessdenied') ||
        errorStr.contains('wrong login/password') ||
        errorStr.contains('invalid login') ||
        errorStr.contains('{code: 200') && errorStr.contains('accessdenied')) {
      return 'Incorrect username or password. Please check your login credentials.';
    } else if (errorStr.contains('html instead of json') ||
        errorStr.contains('formatexception')) {
      return 'Server configuration issue. This may not be an Odoo server or the URL is incorrect.';
    } else if (errorStr.contains('invalid login') ||
        errorStr.contains('wrong credentials')) {
      return 'Incorrect email or password. Please check your login credentials.';
    } else if (errorStr.contains('user not found') ||
        errorStr.contains('no such user')) {
      return 'User account not found. Please check your email address or contact your administrator.';
    } else if (errorStr.contains('database') &&
        errorStr.contains('not found')) {
      return 'Selected database is not available. Please choose a different database.';
    } else if (errorStr.contains('network') || errorStr.contains('socket')) {
      return 'Network connection failed. Please check your internet connection.';
    } else if (errorStr.contains('timeout')) {
      return 'Connection timed out. The server may be slow or unreachable.';
    } else if (errorStr.contains('unauthorized') || errorStr.contains('403')) {
      return 'Access denied. Your account may not have permission to access this database.';
    } else if (errorStr.contains('server') || errorStr.contains('500')) {
      return 'Server error occurred. Please try again later or contact your administrator.';
    } else if (errorStr.contains('ssl') || errorStr.contains('certificate')) {
      return 'SSL connection failed. Try using HTTP instead of HTTPS.';
    } else if (errorStr.contains('connection refused')) {
      return 'Server is not responding. Please verify the server URL and try again.';
    } else if (errorStr.contains('null')) {
      return '';
    } else {
      return 'Login failed. Please check your credentials and server settings.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final motionProvider = Provider.of<MotionProvider>(context, listen: false);
    String baseUrl = widget.url.trim();

    if (baseUrl.startsWith("http://") || baseUrl.startsWith("https://")) {
      baseUrl = baseUrl.replaceFirst(RegExp(r'^https?://'), '');
    }

    return Scaffold(
      body: Stack(
        children: [
          // Background with subtle image overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[950] : Colors.grey[50],
                image: DecorationImage(
                  image: AssetImage("assets/background.png"),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    isDark
                        ? Colors.black.withOpacity(1)
                        : Colors.white.withOpacity(1),
                    BlendMode.dstATop,
                  ),
                ),
              ),
            ),
          ),

          // Back button
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              bottom: false,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isLoading ? null : () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(32),
                  child: Container(
                    height: 64,
                    width: 64,
                    alignment: Alignment.center,
                    child: Icon(
                      HugeIcons.strokeRoundedArrowLeft01,
                      color: _isLoading ? Colors.white54 : Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Logo + App name
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/delivery-icon.png',
                    fit: BoxFit.fitWidth,
                    height: 30,
                    width: 30,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.delivery_dining,
                        color: Color(0xFFC03355),
                        size: 20,
                      );
                    },
                  ),
                  SizedBox(width: 10),
                  Text(
                    'mobo delivery',
                    style: const TextStyle(
                      fontFamily: 'Yaro',
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                      fontSize: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Main form content
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Sign In',
                          style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontSize: 32,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'use proper information to continue',
                          style: GoogleFonts.manrope(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 30),
                        _buildInputField(
                          controller: _usernameController,
                          label: "Username",
                          icon: HugeIcons.strokeRoundedUser03,
                        ),
                        const SizedBox(height: 20),
                        _buildInputField(
                          controller: _passwordController,
                          label: "Password",
                          obscure: true,
                          icon: HugeIcons.strokeRoundedSquareLockPassword,
                          isPasswordField: true,
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                PageRouteBuilder(
                                  pageBuilder:
                                      (
                                        context,
                                        animation,
                                        secondaryAnimation,
                                      ) => ResetPasswordScreen(
                                        url: widget.protocol + baseUrl,
                                        database: widget.database,
                                      ),
                                  transitionDuration:
                                      motionProvider.reduceMotion
                                      ? Duration.zero
                                      : const Duration(milliseconds: 300),
                                  reverseTransitionDuration:
                                      motionProvider.reduceMotion
                                      ? Duration.zero
                                      : const Duration(milliseconds: 300),
                                  transitionsBuilder:
                                      (
                                        context,
                                        animation,
                                        secondaryAnimation,
                                        child,
                                      ) {
                                        if (motionProvider.reduceMotion)
                                          return child;
                                        return FadeTransition(
                                          opacity: animation,
                                          child: child,
                                        );
                                      },
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'Forgot Password?',
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (_errorMessage != null) ...[
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text(
                              _errorMessage!,
                              style: GoogleFonts.manrope(color: Colors.white),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Signing',
                                        style: GoogleFonts.manrope(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      LoadingAnimationWidget.staggeredDotsWave(
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                    ],
                                  )
                                : Text(
                                    "Sign In",
                                    style: GoogleFonts.manrope(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a styled text input field with icon, validation, and password toggle support
  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    bool obscure = false,
    IconData? icon,
    Function(String)? onChanged,
    bool isPasswordField = false,
  }) {
    return AutofillGroup(
      child: TextFormField(
        controller: controller,
        obscureText: isPasswordField ? !_isPasswordVisible : obscure,
        onChanged: onChanged,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return '$label is required';
          }
          return null;
        },
        autofillHints: isPasswordField
            ? const [AutofillHints.password]
            : const [AutofillHints.username],
        style: GoogleFonts.manrope(color: Colors.black),
        decoration: InputDecoration(
          hintText: label,
          hintStyle: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Colors.black.withOpacity(.4),
          ),
          prefixIcon: icon != null
              ? Icon(icon, color: Colors.black54, size: 18)
              : null,
          suffixIcon: isPasswordField
              ? IconButton(
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility
                        : Icons.visibility_off,
                    color: _isPasswordVisible ? Colors.black26 : Colors.black45,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _isPasswordVisible = !_isPasswordVisible;
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.grey.shade100,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          errorStyle: GoogleFonts.manrope(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
