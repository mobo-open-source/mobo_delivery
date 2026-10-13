import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_delivery_app/core/session/database_expiry.dart';

void main() {
  group('DatabaseExpiredException', () {
    test('names the subscription, not the connection', () {
      expect(
        DatabaseExpiredException.message,
        contains('database has expired'),
      );
      expect(DatabaseExpiredException.message, contains('subscription'));
    });
  });

  group('isExpiredDate', () {
    // The exact value the tester's server reports, confirmed in its web
    // console: `expiration_date` = 2026-10-04 08:39:25.
    const serverValue = '2026-10-04 08:39:25';

    test('a date already past is expired', () {
      expect(
        DatabaseExpiry.isExpiredDate(
          serverValue,
          now: DateTime.utc(2026, 10, 12, 9),
        ),
        isTrue,
      );
    });

    test('the same date is not expired before it arrives', () {
      expect(
        DatabaseExpiry.isExpiredDate(
          serverValue,
          now: DateTime.utc(2026, 9, 20),
        ),
        isFalse,
      );
    });

    test('rounds to whole days, matching the Odoo web client', () {
      // A few hours past expiry still rounds to zero days left, so the app
      // and the browser agree on the last usable day.
      expect(
        DatabaseExpiry.isExpiredDate(
          serverValue,
          now: DateTime.utc(2026, 10, 4, 14),
        ),
        isTrue,
      );
    });

    test('an ISO form is read the same way', () {
      expect(
        DatabaseExpiry.isExpiredDate(
          '2026-10-04T08:39:25',
          now: DateTime.utc(2026, 10, 12),
        ),
        isTrue,
      );
    });

    test('a date-only value is accepted', () {
      expect(
        DatabaseExpiry.isExpiredDate(
          '2026-10-04',
          now: DateTime.utc(2026, 10, 12),
        ),
        isTrue,
      );
    });

    test('no date means not expired', () {
      // On-premise databases carry no expiry, and a failed read returns null.
      expect(DatabaseExpiry.isExpiredDate(null), isFalse);
      expect(DatabaseExpiry.isExpiredDate(''), isFalse);
      expect(DatabaseExpiry.isExpiredDate('   '), isFalse);
      expect(DatabaseExpiry.isExpiredDate('not a date'), isFalse);
    });
  });

  group('isExpired', () {
    test('an empty session is never treated as expired', () async {
      // Locking someone out because there was nothing to check would be
      // worse than letting an expired database through.
      expect(
        await DatabaseExpiry.isExpired(serverUrl: '', sessionId: ''),
        isFalse,
      );
      expect(
        await DatabaseExpiry.isExpired(
          serverUrl: 'https://example.com',
          sessionId: '',
        ),
        isFalse,
      );
    });

    test('an unreachable server is not treated as expired', () async {
      expect(
        await DatabaseExpiry.isExpired(
          serverUrl: 'http://127.0.0.1:1',
          sessionId: 'nonexistent-session',
        ),
        isFalse,
      );
    });
  });
}
