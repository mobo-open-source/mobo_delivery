import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../Dashboard/screens/dashboard/pages/dashboard.dart';
import '../../core/company/session/company_session_manager.dart';
import '../../shared/widgets/snackbar.dart';
import '../models/auth_model.dart';
import '../services/app_install_check.dart';
import '../services/storage_service.dart';
import '../views/app_lock_screen.dart';
import '../views/get_started_screen.dart';
import '../views/login_screen.dart';

/// Central controller responsible for authentication flow decisions and navigation.
///
/// Responsibilities:
/// • Check current login state from secure/local storage
/// • Decide whether to show Dashboard, Login, or Get Started screen
/// • Handle biometric authentication when enabled
/// • Perform smooth navigation with motion reduction support
///
/// This class acts as a bridge between storage, auth services, and UI navigation
/// and is typically used right after app launch (e.g. in splash screen or main).
class AuthController {
  final StorageService _storageService;

  AuthController({required StorageService storageService})
    : _storageService = storageService;

  /// Checks whether the user is currently logged in and if biometric auth is enabled.
  ///
  /// Returns an [AuthModel] containing:
  /// - `isLoggedIn`: whether a valid session exists
  /// - `useLocalAuth`: whether biometric/PIN authentication is required
  ///
  /// This method should be called early in the app lifecycle (e.g. after splash screen).
  Future<AuthModel> checkLoginStatus() async {
    final status = await _storageService.getLoginStatus();
    return AuthModel(
      isLoggedIn: status['isLoggedIn'],
      useLocalAuth: status['useLocalAuth'],
    );
  }

  /// Checks whether the user is currently logged in and if biometric auth is enabled.
  ///
  /// Returns an [AuthModel] containing:
  /// - `isLoggedIn`: whether a valid session exists
  /// - `useLocalAuth`: whether biometric/PIN authentication is required
  ///
  /// This method should be called early in the app lifecycle (e.g. after splash screen).
  Future<void> handleAuthentication(
    BuildContext context,
    AuthModel authModel,
  ) async {
    if (authModel.isLoggedIn) {
      // A saved session is not a licence to walk in: Inventory may have been
      // uninstalled, or this account's access to it withdrawn, since the last
      // sign-in. Only a definite "no" ends the session — an unreachable server
      // says nothing and changes nothing.
      final problem = await AppInstallCheck().storedSessionProblem();
      if (problem != null) {
        await CompanySessionManager.clearSessionData();
        if (!context.mounted) return;
        CustomSnackbar.showError(
          context,
          problem == AccessCheckStatus.noInventoryAccess
              ? 'Your access to Inventory has been removed. Please sign in again.'
              : 'The Inventory app is no longer installed on this database.',
        );
        await _navigateToLogin(context);
        return;
      }
      if (!context.mounted) return;

      if (authModel.useLocalAuth) {
        await _navigateToAppLock(context);
      } else {
        await _navigateToDashboard(context);
      }
    } else {
      await _navigateToLogin(context);
    }
  }

  /// Shows the biometric lock over the stored session.
  ///
  /// The screen owns the retry: a failed prompt must not fall through to the
  /// sign-in screen, because the session behind the lock is still valid.
  Future<void> _navigateToAppLock(BuildContext context) async {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => AppLockScreen(
          onAuthenticationSuccess: () => _navigateToDashboard(context),
        ),
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  /// Navigates to the main Dashboard screen with a fade transition.
  ///
  /// Features:
  /// • Uses PageRouteBuilder for custom transition control
  /// • Replaces current route (no back stack to auth screens)
  Future<void> _navigateToDashboard(BuildContext context) async {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const Dashboard(),
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  /// Decides and navigates to either LoginScreen or GetStartedScreen.
  ///
  /// Logic:
  /// • Checks SharedPreferences for 'hasSeenGetStarted' flag
  /// • If false → shows onboarding (GetStartedScreen)
  /// • If true  → shows LoginScreen
  ///
  /// Also uses fade transition and respects motion reduction setting.
  Future<void> _navigateToLogin(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    bool isGetStarted = prefs.getBool('hasSeenGetStarted') ?? false;
    if (isGetStarted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              LoginScreen(),
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const GetStartedScreen(),
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }
}
