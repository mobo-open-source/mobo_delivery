import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Helper class for consistent styling in tabs, buttons, labels, etc.
///
/// Provides:
/// - Primary brand color (with dark mode variant)
/// - Manrope font text style (Google Fonts)
class AppTabStyle {
  /// Returns the main brand color used across the app.
  ///
  /// - Light mode → #C03355 (pinkish red)
  /// - Dark mode → white
  static Color primaryColor({bool isDark = false}) {
    return isDark ? Colors.white : const Color(0xFFC03355);
  }

  /// Creates a text style using the Manrope font.
  ///
  /// Default values:
  /// - size: 14
  /// - weight: regular (w400)
  /// - color: primary brand color (#C03355)
  ///
  /// Example:
  /// ```dart
  /// Text('Hello', style: AppTabStyle.font(size: 16, weight: FontWeight.w600));
  /// ```
  static TextStyle font({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) {
    return GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      color: color ?? const Color(0xFFC03355),
    );
  }
}
