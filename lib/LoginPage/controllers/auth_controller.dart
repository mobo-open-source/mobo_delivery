import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../Dashboard/screens/dashboard/pages/dashboard.dart';
import '../../core/providers/motion_provider.dart';
import '../models/auth_model.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
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
  final AuthService _authService;
  final StorageService _storageService;

  AuthController({
    required AuthService authService,
    required StorageService storageService,
  })  : _authService = authService,
        _storageService = storageService;

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
  Future<void> handleAuthentication(BuildContext context, AuthModel authModel) async {
    if (authModel.isLoggedIn) {
      if (authModel.useLocalAuth) {
        final authResult = await _authService.authenticateWithBiometrics();
        if (authResult == AuthenticationResult.success || authResult == AuthenticationResult.unavailable) {
          await _navigateToDashboard(context);
        } else {
          await _navigateToLogin(context);
        }
      } else {
        await _navigateToDashboard(context);
      }
    } else {
      await _navigateToLogin(context);
    }
  }

  /// Navigates to the main Dashboard screen with a fade transition.
  ///
  /// Features:
  /// • Uses PageRouteBuilder for custom transition control
  /// • Respects user's motion reduction preference (from MotionProvider)
  /// • Replaces current route (no back stack to auth screens)
  Future<void> _navigateToDashboard(BuildContext context) async {
    final motionProvider = Provider.of<MotionProvider>(context, listen: false);

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const Dashboard(),
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
    final motionProvider = Provider.of<MotionProvider>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();
    bool isGetStarted = prefs.getBool('hasSeenGetStarted')?? false;
    if(isGetStarted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => LoginScreen(),
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
      );
    }else{
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation,
              secondaryAnimation) => const GetStartedScreen(),
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
      );
    }
  }
}