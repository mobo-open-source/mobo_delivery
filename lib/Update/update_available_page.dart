import 'package:flutter/material.dart';

import '../shared/utils/globals.dart';
import '../shared/widgets/buttons/mobo_button.dart';

/// A full-screen "Update Available" page.
///
/// Designed to be shown when a newer build of the app is available. When
/// [isRequired] is true the page blocks back navigation, forcing the user to
/// update before continuing (a hard/force-update gate). When false the user
/// can dismiss it (e.g. for an optional update) — wire that via [onSkip].
///
/// The visuals follow the mobo design system: brand-colored accent icon,
/// bold title, muted subtitle and a primary [MoboButton] call-to-action.
///
/// Example:
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => UpdateAvailablePage(
///     latestVersion: '1.0.4',
///     onUpdate: () => launchStoreListing(),
///   ),
/// ));
/// ```
class UpdateAvailablePage extends StatelessWidget {
  /// The newest version number, shown in the subtitle and footer (e.g. "1.0.4").
  final String latestVersion;

  /// Called when the user taps "Update Now" (typically opens the store).
  final VoidCallback onUpdate;

  /// When true (default) the update is mandatory: back navigation is blocked
  /// and the "required to continue" hint is shown.
  final bool isRequired;

  /// Called when an optional update is skipped. Only used when [isRequired]
  /// is false.
  final VoidCallback? onSkip;

  const UpdateAvailablePage({
    super.key,
    required this.latestVersion,
    required this.onUpdate,
    this.isRequired = true,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppStyle.primaryColor;
    final titleColor = isDark ? Colors.white : Colors.black;
    final subtitleColor = isDark ? Colors.white70 : const Color(0xFF6B7280);

    return PopScope(
      canPop: !isRequired,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 3),

                Container(
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.download_rounded,
                    color: primaryColor,
                    size: 60,
                  ),
                ),
                const SizedBox(height: 36),

                Text(
                  'Update Available',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 32,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 18),

                Text(
                  'A new version ($latestVersion) is available. Please '
                  'update for the best experience.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 18,
                    height: 1.4,
                    color: subtitleColor,
                  ),
                ),
                const SizedBox(height: 40),

                MoboButton.primary(
                  label: 'Update Now',
                  height: 56,
                  borderRadius: 16,
                  onPressed: onUpdate,
                ),
                const SizedBox(height: 16),

                if (isRequired)
                  Text(
                    'This update is required to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      color: subtitleColor,
                    ),
                  )
                else
                  TextButton(
                    onPressed: onSkip,
                    child: Text(
                      'Maybe Later',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: subtitleColor,
                      ),
                    ),
                  ),

                const Spacer(flex: 4),

                Text(
                  'Latest version: v$latestVersion',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    color: subtitleColor.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
