import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

/// A standard container widget used to group related settings into a card.
class SectionCard extends StatelessWidget {
  final String title;
  final dynamic icon;
  final List<Widget> children;
  final Widget? headerTrailing;

  const SectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.headerTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.grey[850]! : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildIcon(icon, isDark ? Colors.white : Colors.black87),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                if (headerTrailing != null) headerTrailing!,
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildIcon(dynamic icon, Color color) {
    if (icon is IconData) return Icon(icon, color: color, size: 20);
    return HugeIcon(icon: icon, color: color, size: 20);
  }
}
