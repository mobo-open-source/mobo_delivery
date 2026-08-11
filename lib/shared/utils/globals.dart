import 'package:flutter/material.dart';

/// Central place for app level static styling values.
///
/// Helps maintain consistency across the app UI and avoids
/// hardcoding colors in multiple widgets.
class AppStyle {
  /// Primary brand color used for:
  /// • Buttons
  /// • Highlights
  /// • Active states
  /// • Key UI elements
  static const primaryColor = Color(0xFFC03355);

  /// Lightened brand color for text/icons/outlines on dark surfaces.
  static const primaryColorDark = Color(0xFFE8637F);

  /// The brand accent for foreground use — [primaryColor] on light, [primaryColorDark] on dark.
  static Color accentOn(Brightness brightness) =>
      brightness == Brightness.dark ? primaryColorDark : primaryColor;

  /// [accentOn] resolved from the ambient theme.
  static Color accentOf(BuildContext context) =>
      accentOn(Theme.of(context).brightness);
}

/// Normalises a raw Odoo RPC value for UI display. Collapses Odoo's
/// `False` / `'false'` / `null` / empty to [fallback], and unwraps
/// Many2one tuples (`[id, name]`) to their display name.
String cleanOdooValue(dynamic value, {String fallback = '—'}) {
  if (value == null || value == false) return fallback;
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'false') return fallback;
    return trimmed;
  }
  if (value is List) {
    if (value.length > 1) return cleanOdooValue(value[1], fallback: fallback);
    if (value.isEmpty) return fallback;
    return cleanOdooValue(value.first, fallback: fallback);
  }
  return value.toString();
}
