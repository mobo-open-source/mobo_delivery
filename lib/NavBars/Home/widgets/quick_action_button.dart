import 'package:flutter/material.dart';

import '../../../shared/theme/mobo_home_theme.dart';
import 'mobo_card.dart';

/// One of the 3 quick-action tiles: a [MoboCard] holding the icon and its
/// caption stacked inside the same surface. Self-contained button that reads
/// as a peer of the stat tiles above and the picking rows below — same
/// borderless surface + drop shadow, same 12-radius corner.
class QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final home = Theme.of(context).extension<MoboHomeTheme>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final iconColor = isDark ? Colors.white : home.qaFg;
    return Expanded(
      child: MoboCard(
        radius: 12,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: home.textPrimary,
                height: 1.15,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
