import 'package:flutter/material.dart';

import '../../../shared/utils/globals.dart';

/// A compact header card displayed at the top during active navigation mode.
///
/// Shows:
///   - Current travel mode as a readable title (e.g. "Drive", "Bike", "Walk")
///   - A close button (usually to exit navigation mode)
///
/// Adapts colors and icons for light/dark theme.
/// Designed to be positioned at the top-center of the map screen.
class NavigationHeader extends StatelessWidget {
  final String selectedTravelMode;
  final VoidCallback onClose;

  const NavigationHeader({
    super.key,
    required this.selectedTravelMode,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    /// Maps internal travel mode strings to user-friendly display titles.
    ///
    /// Falls back to generic "Navigation" if mode is unrecognized.
    String getTitle() {
      switch (selectedTravelMode) {
        case 'driving':
          return 'Drive';
        case 'two_wheeler':
          return 'Bike';
        case 'transit':
          return 'Train';
        case 'walking':
          return 'Walk';
        default:
          return 'Navigation';
      }
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 4,
      color: isDark ? Colors.black : AppStyle.primaryColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              getTitle(),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            CircleAvatar(
              backgroundColor: isDark ? Color(0xff3c3c3c) : Colors.white,
              child: IconButton(
                icon: Icon(
                  Icons.close,
                  color: isDark ? Colors.white : AppStyle.primaryColor,
                  size: 20,
                ),
                onPressed: onClose,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
