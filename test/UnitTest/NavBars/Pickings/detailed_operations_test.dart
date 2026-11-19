import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_delivery_app/NavBars/Pickings/PickingFormPage/models/detailed_operations.dart';

/// The Detailed Operations screen writes exactly what Odoo's own screen
/// writes. These pin the parts that decide what reaches Odoo.
void main() {
  group('Pick From values match Odoo _copy_quant_info', () {
    test('a quant with lot, package and owner copies all four', () {
      final quant = PickFromOption.fromJson({
        'id': 7,
        'location_id': [8, 'WH/Stock/Shelf 1'],
        'lot_id': [29, '0000000000029'],
        'package_id': [3, 'PACK0001'],
        'owner_id': [12, 'Azure Interior'],
        'available_quantity': 4.0,
      });
      expect(quant.lineValues, {
        'lot_id': 29,
        'location_id': 8,
        'package_id': 3,
        'owner_id': 12,
      });
    });

    test('Odoo false fields are written back as false, never as null', () {
      final quant = PickFromOption.fromJson({
        'id': 7,
        'location_id': [8, 'WH/Stock'],
        'lot_id': false,
        'package_id': false,
        'owner_id': false,
        'available_quantity': 10.0,
      });
      expect(quant.lineValues, {
        'lot_id': false,
        'location_id': 8,
        'package_id': false,
        'owner_id': false,
      });
      expect(quant.lotName, isNull);
      expect(quant.packageName, isNull);
    });

    test('matches only the stock a line already picks from', () {
      final line = DetailedLine.fromJson({
        'id': 1,
        'move_id': [5, 'move'],
        'product_id': [9, 'Drawer'],
        'location_id': [8, 'WH/Stock'],
        'lot_id': [29, '0000000000029'],
        'package_id': false,
        'owner_id': false,
        'quantity': 5.0,
      });
      PickFromOption quant(int lot) => PickFromOption.fromJson({
        'id': lot,
        'location_id': [8, 'WH/Stock'],
        'lot_id': [lot, 'L$lot'],
        'package_id': false,
        'owner_id': false,
        'available_quantity': 1.0,
      });
      expect(quant(29).matches(line), isTrue);
      expect(quant(30).matches(line), isFalse);
    });
  });

  group('default quantity follows stock.move.line._compute_quantity', () {
    test('takes what is still missing, capped by the stock there', () {
      expect(defaultLineQuantity(demand: 5, done: 2, available: 10), 3);
      expect(defaultLineQuantity(demand: 5, done: 2, available: 1), 1);
    });

    test('a fully done move falls back to the stock available', () {
      expect(defaultLineQuantity(demand: 5, done: 5, available: 4), 4);
    });

    test('never negative', () {
      expect(defaultLineQuantity(demand: 5, done: 0, available: -2), 0);
    });
  });

  group('which column Odoo shows comes from Odoo', () {
    DetailedMove move({
      required bool showQuant,
      required bool showLotsM2o,
      dynamic tracking = 'lot',
    }) => DetailedMove.fromJson({
      'id': 5,
      'product_id': [9, 'Drawer'],
      'location_id': [8, 'WH/Stock'],
      'product_uom_qty': 5.0,
      'quantity': 5.0,
      'has_tracking': tracking,
      'show_quant': showQuant,
      'show_lots_m2o': showLotsM2o,
    });

    test('Pick From wins over the lot column, as in Odoo', () {
      expect(move(showQuant: true, showLotsM2o: false).showLotPicker, isFalse);
    });

    test('lot column when Pick From is hidden and the product is tracked', () {
      expect(move(showQuant: false, showLotsM2o: true).showLotPicker, isTrue);
      expect(
        move(showQuant: false, showLotsM2o: true, tracking: 'none')
            .showLotPicker,
        isFalse,
      );
    });

    test('a false has_tracking reads as untracked', () {
      final m = move(showQuant: false, showLotsM2o: true, tracking: false);
      expect(m.hasTracking, 'none');
      expect(m.isTracked, isFalse);
    });
  });

  test('done and cancelled pickings are locked, as in Odoo', () {
    DetailedOperations ops(String state) => DetailedOperations(
      pickingState: state,
      companyId: 1,
      moves: const [],
      lines: const [],
    );
    for (final s in ['draft', 'waiting', 'confirmed', 'assigned']) {
      expect(ops(s).isEditable, isTrue, reason: s);
    }
    expect(ops('done').isEditable, isFalse);
    expect(ops('cancel').isEditable, isFalse);
  });
}
