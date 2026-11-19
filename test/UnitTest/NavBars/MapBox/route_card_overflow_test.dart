import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:odoo_delivery_app/NavBars/MapBox/widgets/remaining_info_card.dart';
import 'package:odoo_delivery_app/NavBars/MapBox/widgets/route_info_card.dart';

/// Both route sheets cap themselves at a fixed height and fill that budget
/// with a header, a stop list and a button row. Adding the "Open in Maps"
/// pill to the header spent the last few pixels of slack and the navigation
/// card started painting a 3px RenderFlex stripe over the bottom edge.
///
/// The gesture-navigation inset counts against the same budget, so these
/// pump the cards with a realistic bottom padding and a stop list long
/// enough to reach the list's own cap.
void main() {
  List<Map<String, String>> legs(int n) => List.generate(
    n,
    (i) => {
      'end_address': 'Eratty Illam, Sankaranellur, Kuthuparamba, Kerala $i',
      'distance': '96.1 km',
      'duration': '2 hr 9 min',
    },
  );

  List<Map<String, dynamic>> remainingLegs(int n) => List.generate(
    n,
    (i) => {
      'name': 'AI Twar Centre, Pottammal Jct, Pottammal, Kerala $i',
      'distance': '81.0 km',
      'duration': '1 hr 55 min',
      'latlng': const LatLng(11.25, 75.78),
      'type': i == 0 ? 'start' : 'stop',
    },
  );

  /// Wraps a card the way the page does: pinned to the bottom of a phone
  /// screen, under a status bar, over a gesture-nav inset.
  Future<void> pump(
    WidgetTester tester,
    Widget card, {
    double bottomInset = 24,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 800),
            padding: EdgeInsets.only(top: 24, bottom: bottomInset),
          ),
          child: Scaffold(
            body: Stack(
              children: [Positioned(bottom: 0, left: 0, right: 0, child: card)],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('RemainingInfoCard fits its height budget', () {
    testWidgets('with the Open in Maps pill and a full stop list', (
      tester,
    ) async {
      await pump(
        tester,
        RemainingInfoCard(
          remainingDistance: '177.1 km',
          remainingDuration: '4 hr 3 min',
          remainingLegInfo: remainingLegs(6),
          onFocusPressed: (_) {},
          onAddRoutePressed: () {},
          onOpenInMapsPressed: () {},
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Add Stop'), findsOneWidget);
      expect(find.text('Open in Maps'), findsOneWidget);
    });

    testWidgets('on a device with a tall gesture inset', (tester) async {
      await pump(
        tester,
        RemainingInfoCard(
          remainingDistance: '177.1 km',
          remainingDuration: '4 hr 3 min',
          remainingLegInfo: remainingLegs(6),
          onFocusPressed: (_) {},
          onAddRoutePressed: () {},
          onOpenInMapsPressed: () {},
        ),
        bottomInset: 48,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Add Stop'), findsOneWidget);
    });

    testWidgets('without the pill, as before it was added', (tester) async {
      await pump(
        tester,
        RemainingInfoCard(
          remainingDistance: '177.1 km',
          remainingDuration: '4 hr 3 min',
          remainingLegInfo: remainingLegs(6),
          onFocusPressed: (_) {},
          onAddRoutePressed: () {},
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Open in Maps'), findsNothing);
    });
  });

  group('RouteInfoCard fits its height budget', () {
    testWidgets('with the Open in Maps pill and a full leg list', (
      tester,
    ) async {
      await pump(
        tester,
        RouteInfoCard(
          routeDuration: '4 hr 3 min',
          routeDistance: '177.1 km',
          legInfo: legs(8),
          onStartPressed: () {},
          onAddStopPressed: () {},
          onOpenInMapsPressed: () {},
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Add Stop'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('on a device with a tall gesture inset', (tester) async {
      await pump(
        tester,
        RouteInfoCard(
          routeDuration: '4 hr 3 min',
          routeDistance: '177.1 km',
          legInfo: legs(8),
          onStartPressed: () {},
          onAddStopPressed: () {},
          onOpenInMapsPressed: () {},
        ),
        bottomInset: 48,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Start'), findsOneWidget);
    });
  });
}
