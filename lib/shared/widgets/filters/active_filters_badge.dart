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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white70 : Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HugeIcon(
            icon: HugeIcons.strokeRoundedFilterHorizontal,
            size: 14,
            color: Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            '$count active',
            style: TextStyle(
              fontSize: 12,

              color: isDark ? Colors.black : Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
