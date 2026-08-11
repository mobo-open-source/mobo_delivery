import 'package:flutter/material.dart';

import '../../../shared/widgets/loaders/shimmer_skeleton.dart';
import 'mobo_card.dart';

/// One of the 2×2 stat tiles on the Home screen (Ready, Waiting, Late, Done
/// today).
class StatTile extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;
  final String subtitle;

  final Color accentFg;
  final Color accentBg;

  /// If true, renders the "Late tile" treatment.
  final bool prominent;

  final VoidCallback? onTap;

  const StatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.subtitle,
    required this.accentFg,
    required this.accentBg,
    this.prominent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final valueColor = prominent
        ? accentFg
        : (isDark ? Colors.white : Colors.black87);
    final labelColor = isDark ? Colors.grey[300] : Colors.grey[700];
    final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return MoboCard(
      onTap: onTap,
      radius: 12,
      padding: const EdgeInsets.all(14),
      boxShadow: [
        BoxShadow(
          color: isDark
              ? Colors.black.withValues(alpha: 0.15)
              : accentFg.withValues(alpha: 0.08),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$value',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: valueColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: labelColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: subtitleColor),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            _IconSquare(icon: icon, fg: accentFg, bg: accentBg),
          ],
        ),
      ),
    );
  }
}

class _IconSquare extends StatelessWidget {
  final IconData icon;
  final Color fg;
  final Color bg;
  const _IconSquare({required this.icon, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final squareBg = isDark ? fg.withValues(alpha: 0.6) : bg;
    final iconColor = isDark ? Colors.white : fg;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: squareBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: iconColor),
    );
  }
}

/// Skeleton placeholder for a stat tile.
class StatTileSkeleton extends StatelessWidget {
  const StatTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return MoboCard(
      radius: 12,
      padding: const EdgeInsets.all(14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                SkeletonLine(width: 40, height: 22),
                SizedBox(height: 6),
                SkeletonLine(width: 96, height: 15),
                SizedBox(height: 6),
                SkeletonLine(width: 120, height: 11),
              ],
            ),
          ),
          SkeletonBox(
            width: 36,
            height: 36,
            borderRadius: BorderRadius.circular(10),
          ),
        ],
      ),
    );
  }
}
