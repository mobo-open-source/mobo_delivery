import 'package:flutter/material.dart';

/// Collection of reusable static utility methods for formatting and data handling.
///
/// Currently includes:
///   - Relative date formatting with color coding (e.g. "Today", "in 3 days", "2 days ago")
///   - MIME type detection from file extensions (for uploads/attachments)
///
/// These helpers keep UI and business logic clean by centralizing common transformations
/// used across multiple screens (especially lists, badges, file handling).
class Utils {
  /// Formats a date string into a human-friendly relative label with semantic color.
  ///
  /// Returns a map with:
  ///   - 'label': String like "Today", "in 2 days", "3 days ago"
  ///   - 'color': Suggested text/badge color (amber for today, red for overdue, black/grey otherwise)
  ///
  /// Handles parsing errors gracefully by returning the raw string with grey color.
  /// Assumes input is ISO 8601 (common in Odoo/JSON APIs).
  static Map<String, dynamic> getFormattedDateInfo(String dateStr) {
    try {
      final scheduled = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final scheduledDay = DateTime(scheduled.year, scheduled.month, scheduled.day);
      final diff = scheduledDay.difference(today).inDays;

      if (diff == 0) {
        return {'label': 'Today', 'color': Colors.amber[900]};
      } else if (diff > 0) {
        return {'label': 'in $diff day${diff > 1 ? 's' : ''}', 'color': Colors.black};
      } else {
        return {
          'label': '${diff.abs()} day${diff.abs() > 1 ? 's' : ''} ago',
          'color': Colors.red[300],
        };
      }
    } catch (_) {
      return {'label': dateStr, 'color': Colors.grey};
    }
  }

  /// Determines the MIME type of a file based on its extension.
  ///
  /// Supports common formats used in document/signature attachments:
  ///   - Images: jpg/jpeg, png
  ///   - Documents: pdf, doc/docx, xls/xlsx, txt
  ///
  /// Falls back to generic `application/octet-stream` for unknown extensions.
  /// Used when preparing base64 files for upload to Odoo or other APIs.
  static String getMimeType(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.ms-excel';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }
}