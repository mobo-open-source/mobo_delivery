import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_delivery_app/shared/utils/server_url_utils.dart';

void main() {
  group('normalizeServerUrl', () {
    test('the same server saved different ways collapses to one string', () {
      const canonical = 'https://srv.example.com';
      for (final variant in [
        'srv.example.com',
        'srv.example.com/',
        ' srv.example.com ',
        'https://srv.example.com',
        'https://srv.example.com/',
        'https://srv.example.com///',
        'https://SRV.Example.com',
        'HTTPS://srv.example.com',
      ]) {
        expect(normalizeServerUrl(variant), canonical, reason: variant);
      }
    });

    test('http is preserved, not forced to https', () {
      expect(
        normalizeServerUrl('http://srv.example.com/'),
        'http://srv.example.com',
      );
    });

    test('port and path survive; path case is not touched', () {
      expect(
        normalizeServerUrl('srv.example.com:8069'),
        'https://srv.example.com:8069',
      );
      // Some reverse proxies mount Odoo under a case-sensitive segment.
      expect(
        normalizeServerUrl('https://srv.example.com/Odoo/'),
        'https://srv.example.com/Odoo',
      );
    });

    test(
      'empty and null are left alone rather than becoming a bare scheme',
      () {
        expect(normalizeServerUrl(''), '');
        expect(normalizeServerUrl('   '), '');
        expect(normalizeServerUrl(null), '');
      },
    );

    test('different servers never collapse together', () {
      expect(
        normalizeServerUrl('a.example.com') ==
            normalizeServerUrl('b.example.com'),
        isFalse,
      );
      expect(
        normalizeServerUrl('srv.example.com:8069') ==
            normalizeServerUrl('srv.example.com:8070'),
        isFalse,
      );
    });
  });
}
