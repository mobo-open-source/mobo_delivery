import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

/// A badge widget that displays the number of active filters currently applied.
class ActiveFiltersBadge extends StatelessWidget {
  final int count;
  final ThemeData theme;
  final bool hasGroupBy;

  const ActiveFiltersBadge({
    super.key,
    required this.count,
    required this.theme,
    this.hasGroupBy = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;

    if (count == 0) {
      if (hasGroupBy) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'No filters applied',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white : const Color(0xff1E1E1E),
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final accent = isDark ? Colors.white : Colors.black;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedFilterHorizontal,
            size: 14,
            color: accent,
          ),
          const SizedBox(width: 4),
          Text(
            '$count active',
            style: TextStyle(
              fontSize: 12,
              color: accent,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
