import 'package:flutter/material.dart';

/// A compact horizontal indicator that shows the current offline/online status.
///
/// Displays:
///   - Fixed "Offline Mode:" label
///   - Cloud icon (off → red cloud_off, on → green cloud_done)
///   - Status text ("No Internet" in red or "Connected" in green)
///
/// Automatically adapts text/icon colors for light/dark theme.
/// Typically used in headers or status bars of offline-aware screens.
class OfflineStatusIndicator extends StatelessWidget {
  /// `true` when the app is in offline mode (no connection to server)
  final bool isOffline;

  const OfflineStatusIndicator({super.key, required this.isOffline});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Text(
          "Offline Mode:",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          isOffline ? Icons.cloud_off : Icons.cloud_done,
          color: isOffline ? Colors.red : Colors.green,
        ),
        const SizedBox(width: 8),
        Text(
          isOffline ? "No Internet" : "Connected",
          style: TextStyle(
            color: isOffline ? Colors.red : Colors.green,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
