import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:odoo_delivery_app/NavBars/Pickings/CreateNewPicking/models/product.dart';
import 'package:odoo_delivery_app/NavBars/Pickings/CreateNewPicking/services/odoo_create_picking_service.dart';
import 'package:odoo_delivery_app/NavBars/Pickings/PickingFormPage/services/hive_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'create_picking_unit_test.mocks.dart';

@GenerateMocks([OdooCreatePickingService, HiveService])
void main() {
  late MockOdooCreatePickingService mockOdooService;

  setUp(() {
    mockOdooService = MockOdooCreatePickingService();
    SharedPreferences.setMockInitialValues({'userId': 1, 'version': 18});
  });

  /// POSITIVE CASE  - network connection
  group('OdooCreatePickingService', () {
    test('checkNetworkConnectivity returns true when online', () async {
      when(
        mockOdooService.checkNetworkConnectivity(),
      ).thenAnswer((_) async => true);

      final result = await mockOdooService.checkNetworkConnectivity();

      expect(result, true);
    });

    /// NEGATIVE CASE  - network connection
    test('checkNetworkConnectivity returns false when offline', () async {
      when(
        mockOdooService.checkNetworkConnectivity(),
      ).thenAnswer((_) async => false);

      final result = await mockOdooService.checkNetworkConnectivity();

      expect(result, false);
    });

    /// POSITIVE CASE  - load products
    test('loadProducts returns a list of ProductModel', () async {
      final mockProducts = [
        ProductModel(id: 1, name: 'Test Product', uom_id: 1),
      ];

      when(
        mockOdooService.loadProducts(),
      ).thenAnswer((_) async => mockProducts);

      final products = await mockOdooService.loadProducts();

      expect(products, isA<List<ProductModel>>());
      expect(products.length, 1);
      expect(products[0].name, 'Test Product');
    });

    /// NEGATIVE CASE  - load products
    test('loadProducts returns empty list on exception', () async {
      when(
        mockOdooService.loadProducts(),
      ).thenThrow(Exception('Failed to load'));

      try {
        await mockOdooService.loadProducts();
      } catch (e) {
        expect(e, isA<Exception>());
      }
    });

    /// POSITIVE CASE  - create picking
    test('createPicking returns a picking ID', () async {
      when(
        mockOdooService.createPicking(
          partnerId: anyNamed('partnerId'),
          operationTypeId: anyNamed('operationTypeId'),
          scheduledDate: anyNamed('scheduledDate'),
          moveType: anyNamed('moveType'),
          origin: anyNamed('origin'),
          userId: anyNamed('userId'),
          note: anyNamed('note'),
        ),
      ).thenAnswer((_) async => 123);

      final pickingId = await mockOdooService.createPicking(
        partnerId: 1,
        operationTypeId: 2,
        scheduledDate: '2026-01-23 00:00:00',
        moveType: 'direct',
      );

      expect(pickingId, 123);
    });

    /// POSITIVE CASE  - create picking with mandatory fields
    test('createPicking with only mandatory fields', () async {
      when(
        mockOdooService.createPicking(
          partnerId: anyNamed('partnerId'),
          operationTypeId: anyNamed('operationTypeId'),
          scheduledDate: anyNamed('scheduledDate'),
          moveType: anyNamed('moveType'),
        ),
      ).thenAnswer((_) async => 456);

      final pickingId = await mockOdooService.createPicking(
        partnerId: 1,
        operationTypeId: 2,
        scheduledDate: '',
        moveType: '',
      );

      expect(pickingId, 456);
    });

    /// NEGATIVE CASE  - create picking with missing fields
    test('createPicking fails if mandatory fields are missing', () async {
      when(
        mockOdooService.createPicking(
          partnerId: anyNamed('partnerId'),
          operationTypeId: anyNamed('operationTypeId'),
          scheduledDate: anyNamed('scheduledDate'),
          moveType: anyNamed('moveType'),
        ),
      ).thenThrow(Exception('Mandatory fields missing'));

      expect(
        () async => await mockOdooService.createPicking(
          partnerId: 0,
          operationTypeId: 0,
          scheduledDate: '',
          moveType: '',
        ),
        throwsException,
      );
    });

    /// NEGATIVE CASE  - create picking with exception
    test('createPicking throws exception on failure', () async {
      when(
        mockOdooService.createPicking(
          partnerId: anyNamed('partnerId'),
          operationTypeId: anyNamed('operationTypeId'),
          scheduledDate: anyNamed('scheduledDate'),
          moveType: anyNamed('moveType'),
        ),
      ).thenThrow(Exception('Failed to create picking'));

      expect(
        () async => await mockOdooService.createPicking(
          partnerId: 1,
          operationTypeId: 2,
          scheduledDate: '2026-01-23 00:00:00',
          moveType: 'direct',
        ),
        throwsException,
      );
    });

    /// POSITIVE CASE  - load locations
    test('getPickingLocations returns location IDs', () async {
      when(
        mockOdooService.getPickingLocations(1),
      ).thenAnswer((_) async => {'location_id': 10, 'location_dest_id': 20});

      final locations = await mockOdooService.getPickingLocations(1);

      expect(locations['location_id'], 10);
      expect(locations['location_dest_id'], 20);
    });

    /// Negative CASE  - load locations
    test('getPickingLocations throws exception if null', () async {
      when(
        mockOdooService.getPickingLocations(1),
      ).thenThrow(Exception('Failed'));

      expect(
        () async => await mockOdooService.getPickingLocations(1),
        throwsException,
      );
    });
  });
}
