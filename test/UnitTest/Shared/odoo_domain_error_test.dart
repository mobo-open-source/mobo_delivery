import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_delivery_app/shared/utils/odoo_domain_error.dart';

void main() {
  group('isUnsupportedDomainError', () {
    test('detects domains Odoo refuses to search', () {
      expect(
        isUnsupportedDomainError(
          'ValueError: Cannot convert stock.picking.return_count to SQL '
          'because it is not stored',
        ),
        isTrue,
      );
      expect(
        isUnsupportedDomainError(
          "ValueError: Domain() invalid item in domain: 'done'",
        ),
        isTrue,
      );
      expect(
        isUnsupportedDomainError(
          "ValueError: Invalid field 'mobile' on 'res.partner'",
        ),
        isTrue,
      );
      expect(
        isUnsupportedDomainError('Non-stored field x cannot be searched'),
        isTrue,
      );
    });

    test('does not claim unrelated failures are bad filters', () {
      // Dropping the user's filters for these would hide the real problem.
      expect(
        isUnsupportedDomainError(
          'odoo.exceptions.AccessError: Access to unauthorized or invalid '
          'companies.',
        ),
        isFalse,
      );
      expect(
        isUnsupportedDomainError(
          'ClientException with SocketException: Connection reset by peer',
        ),
        isFalse,
      );
      expect(
        isUnsupportedDomainError('OdooSessionExpiredException: session expired'),
        isFalse,
      );
    });
  });
}
