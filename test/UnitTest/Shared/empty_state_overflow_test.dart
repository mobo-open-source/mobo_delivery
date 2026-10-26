import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_delivery_app/shared/widgets/empty_state.dart';

/// Searching a list that returns nothing puts the empty state and the
/// on-screen keyboard on screen at the same time, which can leave the widget
/// barely a third of the viewport. It has to cope with that rather than
/// painting a RenderFlex overflow stripe over the result.
void main() {
  /// Renders the empty state inside a box of [height], the way a list page
  /// hands it whatever is left under the search bar.
  Future<void> pumpAt(WidgetTester tester, double height) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: height,
              width: 400,
              child: const EmptyState(
                title: 'No Pickings Found',
                subtitle: 'There are no picking items available.',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('EmptyState survives a shrinking viewport', () {
    testWidgets('full height — no overflow', (tester) async {
      await pumpAt(tester, 700);
      expect(tester.takeException(), isNull);
      expect(find.text('No Pickings Found'), findsOneWidget);
    });

    testWidgets('keyboard open on a typical phone — no overflow',
        (tester) async {
      /// ~820 logical px tall screen minus a ~330px keyboard and a search bar.
      await pumpAt(tester, 300);
      expect(tester.takeException(), isNull);
      expect(find.text('No Pickings Found'), findsOneWidget);
    });

    testWidgets('keyboard open on a short screen — no overflow',
        (tester) async {
      await pumpAt(tester, 180);
      expect(tester.takeException(), isNull);
    });

    testWidgets('extreme squeeze still does not overflow', (tester) async {
      await pumpAt(tester, 90);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stays scrollable so content is reachable when squeezed',
        (tester) async {
      await pumpAt(tester, 180);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('an action button does not reintroduce overflow',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                height: 240,
                width: 400,
                child: EmptyState(
                  title: 'No Pickings Found',
                  subtitle: 'Try clearing your filters.',
                  actionLabel: 'Clear Filters',
                  onAction: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });
  });
}
