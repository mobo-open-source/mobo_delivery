import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../LoginPage/services/storage_service.dart';
import '../../../NavBars/Pickings/PickingFormPage/services/hive_service.dart';
import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/buttons/mobo_button.dart';
import '../../../shared/widgets/snackbar.dart';

/// A confirmation dialog that handles user logout with loading feedback.
///
/// Features:
///   • Visual confirmation prompt
///   • Loading overlay during logout process
///   • Preserves important onboarding & biometric flags
///   • Clears SharedPreferences (except preserved keys) + Hive data
///   • Navigates back to login screen and removes all previous routes
class LogoutDialog extends StatefulWidget {
  final StorageService storageService;

  const LogoutDialog({required this.storageService});

  @override
  _LogoutDialogState createState() => _LogoutDialogState();
}

/// State class for LogoutDialog.
///
/// Handles:
///   • Logout loading state
///   • Logout execution workflow
///   • Cache and session clearing
///   • Navigation back to login screen
class _LogoutDialogState extends State<LogoutDialog> {
  bool isLogoutLoading = false;
  final HiveService _hiveService = HiveService();

  /// Builds the logout confirmation dialog UI.
  ///
  /// Displays confirmation message, cancel button,
  /// and logout button with loading indicator.
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? Colors.grey[800] : Colors.white,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Confirm Logout",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
              fontSize: 18,
            ),
          ),
        ],
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 15),
          Text(
            'Are you sure you want to log out? Your session will be ended.',
            style: TextStyle(
              fontWeight: FontWeight.normal,
              color: isDark ? Colors.white : Colors.black,
              fontSize: 18,
            ),
          ),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: MoboButton.secondary(
                label: "Cancel",
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ),
            const SizedBox(width: 10),

            Expanded(
              child: MoboButton.danger(
                label: 'Log Out',
                isLoading: isLogoutLoading,
                onPressed: () async {
                  await _performLogout(context);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Performs complete logout operation.
  ///
  /// Steps:
  ///   • Shows loading overlay
  ///   • Clears session and app storage
  ///   • Preserves onboarding, biometric, and URL history flags
  ///   • Clears Hive offline database
  ///   • Navigates user to login screen
  ///   • Shows success snackbar
  Future<void> _performLogout(BuildContext context) async {
    setState(() => isLogoutLoading = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LoadingAnimationWidget.fourRotatingDots(
                  color: isDark ? Colors.white : AppStyle.primaryColor,
                  size: 50,
                ),
                const SizedBox(height: 20),
                Text(
                  "Logging out...",
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Please wait while we process your request.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    await Future.delayed(const Duration(seconds: 2));

    final prefs = await SharedPreferences.getInstance();

    List<String> urlHistory = prefs.getStringList('urlHistory') ?? [];
    bool isGetStarted = prefs.getBool('hasSeenGetStarted') ?? false;
    bool _biometricEnabled = prefs.getBool('biometricEnabled') ?? false;

    await prefs.clear();

    await prefs.setStringList('urlHistory', urlHistory);
    await prefs.setBool('hasSeenGetStarted', isGetStarted);
    await prefs.setBool('biometricEnabled', _biometricEnabled);

    await _hiveService.clearAllData();

    if (context.mounted) {
      Navigator.pop(context);

      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);

      CustomSnackbar.showSuccess(context, "Logged out successfully");
    }

    setState(() => isLogoutLoading = false);
  }
}
