import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_delivery_app/LoginPage/services/auth_service.dart';

void main() {
  group('resumedSessionMismatch', () {
    test('a session for the right account resumes', () {
      expect(
        resumedSessionMismatch(
          sessionInfo: {'db': 'mobo', 'username': 'demo', 'uid': 2},
          expectedDatabase: 'mobo',
          expectedLogin: 'demo',
        ),
        isNull,
      );
    });

    test('a session for another database on the same server is refused', () {
      final reason = resumedSessionMismatch(
        sessionInfo: {'db': 'mobo2', 'username': 'demo', 'uid': 2},
        expectedDatabase: 'mobo',
        expectedLogin: 'demo',
      );
      expect(reason, isNotNull);
      expect(reason, contains('mobo2'));
    });

    test('a session for a different user is refused', () {
      final reason = resumedSessionMismatch(
        sessionInfo: {'db': 'mobo', 'username': 'mitchel', 'uid': 7},
        expectedDatabase: 'mobo',
        expectedLogin: 'demo',
      );
      expect(reason, isNotNull);
      expect(reason, contains('mitchel'));
    });

    test('login comparison ignores case', () {
      expect(
        resumedSessionMismatch(
          sessionInfo: {'db': 'mobo', 'username': 'Demo'},
          expectedDatabase: 'mobo',
          expectedLogin: 'demo',
        ),
        isNull,
      );
    });

    test('fields the server did not send never block a resume', () {
      expect(
        resumedSessionMismatch(
          sessionInfo: {'uid': 2},
          expectedDatabase: 'mobo',
          expectedLogin: 'demo',
        ),
        isNull,
      );
      expect(
        resumedSessionMismatch(
          sessionInfo: {'db': null, 'username': null},
          expectedDatabase: 'mobo',
          expectedLogin: 'demo',
        ),
        isNull,
      );
    });
  });
}
