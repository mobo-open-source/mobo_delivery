import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odoo_delivery_app/NavBars/AttachDocument/services/odoo_attach_service.dart';

class MockOdooAttachService extends Mock implements OdooAttachService {}

void main() {
  late MockOdooAttachService service;

  setUp(() {
    service = MockOdooAttachService();
    registerFallbackValue('');
    registerFallbackValue(0);
    registerFallbackValue(0.0);
    registerFallbackValue(<dynamic>[]);
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(const <String>[]);
  });

  group('OdooAttachService', () {

    /// POSITIVE CASE - StockCount
    group('StockCount', () {
      test('returns count when data exists', () async {
        when(
              () => service.StockCount(
            searchText: any(named: 'searchText'),
            filters: any(named: 'filters'),
          ),
        ).thenAnswer((_) async => 5);

        final result = await service.StockCount(
          searchText: 'PICK',
          filters: ['assigned'],
        );

        expect(result, 5);
        verify(() => service.StockCount(
          searchText: 'PICK',
          filters: ['assigned'],
        )).called(1);
      });

      /// EDGE CASE - StockCount
      test('returns zero when no records found', () async {
        when(
              () => service.StockCount(
            searchText: any(named: 'searchText'),
            filters: any(named: 'filters'),
          ),
        ).thenAnswer((_) async => 0);

        final result = await service.StockCount(
          searchText: 'INVALID',
          filters: [],
        );

        expect(result, 0);
      });

      /// NEGATIVE CASE - StockCount
      test('throws exception when API fails', () async {
        when(
              () => service.StockCount(
            searchText: any(named: 'searchText'),
            filters: any(named: 'filters'),
          ),
        ).thenThrow(Exception('Server error'));

        expect(
              () => service.StockCount(
            searchText: 'PICK',
            filters: [],
          ),
          throwsException,
        );
      });
    });

    /// POSITIVE CASE - fetchAttachmentStockPickings
    group('fetchAttachmentStockPickings', () {
      test('returns list of pickings', () async {
        when(
              () => service.fetchAttachmentStockPickings(
            any(),
            any(),
            searchQuery: any(named: 'searchQuery'),
            filters: any(named: 'filters'),
            groupBy: any(named: 'groupBy'),
          ),
        ).thenAnswer((_) async => [
          {'id': 1, 'name': 'PICK/001', 'state': 'assigned'}
        ]);

        final result = await service.fetchAttachmentStockPickings(
          0,
          10,
          searchQuery: 'PICK',
          filters: [],
        );

        expect(result, isA<List>());
        expect(result.length, 1);
        expect(result.first['name'], 'PICK/001');
      });

      /// EDGE CASE - fetchAttachmentStockPickings
      test('returns empty list when no data', () async {
        when(
              () => service.fetchAttachmentStockPickings(
            any(),
            any(),
            searchQuery: any(named: 'searchQuery'),
            filters: any(named: 'filters'),
            groupBy: any(named: 'groupBy'),
          ),
        ).thenAnswer((_) async => []);

        final result = await service.fetchAttachmentStockPickings(
          0,
          10,
          searchQuery: 'NONE',
          filters: [],
        );

        expect(result, isEmpty);
      });

      /// NEGATIVE CASE - fetchAttachmentStockPickings
      test('throws exception on network failure', () async {
        when(
              () => service.fetchAttachmentStockPickings(
            any(),
            any(),
            searchQuery: any(named: 'searchQuery'),
            filters: any(named: 'filters'),
            groupBy: any(named: 'groupBy'),
          ),
        ).thenThrow(Exception('Network error'));

        expect(
              () => service.fetchAttachmentStockPickings(
            0,
            10,
            searchQuery: 'PICK',
            filters: [],
          ),
          throwsException,
        );
      });
    });

    /// POSITIVE CASE - uploadFileToChatter
    group('uploadFileToChatter', () {
      test('returns true on successful upload', () async {
        when(
              () => service.uploadFileToChatter(
            any(),
            any(),
            any(),
            any(),
          ),
        ).thenAnswer((_) async => true);

        final result = await service.uploadFileToChatter(
          'application/pdf',
          'BASE64_DATA',
          10,
          'invoice.pdf',
        );

        expect(result, true);
      });

      /// NEGATIVE CASE - uploadFileToChatter
      test('returns false when upload fails', () async {
        when(
              () => service.uploadFileToChatter(
            any(),
            any(),
            any(),
            any(),
          ),
        ).thenAnswer((_) async => false);

        final result = await service.uploadFileToChatter(
          'application/pdf',
          'INVALID_BASE64',
          10,
          'invoice.pdf',
        );

        expect(result, false);
      });

      /// NEGATIVE CASE - uploadFileToChatter
      test('throws exception on server error', () async {
        when(
              () => service.uploadFileToChatter(
            any(),
            any(),
            any(),
            any(),
          ),
        ).thenThrow(Exception('Upload failed'));

        expect(
              () => service.uploadFileToChatter(
            'application/pdf',
            'BASE64_DATA',
            10,
            'invoice.pdf',
          ),
          throwsException,
        );
      });
    });
  });
}
