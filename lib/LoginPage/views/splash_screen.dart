import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../controllers/auth_controller.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';

/// The first screen shown when the app launches.
///
/// Displays a branded background video (or fallback logo) while performing
/// an authentication status check in the background. After a minimum display
/// duration (usually 3 seconds), it automatically navigates to either the
/// login screen or the main authenticated screen based on token/user validity.
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

/// Manages the splash screen lifecycle, video playback, and authentication flow.
///
/// Responsibilities:
///   - Waits for a minimum splash duration
///   - Checks login status using AuthController
///   - Handles navigation based on authentication result
///   - Displays background video when ready, or fallback logo during loading
class _SplashScreenState extends State<SplashScreen> {
  late AuthController _authController;

  @override
  void initState() {
    super.initState();

    // Initialize authentication controller with required services
    _authController = AuthController(
      authService: AuthService(),
      storageService: StorageService(),
    );

    _startAuthCheck();
  }

  /// Delays for branding visibility, then checks authentication status and navigates.
  ///
  /// Flow:
  ///   1. Waits for a fixed duration (currently 3 seconds) to ensure the splash
  ///      screen is visible long enough for branding purposes.
  ///   2. Calls [AuthController.checkLoginStatus] to determine if user is logged in.
  ///   3. Uses [AuthController.handleAuthentication] to perform navigation.
  ///
  /// This method runs once during initialization and does not repeat.
  Future<void> _startAuthCheck() async {
    await Future.delayed(const Duration(seconds: 3));
    final authModel = await _authController.checkLoginStatus();
    await _authController.handleAuthentication(context, authModel);
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Builds the splash UI: background video when initialized, or centered logo fallback.
  ///
  /// The video is provided via Provider<VideoPlayerController> (expected to be
  /// initialized higher in the widget tree, usually in main.dart or app wrapper).
  ///
  /// Behavior:
  ///   - When video is ready → shows full-screen cover-fit video
  ///   - Otherwise → shows circular app icon centered on screen
  @override
  Widget build(BuildContext context) {
    final videoController = Provider.of<VideoPlayerController>(context);

    return Scaffold(
      body: videoController.value.isInitialized
          ? SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: videoController.value.size.width,
            height: videoController.value.size.height,
            child: VideoPlayer(videoController),
          ),
        ),
      )
          : Center(
        child: ClipOval(
          child: Image.asset(
            'assets/icon.png',
            width: 200,
            height: 200,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
