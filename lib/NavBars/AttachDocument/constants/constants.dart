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
    'draft': Colors.grey,
    'confirmed': Colors.orange,
    'assigned': Colors.blue,
    'done': Colors.green,
    'waiting': Colors.purple,
    'cancel': Colors.red,
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