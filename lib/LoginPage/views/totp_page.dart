import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:odoo_delivery_app/Dashboard/screens/dashboard/pages/dashboard.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../NavBars/Pickings/PickingFormPage/services/hive_service.dart';
import '../../core/company/session/company_session_manager.dart';
import '../../core/providers/motion_provider.dart';
import '../../shared/utils/globals.dart';
import '../services/app_install_check.dart';
import '../services/common_storage_service.dart';

/// A screen that handles Two-Factor Authentication (TOTP) for Odoo login.
///
/// Uses a hidden InAppWebView to automate the standard Odoo web login flow,
/// including credential injection, TOTP code submission, and session cookie extraction.
/// Once authenticated, saves session data and navigates to the Dashboard or shows
/// module-missing warning if the required "Inventory" module is not installed.
class TotpPage extends StatefulWidget {
  final String serverUrl;
  final String database;
  final String username;
  final String password;
  final String protocol;

  const TotpPage({
    super.key,
    required this.serverUrl,
    required this.database,
    required this.username,
    required this.password,
    required this.protocol,
  });

  @override
  State<TotpPage> createState() => _TotpPageState();
}

/// Manages TOTP verification flow using embedded browser automation.
///
/// Responsibilities:
///   - Loads Odoo login page in background InAppWebView
///   - Auto-injects username/password
///   - Handles TOTP page → focuses input & submits code via JS
///   - Extracts session_id cookie on successful login
///   - Saves session & account data
///   - Checks for required modules before proceeding to Dashboard
class _TotpPageState extends State<TotpPage> {
  InAppWebViewController? _webController;
  final _totpController = TextEditingController();
  String? _error;
  bool _loading = true;
  bool _verifying = false;
  bool _isButtonEnabled = false;
  final _formKey = GlobalKey<FormState>();
  bool _credentialsInjected = false;
  String? sessionId;
  final CommonStorageService _commonStorageService = CommonStorageService();
  final HiveService _hiveService = HiveService();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[950] : Colors.grey[50],
                  image: DecorationImage(
                    image: const AssetImage('assets/background.png'),
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
          ),

          Positioned.fill(
            child: Opacity(
              opacity: 0.0,
              child: InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(
                    '${widget.serverUrl}/web/login?db=${widget.database}',
                  ),
                ),
                initialOptions: InAppWebViewGroupOptions(
                  crossPlatform: InAppWebViewOptions(
                    javaScriptEnabled: true,
                    cacheEnabled: false,
                    clearCache: true,
                    userAgent:
                        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                        "(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
                  ),
                  android: AndroidInAppWebViewOptions(
                    useHybridComposition: true,
                    allowContentAccess: true,
                    allowFileAccess: true,
                    mixedContentMode:
                        AndroidMixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                    forceDark: AndroidForceDark.FORCE_DARK_AUTO,
                    disableDefaultErrorPage: true,
                  ),
                ),
                onWebViewCreated: (controller) {
                  _webController = controller;
                },
                onReceivedServerTrustAuthRequest:
                    (controller, challenge) async {
                      return ServerTrustAuthResponse(
                        action: ServerTrustAuthResponseAction.PROCEED,
                      );
                    },

                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  return NavigationActionPolicy.ALLOW;
                },

                onLoadError: (controller, url, code, message) {
                },

                onReceivedError: (controller, request, errorResponse) {
                },
                onLoadStop: (controller, url) async {
                  final urlStr = url?.toString() ?? '';

                  if (urlStr.contains('/web/database/selector') ||
                      urlStr.contains('/web/database/manager')) {
                    await _handleDatabaseSelector();
                    return;
                  }

                  if (urlStr.contains('/web/login') && !_credentialsInjected) {
                    await Future.delayed(const Duration(milliseconds: 800));
                    await _injectCredentials();
                    return;
                  }

                  if (urlStr.contains('/web/login/totp') ||
                      urlStr.contains('totp_token')) {
                    if (mounted) {
                      setState(() {
                        _loading = false;
                      });
                    }
                    await Future.delayed(const Duration(milliseconds: 600));
                    await _focusTotpField();
                    return;
                  }

                  if ((urlStr.contains('/web') ||
                          urlStr.contains('/odoo/discuss') ||
                          urlStr.contains('/odoo') ||
                          urlStr.contains('/odoo/apps') ||
                          urlStr.contains('/website')) &&
                      !urlStr.contains('/login') &&
                      !urlStr.contains('/totp')) {
                    await _extractAndSaveSession();
                  }
                },
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              bottom: false,
              child: IgnorePointer(
                ignoring: _loading,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(32),
                    child: Container(
                      height: 64,
                      width: 64,
                      alignment: Alignment.center,
                      child: Icon(
                        HugeIcons.strokeRoundedArrowLeft01,
                        color: _loading ? Colors.white54 : Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                _buildForm(),
              ],
            ),
          ),

          if (_loading)
            Container(
              color: isDark ? Colors.black54 : Colors.white70,
              child: Center(
                child: LoadingAnimationWidget.fourRotatingDots(
                  color: Theme.of(context).colorScheme.primary,
                  size: 60,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Displays dialog when required "Inventory" module is not installed.
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

  /// Submits the 6-digit TOTP code via JavaScript and monitors login success.
  ///
  /// Performs these steps:
  ///   1. Validates input format (6 digits)
  ///   2. Injects code into the most likely TOTP field
  ///   3. Checks/trusts device if checkbox exists
  ///   4. Submits form (button click or native submit)
  ///   5. Polls DOM for success indicators (user menu, web client)
  ///   6. Extracts session cookie
  ///   7. Saves session & navigates (or shows module error)
  ///
  /// Shows appropriate error messages on failure.
  Future<void> _submitTotp() async {
    if (_verifying || _webController == null) return;

    setState(() {
      _verifying = true;
      _error = null;
    });

    final totp = _totpController.text.trim();
    if (totp.length != 6 || !RegExp(r'^\d{6}$').hasMatch(totp)) {
      setState(() {
        _error = 'Please enter a valid 6-digit code';
        _verifying = false;
      });
      return;
    }

    try {
      await _webController!.evaluateJavascript(
        source:
        """
  (function() {
    let input = document.querySelector(
      'input[name="totp_token"], input[autocomplete="one-time-code"], input[type="text"][maxlength="6"], input[type="number"][maxlength="6"]'
    );
    if (!input) return "totp_input_not_found";
    
    // Set value and dispatch full input events
    input.focus();
    input.value = '$totp';
    ['input', 'change', 'keydown', 'keyup', 'keypress'].forEach(eventType => {
      input.dispatchEvent(new KeyboardEvent(eventType, {key: 'Enter', bubbles: true, cancelable: true}));
    });
    
    // Handle trust device if present
    const trustCheckbox = document.querySelector('input[name="trust_device"], input[type="checkbox"], [name="trust"]');
    if (trustCheckbox && !trustCheckbox.checked) {
      trustCheckbox.checked = true;
      trustCheckbox.dispatchEvent(new Event('change', {bubbles: true}));
    }
    
    // Submit form
    const form = input.closest('form') || document.querySelector('form[action*="/web/login"]');
    if (form) {
      const btn = form.querySelector('button[type="submit"], button.btn-primary, button[name="submit"], button.btn-block');
      if (btn) {
        btn.click();
      } else {
        form.submit();  // Fallback to native submit
      }
      return "totp_submitted";
    }
    return "form_not_found";
  })();
  """,
      );

      await Future.delayed(const Duration(seconds: 2));

      for (int i = 0; i < 20; i++) {
        final isLoggedIn = await _webController!.evaluateJavascript(
          source: """
    (function() {
      const userMenu = document.querySelector('.o_user_menu, .oe_topbar_avatar, .o_apps_switcher, [data-menu="account"]');
      const webClient = document.querySelector('.o_web_client, .o_action_manager');
      const error = document.querySelector('.alert-danger, .o_error_dialog');
      if (userMenu || webClient) return true;
      if (error) return 'error';
      return false;
    })();
    """,
        );
        if (isLoggedIn == 'error') {
          setState(
                () => _error = "Invalid code or login failed. Please try again.",
          );
          return;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }

      await Future.delayed(const Duration(seconds: 4));

      final currentUrl = await _webController!.getUrl();
      final urlStr = currentUrl?.toString() ?? '';

      final cookies = await CookieManager.instance().getCookies(
        url: currentUrl!,
      );

      final sessionCookie = cookies.firstWhere(
            (c) => c.name == 'session_id',
        orElse: () => Cookie(name: '', value: ''),
      );

      if (sessionCookie.value.isEmpty) {
        setState(() => _error = "Login failed or invalid TOTP.");
        return;
      }

      final domSuccess = await _webController!.evaluateJavascript(
        source: """
      (function() {
        const hasUserMenu = !!document.querySelector('.o_user_menu, .oe_topbar_avatar');
        const hasWebClient = !!document.querySelector('.o_web_client');
        return hasUserMenu || hasWebClient;
      })();
    """,
      );

      if (domSuccess == true ||
          currentUrl.toString().contains('/web?') ||
          currentUrl.toString().contains('/odoo/discuss?') ||
          currentUrl.toString().contains('/odoo') ||
          currentUrl.toString().contains('/odoo/apps?')) {
        await _saveSessionData();
      }

      final isSuccess =
          sessionCookie.value.isNotEmpty &&
              sessionCookie.value.length > 20 &&
              ((urlStr.contains('/web') ||
                  (urlStr.contains('/odoo/discuss')) ||
                  (urlStr.contains('/odoo')) ||
                  (urlStr.contains('/odoo/apps'))) &&
                  !urlStr.contains('/login') &&
                  !urlStr.contains('/totp'));

      if (!isSuccess) {
        setState(() {
          _error = 'Invalid code or login failed. Please try again.';
        });
        return;
      }

      if (mounted) {
        final checker = AppInstallCheck();
        final isInstalled = await checker.checkRequiredModules();

        if (!isInstalled) {
          final prefs = await SharedPreferences.getInstance();
          List<String> urlHistory = prefs.getStringList('urlHistory') ?? [];
          bool isGetStarted = prefs.getBool('hasSeenGetStarted') ?? false;

          await prefs.clear();

          await prefs.setStringList('urlHistory', urlHistory);
          await prefs.setBool('hasSeenGetStarted', isGetStarted);

          await _hiveService.clearAllData();

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
          final motion = Provider.of<MotionProvider>(context, listen: false);
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const Dashboard(),
              transitionDuration: motion.reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
              transitionsBuilder: (_, a, __, c) =>
                  FadeTransition(opacity: a, child: c),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _error = 'Authentication failed. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  /// Saves current URL + credentials to shared preferences history (top 10).
  ///
  /// Normalizes protocol & URL, removes duplicates, keeps most recent first.
  Future<void> _saveUrlHistory({
    required String protocol,
    required String url,
    required String database,
    required String username,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('urlHistory') ?? [];

    String finalProtocol = protocol;
    String finalUrl = url.trim();

    if (finalUrl.startsWith('https://')) {
      finalProtocol = 'https://';
      finalUrl = finalUrl.replaceFirst('https://', '');
    } else if (finalUrl.startsWith('http://')) {
      finalProtocol = 'http://';
      finalUrl = finalUrl.replaceFirst('http://', '');
    }

    final entry = jsonEncode({
      'protocol': finalProtocol,
      'url': finalUrl,
      'db': database,
      'username': username,
    });

    history.removeWhere((e) {
      final d = jsonDecode(e);
      return d['url'] == finalUrl && d['protocol'] == finalProtocol;
    });

    history.insert(0, entry);
    await prefs.setStringList('urlHistory', history.take(10).toList());
  }

  /// Extracts session cookie, saves full session via CompanySessionManager,
  /// stores account info, updates shared preferences flags and timestamp.
  Future<void> _saveSessionData() async {
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(widget.serverUrl),
      );

      final sessionCookie = cookies.firstWhere(
        (cookie) => cookie.name == 'session_id',
        orElse: () => Cookie(name: '', value: ''),
      );

      if (sessionCookie.value.isNotEmpty) {
        sessionId = sessionCookie.value;
        final success = await CompanySessionManager.loginAndSaveSession(
          serverUrl: widget.serverUrl,
          database: widget.database,
          userLogin: widget.username.trim(),
          password: widget.password.trim(),
          session_Id: sessionId,
        );
        await _saveUrlHistory(
          protocol: widget.protocol,
          url: widget.serverUrl,
          database: widget.database,
          username: widget.password.trim(),
        );
        if (!success) {
          return;
        }
        final session = await CompanySessionManager.getCurrentSession();
        await _commonStorageService.saveAccount({
          'userName': session?.userName,
          'userLogin': session?.userLogin,
          'userId': session?.userId,
          'sessionId': session?.sessionId,
          'serverVersion': session?.serverVersion,
          'userLang': session?.userLang,
          'partnerId': session?.partnerId,
          'userTimezone': session?.userTimezone,
          'companyId': session?.companyId,
          'companyName': session?.companyName,
          'isSystem': session?.isSystem,
          'url': widget.serverUrl,
          'database': widget.database,
          'image': '',
        });

        final prefs = await SharedPreferences.getInstance();

        await prefs.remove('logoutAction');

        await prefs.setString('sessionId', sessionId!);
        await prefs.setString('username', widget.username);
        await prefs.setString('url', widget.serverUrl);
        await prefs.setString('database', widget.database);
        await prefs.setBool('logoutAction', false);
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('lastUsername', widget.username.trim());

        await prefs.setInt(
          'loginTimestamp',
          DateTime.now().millisecondsSinceEpoch,
        );
      } else {
        setState(() {
          _error = 'Invalid code or login failed. Please try again.';
        });
        return;
      }
    } catch (e) {
      setState(() {
        _error = 'Invalid code or login failed. Please try again.';
      });
      return;
    }
  }

  /// Injects username and password into the Odoo login form using JavaScript.
  ///
  /// Waits briefly for DOM readiness, finds login/password fields,
  /// sets values safely (JSON-encoded), and triggers form submission.
  /// Marks injection as done to prevent repeated attempts.
  Future<void> _injectCredentials() async {
    if (_credentialsInjected) return;

    final safeUser = jsonEncode(widget.username);
    final safePass = jsonEncode(widget.password);
    final safeDb = jsonEncode(widget.database);

    final result = await _webController?.evaluateJavascript(
      source:
          """
      (function() {
        const login = document.querySelector('input[name="login"], input[type="email"]');
        const password = document.querySelector('input[name="password"]');
        const db = document.querySelector('input[name="db"], select[name="db"]');
        const form = document.querySelector('form[action*="/web/login"]');

        if (!login || !password || !form) return "missing";

        login.value = $safeUser;
        password.value = $safePass;
        if (db) {
          if (db.tagName === 'INPUT') db.value = $safeDb;
          else db.value = $safeDb;
        }

        const btn = form.querySelector('button[type="submit"]');
        if (btn) btn.click();
        else form.requestSubmit();

        return "submitted";
      })();
    """,
    );

    if (result == "submitted") {
      _credentialsInjected = true;
    }
  }

  /// Focuses and selects the TOTP input field when the page is ready.
  Future<void> _focusTotpField() async {
    await _webController?.evaluateJavascript(
      source: """
      const input = document.querySelector('input[name="totp_token"], input[autocomplete="one-time-code"]');
      if (input) {
        input.focus();
        input.select();
      }
    """,
    );
  }

  /// Selects the correct database in the database selector page (if shown).
  Future<void> _handleDatabaseSelector() async {
    await _webController?.evaluateJavascript(
      source:
          """
      const select = document.querySelector('select[name="db"]');
      if (select) {
        select.value = '${widget.database}';
        const btn = document.querySelector('button[type="submit"]');
        if (btn) btn.click();
      }
    """,
    );
  }

  Future<void> _extractAndSaveSession() async {
    final currentUrl = await _webController?.getUrl();
    if (currentUrl == null) return;

    final cookies = await CookieManager.instance().getCookies(url: currentUrl);
    final sessionCookie = cookies.firstWhere(
      (c) => c.name == 'session_id',
      orElse: () => Cookie(name: 'session_id', value: ''),
    );

    if (sessionCookie.value.isEmpty) {
      setState(() => _error = "Login failed. Please try again.");
      return;
    }
  }

  /// Builds the visual header with icon, title, description and server info.
  Widget _buildHeader() {
    return Column(
      children: [
        Icon(
          HugeIcons.strokeRoundedTwoFactorAccess,
          color: Colors.white,
          size: 48,
        ),
        const SizedBox(height: 24),
        Text(
          'Two-factor Authentication',
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.w600,
            color: Colors.white,
            fontSize: 25,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'To login, enter below the six-digit authentication code provided by your Authenticator app.',
          style: GoogleFonts.montserrat(
            fontSize: 14,
            color: Colors.white70,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
        if (widget.serverUrl.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Server: ${widget.serverUrl}',
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: Colors.white60,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  /// Builds the TOTP input form with validation, error display and submit button.
  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _totpController,
            keyboardType: TextInputType.number,
            enabled: !_loading || !_verifying,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'TOTP is required';
              }
              return null;
            },
            onChanged: (value) {
              setState(() {
                _isButtonEnabled = value.trim().isNotEmpty;
                _formKey.currentState?.validate();
                if (_error != null) _error = null;
              });
            },
            cursorColor: Colors.black,
            style: GoogleFonts.manrope(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Colors.black,
            ),
            decoration: InputDecoration(
              hintText: 'Enter TOTP Code',
              hintStyle: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Colors.black.withOpacity(.4),
              ),
              prefixIcon: const Icon(HugeIcons.strokeRoundedSmsCode, size: 20),
              prefixIconColor: MaterialStateColor.resolveWith(
                (states) => states.contains(MaterialState.disabled)
                    ? Colors.black26
                    : Colors.black54,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
              errorStyle: const TextStyle(color: Colors.white),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.red[900]!, width: 1.0),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 10),

          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: _error != null ? 48 : 0,
            child: _error != null
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          HugeIcons.strokeRoundedAlertCircle,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: GoogleFonts.manrope(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
          ),

          const SizedBox(height: 20),

          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: (_verifying || !_isButtonEnabled) ? null : _submitTotp,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _verifying
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Authenticating',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
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
                      'Authenticate',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _webController?.dispose();
    _totpController.dispose();
    super.dispose();
  }
}
