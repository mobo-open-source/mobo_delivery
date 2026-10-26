import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_delivery_app/NavBars/Pickings/PickingFormPage/models/picking_form.dart';

/// `stock.picking.backorder_id` — Odoo's "Back Order of" — is a readonly
/// Many2one that exists unchanged in Odoo 17, 18, 19 and 20, so the only
/// thing that can vary is the shape of the value Odoo sends back.
void main() {
  Map<String, dynamic> picking(Map<String, dynamic> extra) => {
        'id': 12,
        'name': 'WH/OUT/00013',
        'state': 'assigned',
        'return_count': 0,
        'show_check_availability': false,
        ...extra,
      };

  group('PickingForm.backorderId parsing', () {
    test('reads the [id, reference] pair Odoo sends for a backorder', () {
      final p = PickingForm.fromJson(
          picking({'backorder_id': [7, 'WH/OUT/00012']}));
      expect(p.backorderId, [7, 'WH/OUT/00012']);
    });

    test('is null when the picking is not a backorder (Odoo sends false)', () {
      final p = PickingForm.fromJson(picking({'backorder_id': false}));
      expect(p.backorderId, isNull);
    });

    test('is null when the field is absent entirely', () {
      final p = PickingForm.fromJson(picking({}));
      expect(p.backorderId, isNull);
    });

    test('survives a Hive round trip through toJson/fromJson', () {
      final original = PickingForm.fromJson(
          picking({'backorder_id': [7, 'WH/OUT/00012']}));
      final restored = PickingForm.fromJson(original.toJson());
      expect(restored.backorderId, [7, 'WH/OUT/00012']);
    });

    test('a picking cached before this field existed still parses', () {
      /// Old rows simply have no `backorder_id`; they must not throw, and
      /// must read as "not a backorder" rather than crashing the detail page.
      final p = PickingForm.fromJson(picking({'origin': 'SO0042'}));
      expect(p.backorderId, isNull);
      expect(p.name, 'WH/OUT/00013');
    });
  });

  group('reference extraction (what the detail row shows)', () {
    /// Mirrors the guard in PickingDetailsPage._backorderReference.
    String? reference(dynamic raw) {
      if (raw is! List || raw.length < 2) return null;
      final name = raw[1]?.toString();
      if (name == null || name.isEmpty || name.toLowerCase() == 'false') {
        return null;
      }
      return name;
    }

    test('returns the picking reference', () {
      expect(reference([7, 'WH/OUT/00012']), 'WH/OUT/00012');
    });

    test('returns null for every "not set" shape', () {
      expect(reference(false), isNull);
      expect(reference(null), isNull);
      expect(reference(const []), isNull);
      expect(reference([7]), isNull);
      expect(reference([7, '']), isNull);
      expect(reference([7, 'false']), isNull);
    });
  });
}
