import 'package:flutter/material.dart';

/// A pill-shaped widget that displays the current grouping criteria.
class GroupByPill extends StatelessWidget {
  final String label;
  final ThemeData theme;

  const GroupByPill({super.key, required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white70 : Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.layers_outlined,
            size: 14,
            color: isDark ? Colors.black : Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            '$label',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.black : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
