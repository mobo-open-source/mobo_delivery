import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../shared/utils/globals.dart';
import '../services/external_maps_service.dart';

/// Asks which map app should take the route over. Shown on iOS when Google
/// Maps is installed; each option says up front how much of the route it
/// carries, so nobody finds out after leaving the app.
///
/// Returns the chosen app, or null when dismissed.
Future<ExternalMapsApp?> showMapsAppPicker(
  BuildContext context, {
  required int stopCount,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<ExternalMapsApp>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final googleStops = stopCount > ExternalMapsService.googleMaxStops
          ? 'First ${ExternalMapsService.googleMaxStops} of $stopCount stops, in order'
          : stopCount == 1
          ? 'Directions to your stop'
          : 'All $stopCount stops, in order';
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[50],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  'Open route in',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              _MapsAppOption(
                icon: HugeIcons.strokeRoundedGoogleMaps,
                title: 'Google Maps',
                subtitle: googleStops,
                isDark: isDark,
                onTap: () =>
                    Navigator.of(sheetContext).pop(ExternalMapsApp.google),
              ),
              _MapsAppOption(
                icon: HugeIcons.strokeRoundedApple,
                title: 'Apple Maps',
                subtitle: stopCount == 1
                    ? 'Directions to your stop'
                    : 'Next stop only. Apple Maps links can\'t carry more stops.',
                isDark: isDark,
                onTap: () =>
                    Navigator.of(sheetContext).pop(ExternalMapsApp.apple),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
    },
  );
}

class _MapsAppOption extends StatelessWidget {
  const _MapsAppOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppStyle.primaryColor;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.2 : 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: isDark ? Colors.white : accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: isDark ? Colors.white60 : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  HugeIcons.strokeRoundedArrowRight01,
                  size: 18,
                  color: isDark ? Colors.white38 : Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
