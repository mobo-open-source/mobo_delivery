import 'dart:convert';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Utility service for Mapbox-related operations in the route visualization flow.
///
/// Responsibilities:
///   - Place autocomplete suggestions & geocoding via Mapbox Geocoding API
///   - Polyline decoding (Google-compatible format returned by Mapbox Directions API)
///   - Bearing calculation, distance utilities (point-to-point, point-to-segment/polyline)
///   - Audio feedback for reaching stops or going off-route
///   - Human-readable duration and distance formatting
///
/// All Mapbox API calls require a valid public access token.
class MapService {
  final AudioPlayer audioPlayer = AudioPlayer();

  /// Fetches place autocomplete suggestions from Mapbox Geocoding API.
  ///
  /// Used in search fields for source and stop locations.
  /// Returns a list of human-readable place name strings.
  ///
  /// Returns empty list on error or invalid response.
  Future<List<String>> fetchSuggestions(
      String input, String accessToken,
      {LatLng? proximity}) async {
    if (input.trim().isEmpty) return [];
    final encoded = Uri.encodeComponent(input);
    final proximityParam = proximity != null
        ? '&proximity=${proximity.longitude},${proximity.latitude}'
        : '';
    final url =
        'https://api.mapbox.com/geocoding/v5/mapbox.places/$encoded.json'
        '?autocomplete=true$proximityParam&access_token=$accessToken';
    try {
      final response = await http.get(Uri.parse(url));
      final json = jsonDecode(response.body);
      if (json['features'] != null) {
        return List<String>.from(
          (json['features'] as List).map((f) => f['place_name'] as String),
        );
      }
    } catch (_) {
      // Non-critical; return empty list on failure.
    }
    return [];
  }

  /// Converts a place name/description to geographic coordinates ([LatLng]).
  ///
  /// Uses Mapbox Geocoding API to resolve address → latitude/longitude.
  /// Note: Mapbox returns coordinates as [longitude, latitude] — this method
  /// correctly maps them to [LatLng(latitude, longitude)].
  ///
  /// Returns `null` if no results or API error.
  Future<LatLng?> getLatLngFromPlace(
      String placeDescription, String accessToken,
      {LatLng? proximity}) async {
    final encoded = Uri.encodeComponent(placeDescription);
    final proximityParam = proximity != null
        ? '&proximity=${proximity.longitude},${proximity.latitude}'
        : '';
    final url =
        'https://api.mapbox.com/geocoding/v5/mapbox.places/$encoded.json'
        '?access_token=$accessToken$proximityParam';
    try {
      final response = await http.get(Uri.parse(url));
      final json = jsonDecode(response.body);
      if (json['features'] != null &&
          (json['features'] as List).isNotEmpty) {
        // Mapbox center is [longitude, latitude].
        final center = json['features'][0]['center'] as List;
        return LatLng(center[1] as double, center[0] as double);
      }
    } catch (_) {
      // Non-critical; caller handles null return.
    }
    return null;
  }

  /// Decodes a Google-compatible encoded polyline string into a list of [LatLng] points.
  ///
  /// Mapbox Directions API returns the same polyline encoding format when
  /// `geometries=polyline` is requested, making this decoder reusable.
  List<LatLng> decodePolyline(String encoded) {
    final List<LatLng> polyline = [];
    int index = 0;
    final int len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));

      polyline.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return polyline;
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
