import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odoo_delivery_app/NavBars/OfflineSync/services/odoo_offline_service.dart';

class MockOdooOfflineSyncService extends Mock
    implements OdooOfflineSyncService {}

void main() {
  late MockOdooOfflineSyncService service;

  setUp(() {
    service = MockOdooOfflineSyncService();
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<dynamic>[]);
    registerFallbackValue('');
    registerFallbackValue(0);
  });

  group('OdooOfflineSyncService', () {

    group('validatePicking', () {

      /// POSITIVE CASE - validatePicking
      test('returns true when validation succeeds', () async {
        when(() => service.validatePicking(any()))
            .thenAnswer((_) async => true);

        final result = await service.validatePicking(10);

        expect(result, true);
        verify(() => service.validatePicking(10)).called(1);
      });

      /// NEGATIVE CASE - validatePicking
      test('throws exception when validation fails', () async {
        when(() => service.validatePicking(any()))
            .thenThrow(Exception('Validation failed'));

        expect(
              () => service.validatePicking(10),
          throwsException,
        );
      });
    });

    group('cancelPicking', () {

      /// POSITIVE CASE - cancelPicking
      test('returns true when cancellation succeeds', () async {
        when(() => service.cancelPicking(any()))
            .thenAnswer((_) async => true);

        final result = await service.cancelPicking(20);

        expect(result, true);
        verify(() => service.cancelPicking(20)).called(1);
      });

      /// NEGATIVE CASE - cancelPicking
      test('throws exception when cancellation fails', () async {
        when(() => service.cancelPicking(any()))
            .thenThrow(Exception('Cancel failed'));

        expect(
              () => service.cancelPicking(20),
          throwsException,
        );
      });
    });

    group('saveChanges', () {

      /// POSITIVE CASE - saveChanges
      test('returns true when update succeeds', () async {
        final updates = {
          'updates': {
            'partner_id': 1,
            'scheduled_date': '2026-01-23T12:00:00',
            'origin': 'PO001',
            'date_done': '2026-01-23 12:05:00',
            'move_type': 'direct',
            'user_id': 2,
          }
        };

        when(() => service.saveChanges(any(), any()))
            .thenAnswer((_) async => true);

        final result = await service.saveChanges(30, updates);

        expect(result, true);
        verify(() => service.saveChanges(30, updates)).called(1);
      });

      /// NEGATIVE CASE - saveChanges
      test('throws exception when update fails', () async {
        when(() => service.saveChanges(any(), any()))
            .thenThrow(Exception('Save failed'));

        expect(
              () => service.saveChanges(30, {}),
          throwsException,
        );
      });
    });

    group('productUpdates', () {

      /// POSITIVE CASE - productUpdates
      test('returns true when product update succeeds', () async {
        final updates = {
          'id': 1,
          'product_id': [10, 'Product A'],
          'quantity': 5,
        };

        when(() => service.productUpdates(
          any(),
          any(),
          any(),
          any(),
        )).thenAnswer((_) async => true);

        final result =
        await service.productUpdates(40, updates, 2, 3);

        expect(result, true);
        verify(() => service.productUpdates(40, updates, 2, 3))
            .called(1);
      });

      /// NEGATIVE CASE - productUpdates
      test('throws exception when product update fails', () async {
        when(() => service.productUpdates(
          any(),
          any(),
          any(),
          any(),
        )).thenThrow(Exception('Product update failed'));

        expect(
              () => service.productUpdates(40, {}, 2, 3),
          throwsException,
        );
      });
    });

    /// ensureOdooDateFormat
    group('ensureOdooDateFormat', () {
      test('returns same value if already Odoo format', () {
        when(() => service.ensureOdooDateFormat(any()))
            .thenReturn('2026-01-23 12:00:00');

        final result =
        service.ensureOdooDateFormat('2026-01-23 12:00:00');

        expect(result, '2026-01-23 12:00:00');
      });

      test('converts ISO date to Odoo format', () {
        when(() => service.ensureOdooDateFormat(any()))
            .thenReturn('2026-01-23 12:00:00');

        final result =
        service.ensureOdooDateFormat('2026-01-23T12:00:00');

        expect(result, '2026-01-23 12:00:00');
      });
    });

    group('createPicking', () {

      /// POSITIVE CASE - createPicking
      test('returns picking id on success', () async {
        when(() => service.createPicking(
          creates: any(named: 'creates'),
        )).thenAnswer((_) async => 100);

        final result = await service.createPicking(creates: {
          'partnerId': 1,
          'operationTypeId': 2,
          'scheduledDate': '2026-01-23 12:00:00',
          'origin': 'PO001',
          'moveType': 'direct',
          'userId': 3,
          'note': 'Test',
          'products': [],
        });

        expect(result, 100);
        verify(() => service.createPicking(
          creates: any(named: 'creates'),
        )).called(1);
      });

      /// NEGATIVE CASE - createPicking
      test('throws exception when creation fails', () async {
        when(() => service.createPicking(
          creates: any(named: 'creates'),
        )).thenThrow(Exception('Create failed'));

        expect(
              () => service.createPicking(creates: {}),
          throwsException,
        );
      });
    });
  });
}
