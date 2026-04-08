import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odoo_delivery_app/NavBars/ReturnManagement/services/odoo_return_service.dart';

class MockOdooReturnManagementService extends Mock
    implements OdooReturnManagementService {}

void main() {
  late MockOdooReturnManagementService service;

  setUp(() {
    service = MockOdooReturnManagementService();
    registerFallbackValue(0);
    registerFallbackValue(<List<Object>>[]);
  });

  group('OdooReturnManagementService', () {

    /// POSITIVE CASE - createReturn
    group('createReturn', () {
      test('completes successfully when valid return lines provided',
              () async {
            when(
                  () => service.createReturn(
                any(),
                any(),
              ),
            ).thenAnswer((_) async {});

            await service.createReturn(
              10,
              [
                [1, 2.0],
              ],
            );

            verify(
                  () => service.createReturn(
                10,
                [
                  [1, 2.0],
                ],
              ),
            ).called(1);
          });

      /// EDGE CASE - createReturn
      test('throws exception when returnLines is empty', () async {
        when(
              () => service.createReturn(
            any(),
            any(),
          ),
        ).thenThrow(Exception('No quantity specified for return.'));

        expect(
              () => service.createReturn(20, []),
          throwsException,
        );
      });

      /// NEGATIVE CASE - createReturn
      test('throws exception when API fails', () async {
        when(
              () => service.createReturn(
            any(),
            any(),
          ),
        ).thenThrow(Exception('Failed to create return'));

        expect(
              () => service.createReturn(
            30,
            [
              [2, 5.0],
            ],
          ),
          throwsException,
        );
      });
    });
  });
}
