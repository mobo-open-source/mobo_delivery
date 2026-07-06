import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../shared/theme/mobo_home_theme.dart';
import 'mobo_card.dart';

/// Empty state for the "Needs attention" list: a centered check-circle inside
/// a green pill + "All caught up" title + short subtitle. Rendered in place of
/// the list when [HomeState.attention] is empty.
class AllCaughtUp extends StatelessWidget {
  const AllCaughtUp({super.key});

  @override
  Widget build(BuildContext context) {
    final home = Theme.of(context).extension<MoboHomeTheme>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Same sales-app icon-square pattern: dark = strong 70% tint + white
    // icon; light = subtle tint + colored icon.
    final circleBg = isDark ? home.doneFg.withValues(alpha: 0.7) : home.doneBg;
    final iconColor = isDark ? Colors.white : home.doneFg;
    return MoboCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: circleBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              HugeIcons.strokeRoundedCheckmarkCircle02,
              size: 28,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'All caught up',
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: home.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 220,
            child: Text(
              'Nothing overdue right now. Late and waiting deliveries will show here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: home.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
