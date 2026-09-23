import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_delivery_app/NavBars/Home/widgets/section_error_state.dart';

void main() {
  group('homeSectionNeedsReLogin', () {
    test('offers re-login when a section fails while online', () {
      expect(
        homeSectionNeedsReLogin(
          online: true,
          error: 'OdooException: {message: Odoo Server Error}',
        ),
        isTrue,
      );
      expect(
        homeSectionNeedsReLogin(
          online: true,
          error: 'Your session has expired. Please sign in again.',
        ),
        isTrue,
      );
    });

    test('never offers it while offline', () {
      // Logging out clears the cache the user is relying on offline, and a
      // connection they do not have is not fixed by signing in again.
      expect(
        homeSectionNeedsReLogin(online: false, error: 'anything at all'),
        isFalse,
      );
    });

    test('not offered when the section loaded fine', () {
      expect(homeSectionNeedsReLogin(online: true, error: null), isFalse);
      expect(homeSectionNeedsReLogin(online: true, error: ''), isFalse);
    });
  });

  group('homeSectionErrorMessage', () {
    test('an expired session is named, not blamed on the connection', () {
      expect(
        homeSectionErrorMessage(
          online: true,
          error: 'Your session has expired. Please sign in again.',
          offlineDetail: 'x',
          genericDetail: 'y',
        ),
        contains('log out and sign in again'),
      );
    });

    test('offline takes precedence over everything', () {
      expect(
        homeSectionErrorMessage(
          online: false,
          error: 'Your session has expired.',
          offlineDetail: 'Counts need network.',
          genericDetail: 'y',
        ),
        startsWith('No internet connection.'),
      );
    });
  });
}
