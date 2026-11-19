import 'dart:io' show Platform;

import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// A map app the planned route can be handed over to.
enum ExternalMapsApp { google, apple }

/// A link ready to open, and how many of the route's stops it carries.
class ExternalMapsLink {
  const ExternalMapsLink({
    required this.uri,
    required this.stopsSent,
    required this.stopsTotal,
  });

  final Uri uri;
  final int stopsSent;
  final int stopsTotal;

  /// True when the app could not take every stop, so the user must be told.
  bool get isTruncated => stopsSent < stopsTotal;
}

/// Builds and opens directions links for Google Maps and Apple Maps.
///
/// URL building is pure so it can be tested; only [open] and
/// [isGoogleMapsInstalled] touch the platform.
class ExternalMapsService {
  const ExternalMapsService();

  /// Google Maps URLs accept a destination plus up to nine waypoints when the
  /// link opens in the Maps app ("up to three waypoints supported on mobile
  /// browsers, and a maximum of nine waypoints supported otherwise" —
  /// developers.google.com/maps/documentation/urls/get-started).
  static const int googleMaxWaypoints = 9;
  static const int googleMaxStops = googleMaxWaypoints + 1;

  /// Directions through every stop, in order, ending at the last one.
  ///
  /// [origin] is left out when the trip starts at the device's own location:
  /// Google Maps then starts turn-by-turn navigation instead of a preview.
  ExternalMapsLink googleDirections({
    LatLng? origin,
    required List<LatLng> stops,
    required String travelMode,
  }) {
    assert(stops.isNotEmpty, 'A route needs at least one stop');
    final sent = stops.take(googleMaxStops).toList();
    final waypoints = sent.sublist(0, sent.length - 1);
    final params = <String, String>{
      'api': '1',
      if (origin != null) 'origin': _coord(origin),
      'destination': _coord(sent.last),
      if (waypoints.isNotEmpty) 'waypoints': waypoints.map(_coord).join('|'),
      'travelmode': _googleTravelMode(travelMode),
      if (origin == null) 'dir_action': 'navigate',
    };
    return ExternalMapsLink(
      uri: Uri.https('www.google.com', '/maps/dir/', params),
      stopsSent: sent.length,
      stopsTotal: stops.length,
    );
  }

  /// Directions to a single stop in Apple Maps.
  ///
  /// Apple documents no way to pass intermediate stops in a link, so only the
  /// next stop is sent. The address is preferred over coordinates: Apple has
  /// reported `daddr=lat,lng` misbehaving on recent iOS releases.
  ExternalMapsLink appleDirections({
    LatLng? origin,
    required LatLng destination,
    String? destinationAddress,
    required String travelMode,
    required int stopsTotal,
  }) {
    final address = destinationAddress?.trim() ?? '';
    final flag = _appleDirFlag(travelMode);
    final params = <String, String>{
      if (origin != null) 'saddr': _coord(origin),
      'daddr': address.isNotEmpty ? address : _coord(destination),
      if (flag != null) 'dirflg': flag,
    };
    return ExternalMapsLink(
      uri: Uri.https('maps.apple.com', '/', params),
      stopsSent: 1,
      stopsTotal: stopsTotal,
    );
  }

  /// Whether the Google Maps app is installed. Only meaningful on iOS, where
  /// the user is offered a choice; Android hands Google links to the Maps app
  /// itself. Needs `comgooglemaps` in LSApplicationQueriesSchemes.
  Future<bool> isGoogleMapsInstalled() async {
    if (!Platform.isIOS) return false;
    try {
      return await canLaunchUrl(Uri.parse('comgooglemaps://'));
    } catch (_) {
      return false;
    }
  }

  /// Opens [uri] outside the app. Returns false when nothing could open it,
  /// rather than throwing, so the caller can tell the user.
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static String _coord(LatLng p) =>
      '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}';

  static String _googleTravelMode(String mode) {
    switch (mode) {
      case 'walking':
        return 'walking';
      case 'bicycling':
        return 'bicycling';
      default:
        return 'driving';
    }
  }

  /// Apple Maps links know driving (`d`), walking (`w`) and transit (`r`);
  /// there is no cycling flag, so cycling lets Apple Maps choose.
  static String? _appleDirFlag(String mode) {
    switch (mode) {
      case 'walking':
        return 'w';
      case 'bicycling':
        return null;
      default:
        return 'd';
    }
  }
}
