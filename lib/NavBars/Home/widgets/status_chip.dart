import 'package:flutter/material.dart';

/// Pill-shaped chip used for row status (Late / Waiting / Ready / Done).
///
/// Colors come from the app-wide Material status palette, matching the
/// Pickings, Return and Documents lists.
enum StatusChipKind { late_, waiting, ready, done }

class StatusChip extends StatelessWidget {
  final StatusChipKind kind;
  final String label;

  const StatusChip({super.key, required this.kind, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final color = switch (kind) {
      StatusChipKind.late_ => Colors.red,
      StatusChipKind.waiting => Colors.orange,
      StatusChipKind.ready => Colors.blue,
      StatusChipKind.done => Colors.green,
    };

    final chipBg = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : color.withValues(alpha: 0.10);
    final labelColor = isDark ? Colors.white : color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: chipBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: labelColor,
          height: 1.1,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}
