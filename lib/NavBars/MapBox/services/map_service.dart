import 'dart:convert';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Utility service for TomTom-related operations in the route visualization flow.
///
/// Responsibilities:
///   - Place autocomplete suggestions & geocoding via TomTom Search API
///   - Route point parsing from TomTom Routing API responses
///   - Bearing calculation, distance utilities (point-to-point, point-to-segment/polyline)
///   - Audio feedback for reaching stops or going off-route
///   - Human-readable duration and distance formatting
///
/// All TomTom API calls require a valid API key.
class MapService {
  final AudioPlayer audioPlayer = AudioPlayer();

  /// Fetches place autocomplete suggestions from TomTom Search API.
  ///
  /// Used in search fields for source and stop locations.
  /// Returns a list of human-readable address strings.
  ///
  /// Returns empty list on error or invalid response.
  Future<List<String>> fetchSuggestions(
      String input, String apiKey,
      {LatLng? proximity}) async {
    if (input.trim().isEmpty) return [];
    final encoded = Uri.encodeComponent(input);
    final proximityParam = proximity != null
        ? '&lat=${proximity.latitude}&lon=${proximity.longitude}'
        : '';
    final url =
        'https://api.tomtom.com/search/2/search/$encoded.json'
        '?typeahead=true&limit=5$proximityParam&key=$apiKey';
    try {
      final response = await http.get(Uri.parse(url));
      final json = jsonDecode(response.body);
      if (json['results'] != null) {
        return List<String>.from(
          (json['results'] as List).map(
              (r) => r['address']?['freeformAddress'] as String? ?? ''),
        ).where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {
    }
    return [];
  }

  /// Converts a place name/description to geographic coordinates ([LatLng]).
  ///
  /// Uses TomTom Search API to resolve address → latitude/longitude.
  ///
  /// Returns `null` if no results or API error.
  Future<LatLng?> getLatLngFromPlace(
      String placeDescription, String apiKey,
      {LatLng? proximity}) async {
    final encoded = Uri.encodeComponent(placeDescription);
    final proximityParam = proximity != null
        ? '&lat=${proximity.latitude}&lon=${proximity.longitude}'
        : '';
    final url =
        'https://api.tomtom.com/search/2/search/$encoded.json'
        '?limit=1$proximityParam&key=$apiKey';
    try {
      final response = await http.get(Uri.parse(url));
      final json = jsonDecode(response.body);
      if (json['results'] != null &&
          (json['results'] as List).isNotEmpty) {
        final pos = json['results'][0]['position'];
        return LatLng(
          (pos['lat'] as num).toDouble(),
          (pos['lon'] as num).toDouble(),
        );
      }
    } catch (_) {
    }
    return null;
  }

  /// Parses TomTom route leg points into a list of [LatLng].
  ///
  /// TomTom returns route points as `[{latitude, longitude}, ...]` objects
  /// in each leg of the route response.
  List<LatLng> parseRoutePoints(List<dynamic> legs) {
    final List<LatLng> points = [];
    for (final leg in legs) {
      final legPoints = leg['points'] as List? ?? [];
      for (final p in legPoints) {
        points.add(LatLng(
          (p['latitude'] as num).toDouble(),
          (p['longitude'] as num).toDouble(),
        ));
      }
    }
    return points;
  }

  /// Calculates the initial bearing (heading in degrees) from [start] to [end].
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
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// Computes the shortest distance from [point] to any segment of [polyline].
  ///
  /// Useful for off-route detection (if distance > threshold → play alert).
  double distanceToPolyline(LatLng point, List<LatLng> polyline) {
    double minDistance = double.infinity;
    for (int i = 0; i < polyline.length - 1; i++) {
      final d = distanceToSegment(point, polyline[i], polyline[i + 1]);
      if (d < minDistance) minDistance = d;
    }
    return minDistance;
  }

  /// Calculates the perpendicular distance from point [p] to line segment [a]–[b].
  ///
  /// Returns distance in **meters** (approximate using 111 km per degree).
  double distanceToSegment(LatLng p, LatLng a, LatLng b) {
    final double x = p.latitude, y = p.longitude;
    final double x1 = a.latitude, y1 = a.longitude;
    final double x2 = b.latitude, y2 = b.longitude;

    final double C = x2 - x1, D = y2 - y1;
    final double lenSq = C * C + D * D;
    final double param = lenSq != 0 ? ((x - x1) * C + (y - y1) * D) / lenSq : -1;

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

    final double dx = x - xx, dy = y - yy;
    return math.sqrt(dx * dx + dy * dy) * 111000;
  }

  /// Haversine formula: great-circle distance between two [LatLng] points.
  ///
  /// Returns distance in **meters**.
  double distanceBetweenPoints(LatLng a, LatLng b) {
    const double R = 6371000;
    final lat1 = math.pi * a.latitude / 180.0;
    final lat2 = math.pi * b.latitude / 180.0;
    final dLat = math.pi * (b.latitude - a.latitude) / 180.0;
    final dLon = math.pi * (b.longitude - a.longitude) / 180.0;

    final aSin = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(aSin), math.sqrt(1 - aSin));
  }

  /// Plays a sound when the user reaches a stop (within ~50 meters).
  Future<void> playReachPointSound() async {
    await audioPlayer.setSource(AssetSource('stop_alert.wav'));
  }

  /// Plays an alert sound when the user deviates significantly from the route.
  Future<void> playWrongPathSound() async {
    await audioPlayer.setSource(AssetSource('wrong_alert.wav'));
  }

  /// Formats total [seconds] into a human-readable duration (e.g. "2 hr 15 min").
  ///
  /// Omits hours if zero; always shows minutes.
  String formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return hours > 0 ? '$hours hr $minutes min' : '$minutes min';
  }

  /// Formats [meters] into a human-readable distance string (e.g. "1.4 km", "850 m").
  String formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '${meters.toInt()} m';
  }
}
