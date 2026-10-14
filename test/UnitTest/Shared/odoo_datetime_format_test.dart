import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:odoo_delivery_app/shared/utils/odoo_datetime_format.dart';

void main() {
  group('tryToOdooStorage', () {
    test('a local time is converted to UTC, not relabelled', () {
      // The bug this covers: the create form used to format the operator's
      // wall clock and send it as though it were already UTC.
      final local = DateTime(2026, 10, 14, 15, 30);
      final display = OdooDateTimeFormat.formatLocalForDisplay(local);

      final stored = OdooDateTimeFormat.tryToOdooStorage(display);
      expect(stored, isNotNull);

      final expected = DateFormat('yyyy-MM-dd HH:mm:ss').format(local.toUtc());
      expect(stored, expected);
    });

    test('round-trips through display and back unchanged', () {
      final local = DateTime(2026, 1, 2, 8, 5);
      final once = OdooDateTimeFormat.tryToOdooStorage(
        OdooDateTimeFormat.formatLocalForDisplay(local),
      );
      final twice = OdooDateTimeFormat.tryToOdooStorage(
        OdooDateTimeFormat.formatForDisplay(once),
      );
      expect(twice, once);
    });

    test('a value already in Odoo storage form is left in UTC', () {
      expect(
        OdooDateTimeFormat.tryToOdooStorage('2026-10-14 09:30:00'),
        '2026-10-14 09:30:00',
      );
    });

    test('unreadable input returns null so the caller can substitute', () {
      expect(OdooDateTimeFormat.tryToOdooStorage('not a date'), isNull);
      expect(OdooDateTimeFormat.tryToOdooStorage(''), isNull);
      expect(OdooDateTimeFormat.tryToOdooStorage('   '), isNull);
    });
  });

  group('nowForStorage', () {
    test('is UTC in the shape Odoo stores', () {
      final stored = OdooDateTimeFormat.nowForStorage();
      expect(
        RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$').hasMatch(stored),
        isTrue,
      );

      // The stored string is naive UTC, so it needs the 'Z' to parse as UTC
      // rather than as this machine's local time.
      final parsed = DateTime.parse('${stored.replaceFirst(' ', 'T')}Z');
      final nowUtc = DateTime.now().toUtc();
      expect(parsed.difference(nowUtc).inMinutes.abs(), lessThan(2));
    });
  });

  group('formatLocalForDisplay', () {
    test('shows a UTC instant in local time', () {
      final utc = DateTime.utc(2026, 10, 14, 9, 30);
      final shown = OdooDateTimeFormat.formatLocalForDisplay(utc);
      final expected = DateFormat(
        OdooDateTimeFormat.dateTimePattern,
      ).format(utc.toLocal());
      expect(shown, expected);
    });
  });

  group('parseToLocal', () {
    test('an Odoo storage value is read as UTC, then localised', () {
      final parsed = OdooDateTimeFormat.parseToLocal('2026-10-14 09:30:00');
      expect(parsed, isNotNull);
      expect(parsed, DateTime.utc(2026, 10, 14, 9, 30).toLocal());
    });

    test('the day can differ from the raw string, which is the point', () {
      // 19:00 UTC on the 14th is already the 15th in IST. Reading the string
      // as local time would label this "Today" on the wrong day.
      final parsed = OdooDateTimeFormat.parseToLocal('2026-10-14 19:00:00')!;
      final asUtcInstant = DateTime.utc(2026, 10, 14, 19);
      expect(parsed.isAtSameMomentAs(asUtcInstant), isTrue);
    });

    test('unreadable input returns null rather than a wrong date', () {
      expect(OdooDateTimeFormat.parseToLocal(null), isNull);
      expect(OdooDateTimeFormat.parseToLocal(''), isNull);
      expect(OdooDateTimeFormat.parseToLocal('   '), isNull);
      expect(OdooDateTimeFormat.parseToLocal('not a date'), isNull);
    });
  });
}
