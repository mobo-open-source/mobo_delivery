import 'package:flutter/material.dart';

/// Collection of reusable utility functions for formatting and data transformation.
///
/// Currently includes:
///   - Human-friendly date difference formatting (e.g. "Today", "in 3 days", "2 days ago")
///   - MIME type detection based on file extension
///
/// This class helps keep business/presentation logic clean by centralizing common
/// transformations used across multiple screens (especially in lists and file handling).
class Utils {
  /// Formats a date string into a user-friendly relative label with appropriate color.
  ///
  /// Returns a map containing:
  ///   - 'label': String like "Today", "in 2 days", "3 days ago"
  ///   - 'color': Suggested Color for text or badge (amber for today, red for overdue, black/grey otherwise)
  ///
  /// Handles parsing errors gracefully by returning the raw string with grey color.
  /// Assumes input is in ISO 8601 format (as typically returned by Odoo/JSON APIs).
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
  /// Supports common file types used in document/signature attachments:
  ///   - Images: jpg, jpeg, png
  ///   - Documents: pdf, doc, docx, xls, xlsx, txt
  ///
  /// Falls back to generic `application/octet-stream` for unknown extensions.
  /// Used when preparing base64-encoded files for upload to Odoo or other APIs.
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