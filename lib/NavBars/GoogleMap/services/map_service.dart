import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// Utility service for Google Maps-related operations in the route visualization flow.
///
/// Responsibilities:
///   - Create custom navigation marker (blue dot)
///   - Place Autocomplete suggestions & geocoding (lat/lng from place name)
///   - Polyline decoding from Google Directions API
///   - Bearing calculation, distance utilities (point-to-point, point-to-segment/polyline)
///   - Audio feedback for reaching stops or going off-route
///   - Human-readable duration formatting
///
/// All Google Maps API calls require a valid API key (fetched from Odoo).
class MapService {
  final AudioPlayer audioPlayer = AudioPlayer();

  /// Creates a custom circular blue dot marker with semi-transparent background glow.
  ///
  /// Used as the live navigation position indicator.
  /// Opacity can be adjusted dynamically (e.g. pulsing effect).
  ///
  /// Returns a [BitmapDescriptor] ready to use in GoogleMap markers.
  Future<BitmapDescriptor> createBlueDotMarker(double opacity) async {
    final PictureRecorder pictureRecorder = PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    final Paint backgroundPaint = Paint()
      ..color = Colors.green[700]!.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    const double backgroundRadius = 60.0;
    canvas.drawCircle(
      Offset(backgroundRadius, backgroundRadius),
      backgroundRadius,
      backgroundPaint,
    );

    final Paint paint = Paint()
      ..color = Colors.green[700]!.withOpacity(opacity)
      ..style = PaintingStyle.fill;

    const double radius = 20.0;
    canvas.drawCircle(
      Offset(backgroundRadius, backgroundRadius),
      radius,
      paint,
    );

    final img = await pictureRecorder.endRecording().toImage(
      (backgroundRadius * 2).toInt(),
      (backgroundRadius * 2).toInt(),
    );
    final data = await img.toByteData(format: ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  /// Fetches place autocomplete suggestions from Google Places API.
  ///
  /// Used in search fields for source and stop locations.
  /// Returns a list of place description strings (e.g. "Kochi, Kerala, India").
  ///
  /// Returns empty list on error or invalid response.
  Future<List<String>> fetchSuggestions(String input, String apiKey) async {
    final String url =
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$apiKey';

    final response = await http.get(Uri.parse(url));
    final json = jsonDecode(response.body);

    if (json['status'] == 'OK') {
      return List<String>.from(
        json['predictions'].map((p) => p['description']),
      );
    } else {
      return [];
    }
  }

  /// Converts a place name/description to geographic coordinates (LatLng).
  ///
  /// Uses Google Geocoding API to resolve address → latitude/longitude.
  /// Returns `null` if no results or API error.
  Future<LatLng?> getLatLngFromPlace(String placeDescription, String apiKey) async {
    final geocodeUrl =
        'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(placeDescription)}&key=$apiKey';

    final response = await http.get(Uri.parse(geocodeUrl));
    final json = jsonDecode(response.body);

    if (json['status'] == 'OK' && json['results'].isNotEmpty) {
      final location = json['results'][0]['geometry']['location'];
      return LatLng(location['lat'], location['lng']);
    } else {
      return null;
    }
  }

  /// Decodes Google Maps polyline string into a list of LatLng points.
  ///
  /// Used to convert the `overview_polyline.points` from Directions API response
  /// into drawable points for the route Polyline overlay.
  List<LatLng> decodePolyline(String encoded) {
    List<LatLng> polyline = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      polyline.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return polyline;
  }

  /// Calculates the initial bearing (heading in degrees) from start to end point.
  ///
  /// Used to rotate the navigation marker to face the direction of travel.
  /// Returns value in range [0, 360).
  double calculateBearing(LatLng start, LatLng end) {
    final lat1 = math.pi * start.latitude / 180.0;
    final lon1 = math.pi * start.longitude / 180.0;
    final lat2 = math.pi * end.latitude / 180.0;
    final lon2 = math.pi * end.longitude / 180.0;

    final dLon = lon2 - lon1;

    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
            math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final bearing = math.atan2(y, x);
    return (bearing * 180 / math.pi + 360) % 360;
  }

  /// Computes the shortest distance from a point to any segment of the polyline.
  ///
  /// Useful for off-route detection (if distance > threshold → recalculate route).
  double distanceToPolyline(LatLng point, List<LatLng> polyline) {
    double minDistance = double.infinity;
    for (int i = 0; i < polyline.length - 1; i++) {
      final distance = distanceToSegment(point, polyline[i], polyline[i + 1]);
      minDistance = math.min(minDistance, distance);
    }
    return minDistance;
  }

  /// Calculates perpendicular distance from point `p` to line segment `a`-`b`.
  ///
  /// Returns distance in **meters** (approximate using 111 km per degree).
  double distanceToSegment(LatLng p, LatLng a, LatLng b) {
    final double x = p.latitude;
    final double y = p.longitude;
    final double x1 = a.latitude;
    final double y1 = a.longitude;
    final double x2 = b.latitude;
    final double y2 = b.longitude;

    final double A = x - x1;
    final double B = y - y1;
    final double C = x2 - x1;
    final double D = y2 - y1;

    final double dot = A * C + B * D;
    final double len_sq = C * C + D * D;
    final double param = len_sq != 0 ? dot / len_sq : -1;

    double xx, yy;

    if (param < 0) {
      xx = x1;
      yy = y1;
    } else if (param > 1) {
      xx = x2;
      yy = y2;
    } else {
      xx = x1 + param * C;
      yy = y1 + param * D;
    }

    final double dx = x - xx;
    final double dy = y - yy;
    return math.sqrt(dx * dx + dy * dy) * 111000;
  }

  /// Haversine formula: great-circle distance between two LatLng points.
  ///
  /// Returns distance in **meters**.
  double distanceBetweenPoints(LatLng a, LatLng b) {
    const double R = 6371000;
    final lat1 = math.pi * a.latitude / 180.0;
    final lat2 = math.pi * b.latitude / 180.0;
    final deltaLat = math.pi * (b.latitude - a.latitude) / 180.0;
    final deltaLon = math.pi * (b.longitude - a.longitude) / 180.0;

    final aSin =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
            math.cos(lat1) *
                math.cos(lat2) *
                math.sin(deltaLon / 2) *
                math.sin(deltaLon / 2);
    final c = 2 * math.atan2(math.sqrt(aSin), math.sqrt(1 - aSin));
    return R * c;
  }

  /// Plays a sound when user reaches a stop (within ~50 meters).
  Future<void> playReachPointSound() async {
    await audioPlayer.setSource(AssetSource('stop_alert.wav'));
  }

  /// Plays alert sound when user deviates significantly from the route.
  Future<void> playWrongPathSound() async {
    await audioPlayer.setSource(AssetSource('wrong_alert.wav'));
  }

  /// Formats total seconds into human-readable duration (e.g. "2 hr 15 min").
  ///
  /// Omits hours if zero; always shows minutes.
  String formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '$hours hr $minutes min';
    }
    return '$minutes min';
  }
}