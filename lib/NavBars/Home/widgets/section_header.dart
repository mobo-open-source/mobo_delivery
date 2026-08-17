import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../shared/theme/mobo_home_theme.dart';

/// Section header row: bold title left, "View all →" tappable link right.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailingLabel;
  final VoidCallback? onTrailingTap;

  /// Overrides the title's font size. Defaults to 16.
  final double titleFontSize;

  /// Overrides the title's color. Defaults to [MoboHomeTheme.textPrimary].
  final Color? titleColor;

  /// Icon shown after [trailingLabel]. Defaults to a right chevron.
  final IconData trailingIcon;

  const SectionHeader({
    super.key,
    required this.title,
    this.trailingLabel,
    this.onTrailingTap,
    this.titleFontSize = 16,
    this.titleColor,
    this.trailingIcon = HugeIcons.strokeRoundedArrowRight01,
  });

  @override
  Widget build(BuildContext context) {
    final home = Theme.of(context).extension<MoboHomeTheme>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final linkColor = isDark ? Colors.white : home.accent;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: GoogleFonts.manrope(
            fontSize: titleFontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.16,
            color: titleColor ?? home.textPrimary,
          ),
        ),
        if (trailingLabel != null && onTrailingTap != null)
          InkWell(
            onTap: onTrailingTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    trailingLabel!,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: linkColor,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(trailingIcon, size: 14, color: linkColor),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
