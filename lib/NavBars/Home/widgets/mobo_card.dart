import 'package:flutter/material.dart';

import '../../../shared/theme/mobo_home_theme.dart';

/// Base surface primitive used across the Home screen (stat tiles, empty
/// state, quick-action tiles). Draws a rounded surface with the app-wide
/// resting shadow — **no hairline border** — so it reads as a sibling of the
/// Pickings / Return / Documents list tiles.
///
/// Callers that need a "Late" style pass `background` (e.g. `home.lateTileBg`);
/// the accent-strip variant used by attention rows lives in [PickingRow]'s
/// `_TileShell` because the two aren't visually identical anymore.
class MoboCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? background;
  final VoidCallback? onTap;

  const MoboCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 16,
    this.background,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final home = Theme.of(context).extension<MoboHomeTheme>()!;
    final r = BorderRadius.circular(radius);

    Widget content = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background ?? home.surface,
        borderRadius: r,
        boxShadow: home.cardShadow,
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: r,
          child: content,
        ),
      );
    }
    return content;
  }
}
