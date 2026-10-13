import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_delivery_app/NavBars/ReturnManagement/services/odoo_return_service.dart';
import 'package:odoo_delivery_app/shared/utils/odoo_version.dart';

void main() {
  group('stockMoveUomField', () {
    test('is product_uom up to Odoo 19', () {
      for (final major in [14, 15, 16, 17, 18, 19]) {
        expect(stockMoveUomField(major), 'product_uom', reason: 'v$major');
      }
    });

    test('is uom_id from Odoo 20', () {
      expect(stockMoveUomField(20), 'uom_id');
      expect(stockMoveUomField(21), 'uom_id');
    });

    test('an unknown version keeps the long-standing name', () {
      expect(stockMoveUomField(0), 'product_uom');
    });
  });

  group('odooUsesReturnWizard', () {
    test('every version that ships the wizard uses it', () {
      for (final major in [14, 16, 17, 18, 19]) {
        expect(odooUsesReturnWizard(major), isTrue, reason: 'v$major');
      }
    });

    test('Odoo 20 removed the wizard', () {
      expect(odooUsesReturnWizard(20), isFalse);
      expect(odooUsesReturnWizard(21), isFalse);
    });

    test('an unknown version is treated as pre-20', () {
      expect(odooUsesReturnWizard(0), isTrue);
    });
  });

  group('odooReadGroupReturnsTuples', () {
    test('dicts up to 19, tuples from 20', () {
      expect(odooReadGroupReturnsTuples(19), isFalse);
      expect(odooReadGroupReturnsTuples(20), isTrue);
      expect(odooReadGroupReturnsTuples(0), isFalse);
    });
  });

  group('returnableLinesFromMoves', () {
    List<Map> move(int id, double qty, {List<int> dests = const []}) => [
      {
        'id': id,
        'product_id': [7, 'Widget'],
        'quantity': qty,
        'uom_id': [1, 'Units'],
        'move_dest_ids': dests,
      },
    ];

    test('a line never returned is returnable in full', () {
      final lines = returnableLinesFromMoves(
        moves: move(10, 5),
        destinationMoves: const [],
        uomField: 'uom_id',
      );
      expect(lines, hasLength(1));
      expect(lines.single['quantity'], 5);
      expect(lines.single['move_id'], 10);
      expect(lines.single['uom_id'], [1, 'Units']);
    });

    test('an earlier return is subtracted', () {
      final lines = returnableLinesFromMoves(
        moves: move(10, 5, dests: [99]),
        destinationMoves: [
          {
            'origin_returned_move_id': [10, 'WH/OUT/1'],
            'quantity': 2.0,
          },
        ],
        uomField: 'uom_id',
      );
      expect(lines.single['quantity'], 3);
    });

    test('several partial returns accumulate', () {
      final lines = returnableLinesFromMoves(
        moves: move(10, 10, dests: [98, 99]),
        destinationMoves: [
          {
            'origin_returned_move_id': [10, 'r1'],
            'quantity': 3.0,
          },
          {
            'origin_returned_move_id': [10, 'r2'],
            'quantity': 4.0,
          },
        ],
        uomField: 'uom_id',
      );
      expect(lines.single['quantity'], 3);
    });

    test('a fully returned line is omitted, not shown as zero', () {
      final lines = returnableLinesFromMoves(
        moves: move(10, 5, dests: [99]),
        destinationMoves: [
          {
            'origin_returned_move_id': [10, 'r'],
            'quantity': 5.0,
          },
        ],
        uomField: 'uom_id',
      );
      expect(lines, isEmpty);
    });

    test('over-returning never yields a negative line', () {
      final lines = returnableLinesFromMoves(
        moves: move(10, 5, dests: [99]),
        destinationMoves: [
          {
            'origin_returned_move_id': [10, 'r'],
            'quantity': 8.0,
          },
        ],
        uomField: 'uom_id',
      );
      expect(lines, isEmpty);
    });

    test('a destination move belonging to another line is not subtracted', () {
      final lines = returnableLinesFromMoves(
        moves: move(10, 5, dests: [99]),
        destinationMoves: [
          {
            'origin_returned_move_id': [11, 'other'],
            'quantity': 5.0,
          },
          // An onward move that is not a return at all.
          {'origin_returned_move_id': false, 'quantity': 5.0},
        ],
        uomField: 'uom_id',
      );
      expect(lines.single['quantity'], 5);
    });

    test('reads whichever UoM field the server uses', () {
      final legacy = [
        {
          'id': 1,
          'product_id': [7, 'W'],
          'quantity': 2.0,
          'product_uom': [3, 'Dozen'],
        },
      ];
      final lines = returnableLinesFromMoves(
        moves: legacy,
        destinationMoves: const [],
        uomField: 'product_uom',
      );
      expect(lines.single['uom_id'], [3, 'Dozen']);
    });
  });

  group('returnQuantitiesByMoveId', () {
    test('reads the sheet create commands', () {
      final wanted = returnQuantitiesByMoveId([
        [
          0,
          0,
          {'product_id': 7, 'quantity': 2.0, 'move_id': 10},
        ],
        [
          0,
          0,
          {'product_id': 8, 'quantity': 1.0, 'move_id': 11},
        ],
      ]);
      expect(wanted, {10: 2.0, 11: 1.0});
    });

    test('accepts a Many2one pair for move_id', () {
      final wanted = returnQuantitiesByMoveId([
        [
          0,
          0,
          {
            'quantity': 2.0,
            'move_id': [10, 'WH/OUT/1'],
          },
        ],
      ]);
      expect(wanted, {10: 2.0});
    });

    test('drops zero, negative and unusable lines', () {
      final wanted = returnQuantitiesByMoveId([
        [
          0,
          0,
          {'quantity': 0.0, 'move_id': 10},
        ],
        [
          0,
          0,
          {'quantity': -1.0, 'move_id': 11},
        ],
        [
          0,
          0,
          {'quantity': 1.0, 'move_id': false},
        ],
      ]);
      expect(wanted, isEmpty);
    });

    test('sums repeats for the same move', () {
      final wanted = returnQuantitiesByMoveId([
        [
          0,
          0,
          {'quantity': 2.0, 'move_id': 10},
        ],
        [
          0,
          0,
          {'quantity': 3.0, 'move_id': 10},
        ],
      ]);
      expect(wanted, {10: 5.0});
    });
  });

  group('firstOdooId', () {
    test('reads bare ids, Many2one pairs, and false', () {
      expect(firstOdooId(5), 5);
      expect(firstOdooId([5, 'Name']), 5);
      expect(firstOdooId(false), isNull);
      expect(firstOdooId(null), isNull);
      expect(firstOdooId(const []), isNull);
    });
  });
}
