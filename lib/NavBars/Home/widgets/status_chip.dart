import 'package:flutter/material.dart';

import '../../../shared/theme/mobo_home_theme.dart';

/// Pill-shaped chip used for row status (Late / Waiting / Ready / Done).
/// Colors come from the [MoboHomeTheme] fg/bg pairs — no hex leaks in.
enum StatusChipKind { late_, waiting, ready, done }

class StatusChip extends StatelessWidget {
  final StatusChipKind kind;
  final String label;

  const StatusChip({super.key, required this.kind, required this.label});

  @override
  Widget build(BuildContext context) {
    final home = Theme.of(context).extension<MoboHomeTheme>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (fg, bg) = switch (kind) {
      StatusChipKind.late_ => (home.lateFg, home.lateBg),
      StatusChipKind.waiting => (home.waitFg, home.waitBg),
      StatusChipKind.ready => (home.readyFg, home.readyBg),
      StatusChipKind.done => (home.doneFg, home.doneBg),
    };

    final chipBg = isDark ? Colors.white.withValues(alpha: 0.15) : bg;
    final labelColor = isDark ? Colors.white : fg;
    final labelWeight = isDark ? FontWeight.bold : FontWeight.w700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: chipBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: labelWeight,
          color: labelColor,
          height: 1.1,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}
