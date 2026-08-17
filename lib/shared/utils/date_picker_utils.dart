import 'package:flutter/material.dart';

/// Extra space under the picker's Cancel/OK labels so the row doesn't sit
/// flush against the dialog's bottom edge.
const double _kActionBottomGap = 22;

/// Utility class for showing consistently themed date and time pickers
/// across the app. Matches the mobo sales app picker design.
class DatePickerUtils {
  /// Displays a themed Material date picker.
  static Future<DateTime?> showStandardDatePicker({
    required BuildContext context,
    DateTime? initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    String? helpText,
    String? cancelText,
    String? confirmText,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: firstDate ?? DateTime(2020),
      lastDate: lastDate ?? DateTime(2030),
      helpText: helpText,
      cancelText: cancelText,
      confirmText: confirmText,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: primaryColor,
              onPrimary: Colors.white,
              surface: isDark ? Colors.grey[850] : Colors.white,
              onSurface: isDark ? Colors.white : Colors.black,
              surfaceContainerHighest: isDark
                  ? Colors.grey[800]
                  : Colors.grey[100],
              onSurfaceVariant: isDark ? Colors.grey[300] : Colors.grey[700],
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: primaryColor,
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
                padding: const EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  _kActionBottomGap,
                ),
              ),
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: isDark ? Colors.grey[850] : Colors.white,
              headerBackgroundColor: primaryColor,
              headerForegroundColor: Colors.white,
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return Colors.white;
                return isDark ? Colors.white : Colors.black;
              }),
              dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return primaryColor;
                return Colors.transparent;
              }),
              todayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return Colors.white;
                return primaryColor;
              }),
              todayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return primaryColor;
                return Colors.transparent;
              }),
              todayBorder: BorderSide(color: primaryColor, width: 1),
              yearForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return Colors.white;
                return isDark ? Colors.white : Colors.black;
              }),
              yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return primaryColor;
                return Colors.transparent;
              }),
              rangePickerBackgroundColor: isDark
                  ? Colors.grey[850]
                  : Colors.white,
              rangePickerHeaderBackgroundColor: primaryColor,
              rangePickerHeaderForegroundColor: Colors.white,
              rangeSelectionBackgroundColor: primaryColor.withValues(
                alpha: 0.1,
              ),
              rangeSelectionOverlayColor: WidgetStateProperty.all(
                primaryColor.withValues(alpha: 0.1),
              ),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: isDark ? Colors.grey[850] : Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
  }

  /// Displays a themed Material time picker, always in 12-hour AM/PM mode.
  static Future<TimeOfDay?> showStandardTimePicker({
    required BuildContext context,
    TimeOfDay? initialTime,
    String? helpText,
    String? cancelText,
    String? confirmText,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return showTimePicker(
      context: context,
      initialTime: initialTime ?? TimeOfDay.now(),
      helpText: helpText,
      cancelText: cancelText,
      confirmText: confirmText,
      errorInvalidText: 'Hour 1–12, minute 0–59',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: primaryColor,
              onPrimary: Colors.white,
              surface: isDark ? Colors.grey[850] : Colors.white,
              onSurface: isDark ? Colors.white : Colors.black,
              surfaceContainerHighest: isDark
                  ? Colors.grey[800]
                  : Colors.grey[100],
              onSurfaceVariant: isDark ? Colors.grey[300] : Colors.grey[700],
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: primaryColor,
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
                padding: const EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  _kActionBottomGap,
                ),
              ),
            ),

            textSelectionTheme: TextSelectionThemeData(
              cursorColor: primaryColor,
              selectionColor: primaryColor.withValues(alpha: 0.25),
              selectionHandleColor: primaryColor,
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: isDark ? Colors.grey[850] : Colors.white,

              hourMinuteTextColor: WidgetStateColor.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return isDark ? Colors.white : Colors.black;
                }
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return isDark ? Colors.white : Colors.black;
              }),

              hourMinuteColor: WidgetStateColor.resolveWith((states) {
                if (states.contains(WidgetState.focused)) {
                  return isDark ? Colors.grey[800]! : Colors.grey[100]!;
                }
                if (states.contains(WidgetState.selected)) {
                  return primaryColor;
                }
                return isDark ? Colors.grey[800]! : Colors.grey[100]!;
              }),
              dayPeriodTextColor: WidgetStateColor.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return isDark ? Colors.white70 : Colors.black54;
              }),
              dayPeriodColor: WidgetStateColor.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.black;
                }
                return isDark ? Colors.grey[800]! : Colors.grey[100]!;
              }),
              dialHandColor: primaryColor,
              dialBackgroundColor: isDark ? Colors.grey[800] : Colors.grey[100],
              dialTextColor: WidgetStateColor.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return isDark ? Colors.white : Colors.black;
              }),
              entryModeIconColor: isDark ? Colors.white : Colors.black,
              hourMinuteTextStyle: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
              dayPeriodTextStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: isDark ? Colors.grey[850] : Colors.white,
            ),
          ),

          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
            child: child!,
          ),
        );
      },
    );
  }
}
