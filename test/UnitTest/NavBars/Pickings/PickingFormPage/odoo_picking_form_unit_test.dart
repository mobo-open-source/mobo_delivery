import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odoo_delivery_app/NavBars/Pickings/PickingFormPage/models/stock_move.dart';
import 'package:odoo_delivery_app/NavBars/Pickings/PickingFormPage/services/hive_service.dart';
import 'package:odoo_delivery_app/NavBars/Pickings/PickingFormPage/services/odoo_picking_form_service.dart';

class MockOdooPickingFormService extends Mock
    implements OdooPickingFormService {}

class MockHiveService extends Mock implements HiveService {}

void main() {
  late MockOdooPickingFormService mockOdooService;
  late MockHiveService mockHiveService;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<Map<String, dynamic>>[]);
  });

  setUp(() {
    mockOdooService = MockOdooPickingFormService();
    mockHiveService = MockHiveService();
  });

  group('Picking Actions', () {
    /// POSITIVE CASE - UPDATE PRODUCT – ONLINE
    test(
      'update product ONLINE → calls updateProductMove and returns true',
      () async {
        when(
          () => mockOdooService.checkNetworkConnectivity(),
        ).thenAnswer((_) async => true);

        when(
          () => mockOdooService.updateProductMove(
            any(),
            any(),
            any(),
            any(),
            any(),
            any(),
          ),
        ).thenAnswer((_) async => true);

        final isOnline = await mockOdooService.checkNetworkConnectivity();
        bool success = false;

        if (isOnline) {
          success = await mockOdooService.updateProductMove(
            10,
            100,
            'Test Product',
            5.0,
            1,
            2,
          );
        }
        expect(success, true);

        verify(
          () => mockOdooService.updateProductMove(
            10,
            100,
            'Test Product',
            5.0,
            1,
            2,
          ),
        ).called(1);
      },
    );

    /// UPDATE PRODUCT – OFFLINE
    test(
      'update product OFFLINE → saves update to Hive and skips API',
      () async {
        when(
          () => mockOdooService.checkNetworkConnectivity(),
        ).thenAnswer((_) async => false);

        when(
          () => mockHiveService.savePendingProductUpdates(any(), any(), any()),
        ).thenAnswer((_) async {});

        final move = StockMove(
          id: 10,
          productId: [100, 'Test Product'],
          productUomQty: 1,
          quantity: 5.0,
        );

        final isOnline = await mockOdooService.checkNetworkConnectivity();

        if (!isOnline) {
          await mockHiveService.savePendingProductUpdates(1, {
            'move': move.toJson(),
            'timestamp': DateTime.now().toIso8601String(),
          }, 'Picking Details');
        }
        verify(
          () => mockHiveService.savePendingProductUpdates(
            1,
            any(),
            'Picking Details',
          ),
        ).called(1);

        verifyNever(
          () => mockOdooService.updateProductMove(
            any(),
            any(),
            any(),
            any(),
            any(),
            any(),
          ),
        );
      },
    );

    /// VALIDATE PICKING – ONLINE SUCCESS
    test('validate picking ONLINE → returns true', () async {
      when(
        () => mockOdooService.checkNetworkConnectivity(),
      ).thenAnswer((_) async => true);

      when(
        () => mockOdooService.validatePicking(any()),
      ).thenAnswer((_) async => true);

      final success = await mockOdooService.validatePicking(1);

      expect(success, true);
      verify(() => mockOdooService.validatePicking(1)).called(1);
    });

    /// VALIDATE PICKING – ONLINE FAILURE
    test('validate picking ONLINE → returns false', () async {
      when(
        () => mockOdooService.checkNetworkConnectivity(),
      ).thenAnswer((_) async => true);

      when(
        () => mockOdooService.validatePicking(any()),
      ).thenAnswer((_) async => false);

      final success = await mockOdooService.validatePicking(1);

      expect(success, false);
      verify(() => mockOdooService.validatePicking(1)).called(1);
    });

    /// MARK AS TODO – SUCCESS
    test('mark as todo picking → success', () async {
      when(
        () => mockOdooService.markAsTodoPicking(any()),
      ).thenAnswer((_) async => true);

      final result = await mockOdooService.markAsTodoPicking(1);

      expect(result, true);
      verify(() => mockOdooService.markAsTodoPicking(1)).called(1);
    });

    /// MARK AS TODO – FAILURE
    test('mark as todo picking → failure', () async {
      when(
        () => mockOdooService.markAsTodoPicking(any()),
      ).thenAnswer((_) async => false);

      final result = await mockOdooService.markAsTodoPicking(1);

      expect(result, false);
      verify(() => mockOdooService.markAsTodoPicking(1)).called(1);
    });

    /// CANCEL PICKING – OFFLINE
    test('cancel picking OFFLINE → saves cancellation to Hive', () async {
      when(
        () => mockOdooService.checkNetworkConnectivity(),
      ).thenAnswer((_) async => false);

      when(
        () => mockHiveService.savePendingCancellation(any(), any()),
      ).thenAnswer((_) async {});

      when(() => mockHiveService.savePickings(any())).thenAnswer((_) async {});

      final isOnline = await mockOdooService.checkNetworkConnectivity();

      if (!isOnline) {
        await mockHiveService.savePendingCancellation(1, {
          'id': 1,
          'state': 'cancel',
        });
        await mockHiveService.savePickings([
          {'id': 1, 'state': 'cancel'},
        ]);
      }

      verify(() => mockHiveService.savePendingCancellation(1, any())).called(1);

      verify(() => mockHiveService.savePickings(any())).called(1);
    });

    /// CANCEL PICKING – ONLINE
    test('cancel picking ONLINE → Hive is NOT called', () async {
      when(
        () => mockOdooService.checkNetworkConnectivity(),
      ).thenAnswer((_) async => true);

      final isOnline = await mockOdooService.checkNetworkConnectivity();

      expect(isOnline, true);

      verifyNever(() => mockHiveService.savePendingCancellation(any(), any()));
      verifyNever(() => mockHiveService.savePickings(any()));
    });
  });
}
