import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/mobo_home_theme.dart';
import '../../../shared/widgets/loaders/shimmer_skeleton.dart';
import 'mobo_card.dart';

/// One of the 2×2 stat tiles on the Home screen (Ready, Waiting, Late, Done
/// today). `prominent` styles the Late variant — heavier border, tinted
/// background, red-accent value + label, PRIORITY flag.
class StatTile extends StatelessWidget {
  final IconData icon;
  final int value;
  final String label;

  /// Accent foreground / background pair from [MoboHomeTheme].
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
    required this.accentFg,
    required this.accentBg,
    this.prominent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final home = Theme.of(context).extension<MoboHomeTheme>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color valueColor;
    final Color labelColor;
    final Color priorityColor;
    if (prominent) {
      if (isDark) {
        valueColor = Colors.white;
        labelColor = Colors.white.withValues(alpha: 0.75);
        priorityColor = Colors.white;
      } else {
        valueColor = accentFg;
        labelColor = accentFg.withValues(alpha: 0.85);
        priorityColor = accentFg;
      }
    } else {
      valueColor = home.textPrimary;
      labelColor = home.textSecondary;
      priorityColor = accentFg;
    }

    return MoboCard(
      onTap: onTap,
      background: prominent ? home.lateTileBg : home.surface,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _IconSquare(icon: icon, fg: accentFg, bg: accentBg),
              if (prominent)
                Text(
                  'PRIORITY',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: priorityColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$value',
            style: GoogleFonts.manrope(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: -0.5,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: prominent ? FontWeight.w600 : FontWeight.w400,
              color: labelColor,
            ),
          ),
        ],
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

    final squareBg = isDark ? fg.withValues(alpha: 0.7) : bg;
    final iconColor = isDark ? Colors.white : fg;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: squareBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 19, color: iconColor),
    );
  }
}

/// Skeleton placeholder for a stat tile.
///
/// Mirrors [StatTile]'s content: a 34×34 icon square (10px radius, matching
/// the real `_IconSquare`), the two-digit value bar (28px tall like the real
/// value text), and a wider label bar (12.5px tall like the real label). Same
/// [MoboCard] wrapper + padding as the real tile so the layout doesn't shift
/// when data arrives.
class StatTileSkeleton extends StatelessWidget {
  const StatTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return MoboCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SkeletonBox(
            width: 34,
            height: 34,
            borderRadius: BorderRadius.circular(10),
          ),
          const SizedBox(height: 10),
          const SkeletonLine(width: 46, height: 28),
          const SizedBox(height: 6),
          const SkeletonLine(width: 96, height: 12),
        ],
      ),
    );
  }
}
