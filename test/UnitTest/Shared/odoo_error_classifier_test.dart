import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_delivery_app/shared/utils/odoo_error_classifier.dart';

void main() {
  group('isServerUnreachable', () {
    test('true for genuine transport failures', () {
      expect(
        OdooErrorClassifier.isServerUnreachable(
          'ClientException with SocketException: Connection reset by peer',
        ),
        isTrue,
      );
      expect(
        OdooErrorClassifier.isServerUnreachable(
          "SocketException: Failed host lookup: 'example.com'",
        ),
        isTrue,
      );
    });

    test('false for application errors wrapped in the Odoo envelope', () {
      // These are why the Home card told users to check a healthy server.
      expect(
        OdooErrorClassifier.isServerUnreachable(
          'OdooException: {code: 0, message: Odoo Server Error, data: {name: '
          'odoo.exceptions.AccessError, message: Access Denied}}',
        ),
        isFalse,
      );
      expect(
        OdooErrorClassifier.isServerUnreachable(
          'OdooException: {message: Odoo Server Error, data: {message: '
          'Cannot convert stock.picking.return_count to SQL}}',
        ),
        isFalse,
      );
    });

    test('false for a bare status-like number in ordinary data', () {
      // Record ids and amounts routinely contain 500.
      expect(
        OdooErrorClassifier.isServerUnreachable('Picking 500 has no moves'),
        isFalse,
      );
      expect(
        OdooErrorClassifier.isServerUnreachable(
          'HTTP 503 service unavailable',
        ),
        isTrue,
      );
    });

    test('a session failure is not reported as unreachable', () {
      expect(
        OdooErrorClassifier.isServerUnreachable(
          'Your session has expired. Please sign in again.',
        ),
        isFalse,
      );
    });
  });

  group('isSessionExpired', () {
    test('recognises the session failures the app can raise', () {
      expect(
        OdooErrorClassifier.isSessionExpired(
          'Your session has expired. Please sign in again.',
        ),
        isTrue,
      );
      expect(
        OdooErrorClassifier.isSessionExpired('Session is no longer valid.'),
        isTrue,
      );
      expect(
        OdooErrorClassifier.isSessionExpired('OdooSessionExpiredException'),
        isTrue,
      );
    });

    test('does not claim unrelated failures are session failures', () {
      expect(
        OdooErrorClassifier.isSessionExpired('SocketException: reset by peer'),
        isFalse,
      );
      expect(OdooErrorClassifier.isSessionExpired(null), isFalse);
    });
  });
}
