import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/company/session/company_session_manager.dart';

class OdooDateTimeFormat {
  static const _kTimeFormatKey = 'odoo_time_format';
  static const _kDateFormatKey = 'odoo_date_format';

  static const _fallbackTimePattern = 'hh:mm a';
  static const _fallbackDatePattern = 'yyyy-MM-dd';

  static String? _cachedTimePattern;
  static String? _cachedDatePattern;
  static Future<void>? _inflight;

  static String get timePattern => _cachedTimePattern ?? _fallbackTimePattern;

  static String get datePattern => _cachedDatePattern ?? _fallbackDatePattern;

  static String get dateTimePattern => '$datePattern $timePattern';

  static Future<void> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedTimePattern = prefs.getString(_kTimeFormatKey);
    _cachedDatePattern = prefs.getString(_kDateFormatKey);
  }

  static Future<void> ensureFetched({bool force = false}) async {
    if (!force && _cachedTimePattern != null && _cachedDatePattern != null) {
      return;
    }
    _inflight ??= _fetchAndCache().whenComplete(() => _inflight = null);
    return _inflight;
  }

  static Future<void> _fetchAndCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userLang = prefs.getString('userLang') ?? 'en_US';

      final result = await CompanySessionManager.callKwWithCompany({
        'model': 'res.lang',
        'method': 'search_read',
        'args': [
          [
            ['code', '=', userLang],
          ],
        ],
        'kwargs': {
          'fields': ['time_format', 'date_format'],
          'limit': 1,
        },
      });

      if (result is! List || result.isEmpty) return;
      final row = result.first as Map<String, dynamic>;
      final rawTime = row['time_format']?.toString() ?? '';
      final rawDate = row['date_format']?.toString() ?? '';

      final timePattern = _strftimeToDartPattern(
        rawTime,
        fallback: _fallbackTimePattern,
      );
      final datePattern = _strftimeToDartPattern(
        rawDate,
        fallback: _fallbackDatePattern,
      );

      _cachedTimePattern = timePattern;
      _cachedDatePattern = datePattern;
      await prefs.setString(_kTimeFormatKey, timePattern);
      await prefs.setString(_kDateFormatKey, datePattern);
    } catch (_) {}
  }

  static String _strftimeToDartPattern(
    String pattern, {
    required String fallback,
  }) {
    if (pattern.isEmpty) return fallback;
    const map = <String, String>{
      '%Y': 'yyyy',
      '%y': 'yy',
      '%m': 'MM',
      '%d': 'dd',
      '%H': 'HH',
      '%I': 'hh',
      '%M': 'mm',
      '%S': 'ss',
      '%p': 'a',
      '%B': 'MMMM',
      '%b': 'MMM',
      '%A': 'EEEE',
      '%a': 'EEE',
      '%%': '%',
    };
    final buffer = StringBuffer();
    for (int i = 0; i < pattern.length; i++) {
      if (pattern[i] == '%' && i + 1 < pattern.length) {
        final token = pattern.substring(i, i + 2);
        if (map.containsKey(token)) {
          buffer.write(map[token]);
          i++;
          continue;
        }
      }
      buffer.write(pattern[i]);
    }
    final result = buffer.toString();
    return result.isEmpty ? fallback : result;
  }

  static String formatForDisplay(String? input) {
    if (input == null) return '';
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';

    final parsed = _parseSmart(trimmed);
    if (parsed == null) return trimmed;
    return DateFormat(dateTimePattern).format(parsed.toLocal());
  }

  static String toOdooStorage(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;
    final parsed = _parseSmart(trimmed);
    if (parsed == null) return trimmed;
    final utc = parsed.isUtc ? parsed : parsed.toUtc();
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(utc);
  }

  static DateTime? _parseSmart(String trimmed) {
    final odooStorage = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$');
    if (odooStorage.hasMatch(trimmed)) {
      try {
        final dt = DateFormat('yyyy-MM-dd HH:mm:ss').parseStrict(trimmed);
        return DateTime.utc(
          dt.year,
          dt.month,
          dt.day,
          dt.hour,
          dt.minute,
          dt.second,
        );
      } catch (_) {}
    }

    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return iso;

    for (final pattern in [
      dateTimePattern,
      'yyyy-MM-dd hh:mm a',
      'yyyy-MM-dd hh:mm:ss a',
      'yyyy-MM-dd HH:mm:ss',
      'yyyy-MM-dd HH:mm',
    ]) {
      try {
        return DateFormat(pattern).parseStrict(trimmed);
      } catch (_) {}
    }
    return null;
  }
}
