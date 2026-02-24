import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odoo_delivery_app/NavBars/PickingNotes/services/odoo_picking_note_service.dart';

class MockOdooPickingNoteService extends Mock
    implements OdooPickingNoteService {}

void main() {
  late MockOdooPickingNoteService service;

  setUp(() {
    service = MockOdooPickingNoteService();

    registerFallbackValue(0);
    registerFallbackValue('');
    registerFallbackValue(<String, dynamic>{});
  });

  group('OdooPickingNoteService', () {

    /// POSITIVE CASE - saveNote
    group('saveNote', () {
      test('returns true when note is saved successfully', () async {
        when(
              () => service.saveNote(
            any(),
            any(),
          ),
        ).thenAnswer((_) async => true);

        final result = await service.saveNote(
          10,
          'Picking note added',
        );

        expect(result, true);

        verify(
              () => service.saveNote(
            10,
            'Picking note added',
          ),
        ).called(1);
      });

      /// EDGE CASE - saveNote
      test('returns false when API returns false', () async {
        when(
              () => service.saveNote(
            any(),
            any(),
          ),
        ).thenAnswer((_) async => false);

        final result = await service.saveNote(
          20,
          'Another note',
        );

        expect(result, false);
      });

      /// NEGATIVE CASE - saveNote
      test('throws exception when API fails', () async {
        when(
              () => service.saveNote(
            any(),
            any(),
          ),
        ).thenThrow(Exception('Server error'));

        expect(
              () => service.saveNote(
            30,
            'Failure note',
          ),
          throwsException,
        );
      });
    });
  });
}
