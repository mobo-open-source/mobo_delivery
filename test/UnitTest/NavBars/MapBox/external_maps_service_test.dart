import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:odoo_delivery_app/NavBars/MapBox/services/external_maps_service.dart';

void main() {
  const service = ExternalMapsService();
  final stops = List.generate(
    12,
    (i) => LatLng(11.0 + i / 100, 75.0 + i / 100),
  );

  group('googleDirections', () {
    test('sends every stop in order, last one as the destination', () {
      final link = service.googleDirections(
        stops: stops.take(3).toList(),
        travelMode: 'driving',
      );
      final q = link.uri.queryParameters;
      expect(link.uri.host, 'www.google.com');
      expect(link.uri.path, '/maps/dir/');
      expect(q['api'], '1');
      expect(q['destination'], '11.020000,75.020000');
      expect(q['waypoints'], '11.000000,75.000000|11.010000,75.010000');
      expect(q['travelmode'], 'driving');
      expect(link.isTruncated, isFalse);
    });

    test('device location: no origin, starts navigation', () {
      final q = service
          .googleDirections(stops: [stops.first], travelMode: 'driving')
          .uri
          .queryParameters;
      expect(q.containsKey('origin'), isFalse);
      expect(q['dir_action'], 'navigate');
      expect(q.containsKey('waypoints'), isFalse);
    });

    test('typed source: origin sent, no forced navigation', () {
      final q = service
          .googleDirections(
            origin: const LatLng(10, 76),
            stops: [stops.first],
            travelMode: 'walking',
          )
          .uri
          .queryParameters;
      expect(q['origin'], '10.000000,76.000000');
      expect(q.containsKey('dir_action'), isFalse);
      expect(q['travelmode'], 'walking');
    });

    test('caps at 9 waypoints + destination and reports the cut', () {
      final link = service.googleDirections(stops: stops, travelMode: 'driving');
      final q = link.uri.queryParameters;
      expect(q['waypoints']!.split('|'), hasLength(9));
      expect(q['destination'], '11.090000,75.090000');
      expect(link.stopsSent, 10);
      expect(link.stopsTotal, 12);
      expect(link.isTruncated, isTrue);
    });
  });

  group('appleDirections', () {
    test('prefers the address and reports a single stop sent', () {
      final link = service.appleDirections(
        destination: stops.first,
        destinationAddress: '  MG Road, Kochi ',
        travelMode: 'driving',
        stopsTotal: 3,
      );
      final q = link.uri.queryParameters;
      expect(link.uri.host, 'maps.apple.com');
      expect(q['daddr'], 'MG Road, Kochi');
      expect(q['dirflg'], 'd');
      expect(q.containsKey('saddr'), isFalse);
      expect(link.isTruncated, isTrue);
    });

    test('falls back to coordinates without an address', () {
      final q = service
          .appleDirections(
            destination: stops.first,
            destinationAddress: '',
            travelMode: 'bicycling',
            stopsTotal: 1,
          )
          .uri
          .queryParameters;
      expect(q['daddr'], '11.000000,75.000000');
      expect(q.containsKey('dirflg'), isFalse);
    });
  });
}
