import 'package:flutter/material.dart';

import '../../../shared/utils/globals.dart';

/// Compact pill-shaped header shown at the top during active navigation.
///
/// Displays the current travel mode icon + label, and a close button.
/// Uses a white/surface style with subtle shadow — no solid brand-color fill.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1C1C2E) : Colors.white;
    final primary = isDark ? Colors.white : const Color(0xFF202124);
    final secondary = isDark ? const Color(0xFFAAAAAA) : const Color(0xFF70757A);
    final accent = AppStyle.primaryColor;

    IconData modeIcon;
    String modeLabel;
    switch (selectedTravelMode) {
      case 'walking':
        modeIcon = Icons.directions_walk;
        modeLabel = 'Walking';
        break;
      case 'bicycling':
        modeIcon = Icons.directions_bike;
        modeLabel = 'Cycling';
        break;
      default:
        modeIcon = Icons.directions_car_filled;
        modeLabel = 'Driving';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(modeIcon, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            modeLabel,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: primary,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: isDark ? Colors.white12 : Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, size: 16, color: secondary),
            ),
          ),
        ],
      ),
    );
  }
}
