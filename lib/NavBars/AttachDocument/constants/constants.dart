import 'package:flutter/material.dart';

import '../../../shared/utils/globals.dart';

/// Centralized constants for UI styling and state representation across the app.
///
/// This class provides:
///   - Color mappings for different picking/transfer states
///   - Human-readable labels for each state
///   - Global color references (primary theme color)
///
/// Using this class ensures consistent appearance and reduces magic strings/colors
/// throughout the application (especially in lists, badges, and status indicators)
class AppConstants {
  /// Maps internal picking/transfer state keys to semantic UI colors.
  ///
  /// These colors are used in status badges, chips, indicators, and tiles
  /// to visually communicate the current status of stock operations.
  static const Map<String, Color> stateColors = {
    'draft': Color(0xFF6B7280),
    'confirmed': Color(0xFFF97316),
    'assigned': Color(0xFF3B82F6),
    'done': Color(0xFF00A63E),
    'waiting': Color(0xFFF97316),
    'cancel': Color(0xFFEF4444),
  };

  /// Maps internal state keys to user-friendly, readable labels.
  ///
  /// Used in UI elements such as:
  ///   - Status badges
  ///   - List tiles
  ///   - Filters
  ///   - Detail screens
  ///
  /// Ensures users see meaningful text instead of technical state codes.
  static const Map<String, String> stateLabels = {
    'draft': 'Draft',
    'confirmed': 'Waiting',
    'assigned': 'Ready',
    'done': 'Done',
    'waiting': 'Waiting Another Op.',
    'cancel': 'Cancelled',
  };

  static const Color appBarColor = AppStyle.primaryColor;
}