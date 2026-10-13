import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_delivery_app/shared/services/odoo_defaults_service.dart';

void main() {
  group('usableDomain', () {
    test('a list domain is passed through', () {
      final raw = [
        ['all_group_ids', 'in', 12],
      ];
      expect(usableDomain(raw), same(raw));
    });

    test('an empty list is still a usable domain', () {
      expect(usableDomain(const []), isEmpty);
    });

    test('a string domain is refused', () {
      // Odoo returns this form for domains that reference other fields of the
      // open form. It means nothing outside that form, so it must not be sent.
      expect(usableDomain("[('company_id', '=', company_id)]"), isNull);
    });

    test('a missing or false domain is refused', () {
      expect(usableDomain(null), isNull);
      expect(usableDomain(false), isNull);
    });
  });

  group('parsePickingCreateDefaults', () {
    test('reads a many2one default sent as a bare id', () {
      final d = parsePickingCreateDefaults({'user_id': 7});
      expect(d.responsibleUserId, 7);
    });

    test('reads a many2one default sent as an id/name pair', () {
      final d = parsePickingCreateDefaults({
        'user_id': [7, 'Mitchell Admin'],
      });
      expect(d.responsibleUserId, 7);
    });

    test('false means no default, not user zero', () {
      expect(parsePickingCreateDefaults({'user_id': false}).responsibleUserId,
          isNull);
    });

    test('a field Odoo did not default is absent, not zero', () {
      final d = parsePickingCreateDefaults(const {});
      expect(d.responsibleUserId, isNull);
      expect(d.scheduledDateUtc, isNull);
      expect(d.shippingPolicy, isNull);
    });

    test('scheduled_date is read as the naive UTC Odoo sends', () {
      final d = parsePickingCreateDefaults({
        'scheduled_date': '2026-10-13 09:30:00',
      });
      expect(d.scheduledDateUtc, isNotNull);
      expect(d.scheduledDateUtc!.isUtc, isTrue);
      expect(d.scheduledDateUtc, DateTime.utc(2026, 10, 13, 9, 30));
    });

    test('an unparseable date is dropped rather than guessed', () {
      expect(
        parsePickingCreateDefaults({'scheduled_date': 'not a date'})
            .scheduledDateUtc,
        isNull,
      );
      expect(
        parsePickingCreateDefaults({'scheduled_date': false}).scheduledDateUtc,
        isNull,
      );
    });

    test('move_type is read when the server sends one', () {
      expect(
        parsePickingCreateDefaults({'move_type': 'one'}).shippingPolicy,
        'one',
      );
      expect(
        parsePickingCreateDefaults({'move_type': ''}).shippingPolicy,
        isNull,
      );
      expect(
        parsePickingCreateDefaults({'move_type': false}).shippingPolicy,
        isNull,
      );
    });

    test('a full response reads every field', () {
      final d = parsePickingCreateDefaults({
        'user_id': 2,
        'scheduled_date': '2026-01-02 03:04:05',
        'move_type': 'direct',
      });
      expect(d.responsibleUserId, 2);
      expect(d.scheduledDateUtc, DateTime.utc(2026, 1, 2, 3, 4, 5));
      expect(d.shippingPolicy, 'direct');
    });
  });
}
