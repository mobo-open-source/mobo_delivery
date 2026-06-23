import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:location/location.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:http/http.dart' as http;
import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/snackbar.dart';
import '../services/map_service.dart';
import '../services/odoo_map_service.dart';
import '../../../shared/widgets/loaders/loading_widget.dart';
import '../../../shared/widgets/loading_overlay.dart';
import '../../../shared/widgets/error_state_widget.dart';
import '../../../shared/widgets/inputs/mobo_text_field.dart';
import '../../../shared/widgets/buttons/mobo_button.dart';
import '../../../core/company/widgets/mobo_checkbox.dart';
import '../widgets/navigation_header.dart';
import '../widgets/remaining_info_card.dart';
import '../widgets/route_info_card.dart';
import '../widgets/search_inputs.dart';

/// Full-screen page for route planning and real-time navigation visualization.
///
/// Features:
///   - Select multiple stock pickings → auto-populate stops from destination points
///   - Source location (defaults to current GPS or manual entry)
///   - Mapbox Directions API route calculation with ordered waypoints
///   - Live location tracking with animated navigation dot marker & bearing
///   - Remaining distance/time updates + leg-by-leg info card
///   - Map style switching (streets, satellite, terrain, hybrid)
///   - Manual camera control and offline warning
///   - Gyroscope-based rotation detection for bearing adjustment
class RouteVisualizationPage extends StatefulWidget {
  const RouteVisualizationPage({super.key});

  @override
  State<RouteVisualizationPage> createState() => _RouteVisualizationPageState();
}

/// Manages map controller, location tracking, route calculation, markers/polylines,
/// UI overlays, navigation state, and real-time updates.
///
/// Responsibilities:
///   - Initialize location services, navigation marker, gyroscope listener
///   - Fetch pickings from Odoo and populate stop fields
///   - Calculate & display route via Mapbox Directions API
///   - Track user location, update live navigation marker + bearing
///   - Periodically refresh remaining distance/time
///   - Handle offline mode, map style switching, stop addition
class _RouteVisualizationPageState extends State<RouteVisualizationPage> {
  final OdooMapService odooService = OdooMapService();
  final MapService mapService = MapService();

  LatLng? _initialCameraPosition;

  /// Center used when the device location is unavailable (permission denied,
  /// location services off, or a lookup error) so the map still renders
  /// instead of hanging on the loading overlay forever.
  static const LatLng _fallbackCenter = LatLng(20.5937, 78.9629);

  /// Ensures the "location unavailable" notice is only shown once.
  bool _locationNoticeShown = false;

  final MapController _mapController = MapController();
  final TextEditingController sourceController = TextEditingController();
  final TextEditingController sourceSearchController = TextEditingController();
  final List<TextEditingController> _stopSearchControllers = [
    TextEditingController(),
  ];
  final List<List<String>> _stopSuggestions = [[]];
  bool _showLocationNames = false;

  /// Static markers: start location + numbered stop pins.
  List<Marker> _markers = [];

  /// Live navigation marker (updated on every location event).
  Marker? _movingMarker;

  List<String> _sourceSuggestions = [];
  final List<LatLng> _stops = [];
  LatLng? _sourceLatLng;
  List<Polyline> _polylines = [];

  /// Current TomTom map style: basic/main, sat/main, basic/night, hybrid/main.
  String _currentMapStyle = 'basic/main';
  bool _showOtherFABs = true;
  String _routeDuration = '';
  String _routeDistance = '';
  List<Map<String, String>> _legInfo = [];
  String _selectedTravelMode = 'driving';
  StreamSubscription<LocationData>? _locationSubscription;
  final Location _location = Location();
  double _lastBearing = 0.0;
  Widget? _navigationIcon;
  StreamSubscription? _gyroscopeSubscription;
  bool _isPhoneRotated = false;
  LatLng? _currentLatLng;
  bool _showLayer = true;
  List<Map<String, dynamic>> pickings = [];
  List<int> selectedPickings = [];
  List<String> selectedPickingNames = [];
  bool shouldValidate = false;
  bool _isMapManuallyMoved = false;
  bool _isNavigationStarted = false;
  Timer? _distanceUpdateTimer;
  String _remainingDuration = '';
  String _remainingDistance = '';
  bool _showStopLocationFields = false;
  List<Map<String, dynamic>> _remainingLegInfo = [];
  bool _isLoading = false;
  bool _infoCard = false;
  bool isOnline = true;
  bool _showRemainingInfo = false;

  /// Mapbox public access token — loaded from .env at start, may be overridden by Odoo.
  // ignore: prefer_final_fields
  String _apiKey = '';

  @override
  void initState() {
    super.initState();
    _apiKey = dotenv.env['TOMTOM_API_KEY'] ?? '***REMOVED-SEE-SECURITY-NOTICE***';
    _initializeServices();
    _setInitialLocation();
    _loadCustomMarker();
    _listenToGyroscope();
  }

  /// Initializes Odoo client, checks connectivity, fetches pickings.
  ///
  /// Internet status (`isOnline`) is driven purely by the DNS-based
  /// connectivity check — Odoo session / RPC failures do NOT flip
  /// `isOnline` because the map itself works without picking data.
  /// Backend errors surface as a snackbar instead of the full-page
  /// "No Internet" overlay.
  Future<void> _initializeServices() async {
    bool online;
    try {
      online = await odooService.checkNetworkConnectivity();
    } catch (_) {
      online = false;
    }

    if (!online) {
      if (mounted) setState(() => isOnline = false);
      return;
    }
    if (mounted) setState(() => isOnline = true);

    try {
      await odooService.initializeOdooClient();
      final fetched = await odooService.fetchStockPickings();
      if (mounted) setState(() => pickings = fetched);
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Could not load pickings from Odoo. Map navigation still works.',
        );
      }
    }
  }

  /// Listens to gyroscope events to detect phone rotation (used for bearing updates).
  void _listenToGyroscope() {
    _gyroscopeSubscription = gyroscopeEventStream().listen((GyroscopeEvent event) {
      _isPhoneRotated = event.z.abs() > 0.5;
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _distanceUpdateTimer?.cancel();
    sourceController.dispose();
    sourceSearchController.dispose();
    for (var controller in _stopSearchControllers) {
      controller.dispose();
    }
    mapService.audioPlayer.dispose();
    super.dispose();
  }

  /// Builds the navigation arrow marker used during live navigation.
  void _loadCustomMarker() {
    _navigationIcon = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF1A73E8),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0x664285F4),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
    );
    if (mounted) setState(() {});
  }

  /// Maps internal travel mode string to the corresponding TomTom travel mode.
  /// Sorts intermediate stops by nearest-neighbor from [_sourceLatLng],
  /// always keeping the last stop (final destination) fixed at the end.
  ///
  /// Example: Source → [Ramanattukara, Kozhikode] → Thamarassery
  /// If Ramanattukara is closer to Source, order stays; otherwise swaps.
  void _applySortedStopOrder() {
    if (_sourceLatLng == null || _stops.length < 2) return;

    final finalStop = _stops.last;
    final finalCtrl = _stopSearchControllers.last;

    final intermediate = _stops.sublist(0, _stops.length - 1);
    final intermediateCtrls =
        _stopSearchControllers.sublist(0, _stopSearchControllers.length - 1);

    final remaining = List<int>.generate(intermediate.length, (i) => i);
    final sortedIndices = <int>[];
    LatLng current = _sourceLatLng!;

    while (remaining.isNotEmpty) {
      int bestIdx = remaining[0];
      double bestDist =
          mapService.distanceBetweenPoints(current, intermediate[bestIdx]);
      for (final i in remaining) {
        final d = mapService.distanceBetweenPoints(current, intermediate[i]);
        if (d < bestDist) {
          bestDist = d;
          bestIdx = i;
        }
      }
      sortedIndices.add(bestIdx);
      remaining.remove(bestIdx);
      current = intermediate[bestIdx];
    }

    _stops
      ..clear()
      ..addAll(sortedIndices.map((i) => intermediate[i]))
      ..add(finalStop);

    _stopSearchControllers
      ..clear()
      ..addAll(sortedIndices.map((i) => intermediateCtrls[i]))
      ..add(finalCtrl);

    _stopSuggestions
      ..clear()
      ..addAll(List.generate(_stops.length, (_) => <String>[]));
  }

  String _getTomTomTravelMode(String travelMode) {
    switch (travelMode) {
      case 'walking':
        return 'pedestrian';
      case 'bicycling':
        return 'bicycle';
      default:
        return 'car';
    }
  }

  /// Calculates route using TomTom Routing API.
  ///
  /// Flow:
  ///   1. Builds coordinates string: origin + ordered stops (lat,lon format)
  ///   2. Calls TomTom Calculate Route API
  ///   3. Parses route points → draws route overlay
  ///   4. Computes total distance/duration + leg-by-leg info
  ///   5. Places start/stop markers on the map
  ///   6. Fits camera bounds to show entire route
  Future<void> _getOptimizedRoute() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      if (_apiKey.isEmpty) {
        CustomSnackbar.showError(context,
            'TomTom API key is missing. Check .env or Profile settings.');
        return;
      }

      if (_sourceLatLng == null) {
        if (_currentLatLng != null) {
          _sourceLatLng = _currentLatLng;
          sourceController.text = 'Your Location';
        } else if (sourceController.text.trim().isNotEmpty &&
            sourceController.text != 'Your Location') {
          _sourceLatLng = await mapService.getLatLngFromPlace(
              sourceController.text, _apiKey,
              proximity: _currentLatLng);
        }
      }

      if (_sourceLatLng == null) {
        if (!mounted) return;
        CustomSnackbar.showError(
            context, 'Source location not set. Enable GPS or enter manually.');
        return;
      }

      final filledCtrls = _stopSearchControllers
          .where((c) => c.text.trim().isNotEmpty)
          .toList();
      if (filledCtrls.isNotEmpty && _stops.length != filledCtrls.length) {
        final resolved = <LatLng>[];
        for (final ctrl in filledCtrls) {
          final latlng = await mapService.getLatLngFromPlace(
              ctrl.text, _apiKey,
              proximity: _currentLatLng);
          if (latlng != null) {
            resolved.add(latlng);
          }
        }
        if (mounted) {
          setState(() {
            _stops
              ..clear()
              ..addAll(resolved);
          });
        }
      }

      if (_stops.isEmpty) {
        if (!mounted) return;
        CustomSnackbar.showError(
            context, 'Could not resolve any stop locations. Try selecting from suggestions.');
        return;
      }

      if (_stops.length >= 2) _applySortedStopOrder();

      final allCoords = [
        '${_sourceLatLng!.latitude},${_sourceLatLng!.longitude}',
        ..._stops.map((s) => '${s.latitude},${s.longitude}'),
      ];
      final travelMode = _getTomTomTravelMode(_selectedTravelMode);
      final url =
          'https://api.tomtom.com/routing/1/calculateRoute/${allCoords.join(':')}/json'
          '?travelMode=$travelMode&key=$_apiKey';

      debugPrint('[TomTom] Routing URL: $url');

      final response = await http.get(Uri.parse(url));
      debugPrint('[TomTom] Routing response (${response.statusCode}): ${response.body.substring(0, response.body.length.clamp(0, 300))}');

      if (response.statusCode != 200) {
        if (!mounted) return;
        try {
          final errJson = jsonDecode(response.body);
          final msg = errJson['detailedError']?['message']
              ?? errJson['message']
              ?? 'HTTP ${response.statusCode}';
          CustomSnackbar.showError(context,
              travelMode == 'bicycle'
                  ? 'Bike routing unavailable for this route. Try a shorter distance or Drive mode. ($msg)'
                  : 'Route request failed: $msg');
        } catch (_) {
          CustomSnackbar.showError(
              context, 'Route request failed (HTTP ${response.statusCode}).');
        }
        return;
      }

      final json = jsonDecode(response.body);

      if (json['routes'] != null &&
          (json['routes'] as List).isNotEmpty) {
        final route = json['routes'][0];
        final legs = route['legs'] as List;
        final polylinePoints = mapService.parseRoutePoints(legs);

        if (polylinePoints.isEmpty) {
          if (mounted) {
            CustomSnackbar.showError(context, 'Route geometry could not be parsed.');
          }
          return;
        }

        double totalDistance = 0;
        int totalDuration = 0;
        final List<Map<String, String>> legInfo = [];

        final leg0Summary = legs[0]['summary'];
        legInfo.add({
          'start_address': sourceController.text.isEmpty
              ? 'Your Location'
              : sourceController.text,
          'end_address': _stopSearchControllers.isNotEmpty &&
                  _stopSearchControllers[0].text.isNotEmpty
              ? _stopSearchControllers[0].text
              : 'Stop 1',
          'distance':
              mapService.formatDistance((leg0Summary['lengthInMeters'] as num).toDouble()),
          'duration':
              mapService.formatDuration((leg0Summary['travelTimeInSeconds'] as num).toInt()),
        });
        totalDistance += (leg0Summary['lengthInMeters'] as num).toDouble() / 1000;
        totalDuration += (leg0Summary['travelTimeInSeconds'] as num).toInt();

        for (int i = 1; i < legs.length; i++) {
          final legSummary = legs[i]['summary'];
          totalDistance += (legSummary['lengthInMeters'] as num).toDouble() / 1000;
          totalDuration += (legSummary['travelTimeInSeconds'] as num).toInt();
          legInfo.add({
            'start_address': i - 1 < _stopSearchControllers.length &&
                    _stopSearchControllers[i - 1].text.isNotEmpty
                ? _stopSearchControllers[i - 1].text
                : 'Stop $i',
            'end_address': i < _stopSearchControllers.length &&
                    _stopSearchControllers[i].text.isNotEmpty
                ? _stopSearchControllers[i].text
                : 'Stop ${i + 1}',
            'distance':
                mapService.formatDistance((legSummary['lengthInMeters'] as num).toDouble()),
            'duration':
                mapService.formatDuration((legSummary['travelTimeInSeconds'] as num).toInt()),
          });
        }

        if (!mounted) return;
        setState(() {
          _polylines = [
            Polyline(
              points: polylinePoints,
              color: const Color(0xFF1A73E8),
              strokeWidth: 5.5,
              strokeCap: StrokeCap.round,
              strokeJoin: StrokeJoin.round,
              borderStrokeWidth: 1.5,
              borderColor: const Color(0xFF1557A0),
            ),
          ];
          _routeDistance = '${totalDistance.toStringAsFixed(1)} km';
          _routeDuration = mapService.formatDuration(totalDuration);
          _remainingDistance = _routeDistance;
          _remainingDuration = _routeDuration;
          _legInfo = legInfo;
          _movingMarker = null;
          _markers = [
            if (_sourceLatLng != null)
              Marker(
                point: _sourceLatLng!,
                width: 40,
                height: 50,
                alignment: Alignment.bottomCenter,
                child: _buildLocationPin(),
              ),
            for (int i = 0; i < _stops.length; i++)
              Marker(
                point: _stops[i],
                width: 40,
                height: 50,
                alignment: Alignment.bottomCenter,
                child: _buildStopMarker(i),
              ),
          ];
        });
        _moveCameraToFitAllMarkers();
      } else {
        final errorMsg = json['detailedError']?['message']
            ?? json['message']
            ?? 'No route found between these locations.';
        debugPrint('[TomTom] Routing error: $errorMsg');
        if (mounted) {
          CustomSnackbar.showError(context, 'Route error: $errorMsg');
          setState(() {
            _polylines.clear();
            _routeDistance = '--';
            _routeDuration = '--';
            _legInfo = [];
          });
        }
      }
    } catch (e, stack) {
      debugPrint('[TomTom] _getOptimizedRoute exception: $e\n$stack');
      if (mounted) {
        CustomSnackbar.showError(context, 'Failed to get route: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Builds a clean numbered pin widget for a stop marker (circle head + stem).
  Widget _buildStopMarker(int index) {
    final color = AppStyle.primaryColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: Center(
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Container(
          width: 3,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(2)),
          ),
        ),
      ],
    );
  }

  /// Periodically updates remaining distance/time from the current position to remaining stops.
  ///
  /// Re-queries Mapbox Directions API with current position as origin.
  /// Marks visited stops (within 50 m) and plays the reach-stop sound.
  Future<void> _updateRemainingDistanceAndTime() async {
    if (!_isNavigationStarted || _currentLatLng == null || _polylines.isEmpty) {
      setState(() {
        _remainingDistance = '--';
        _remainingDuration = '--';
        _remainingLegInfo = [];
      });
      return;
    }

    final List<LatLng> polylinePoints = _polylines.first.points;
    for (int i = 0; i < polylinePoints.length; i++) {
      mapService.distanceToSegment(
          _currentLatLng!, polylinePoints[i], polylinePoints[i]);
    }

    final List<LatLng> remainingPoints = List.from(_stops);
    final List<String> remainingNames = _stopSearchControllers
        .asMap()
        .entries
        .map((e) => e.value.text.isEmpty ? 'Stop ${e.key + 1}' : e.value.text)
        .toList();
    final List<bool> visitedStops = List.filled(_stops.length, false);
    int nextPointIndex = -1;
    double minDistanceToPoint = double.infinity;

    for (int i = 0; i < remainingPoints.length; i++) {
      final distance =
          mapService.distanceBetweenPoints(_currentLatLng!, remainingPoints[i]);
      if (distance <= 50) {
        visitedStops[i] = true;
        await mapService.playReachPointSound();
      } else if (distance < minDistanceToPoint) {
        minDistanceToPoint = distance;
        nextPointIndex = i;
      }
    }
    if (nextPointIndex == -1) nextPointIndex = remainingPoints.length - 1;

    if (remainingPoints.isEmpty) {
      if (mounted) {
        setState(() {
          _remainingDistance = '0 km';
          _remainingDuration = '0 min';
          _remainingLegInfo = [];
        });
      }
      return;
    }

    final travelMode = _getTomTomTravelMode(_selectedTravelMode);
    final allCoords = [
      '${_currentLatLng!.latitude},${_currentLatLng!.longitude}',
      ...remainingPoints.map((s) => '${s.latitude},${s.longitude}'),
    ];
    final url =
        'https://api.tomtom.com/routing/1/calculateRoute/${allCoords.join(':')}/json'
        '?travelMode=$travelMode&key=$_apiKey';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return;
      final json = jsonDecode(response.body);

      if (json['routes'] != null && (json['routes'] as List).isNotEmpty) {
        final legs = json['routes'][0]['legs'] as List;
        double totalDistance = 0;
        int totalDuration = 0;
        final List<Map<String, dynamic>> remainingLegInfo = [];

        for (int i = 0; i < legs.length; i++) {
          final legSummary = legs[i]['summary'];
          totalDistance += (legSummary['lengthInMeters'] as num).toDouble() / 1000;
          totalDuration += (legSummary['travelTimeInSeconds'] as num).toInt();

          final name = remainingNames[
              i < remainingNames.length ? i : remainingNames.length - 1];
          final latlng = remainingPoints[
              i < remainingPoints.length ? i : remainingPoints.length - 1];
          final isVisited = i < visitedStops.length ? visitedStops[i] : false;

          remainingLegInfo.add({
            'name': name,
            'distance': mapService.formatDistance(
                (legSummary['lengthInMeters'] as num).toDouble()),
            'duration': mapService.formatDuration(
                (legSummary['travelTimeInSeconds'] as num).toInt()),
            'latlng': latlng,
            'type': isVisited ? 'visited_stop' : 'stop',
          });
        }

        if (nextPointIndex > 0 && legs.isNotEmpty) {
          final firstLegSummary = legs[0]['summary'];
          remainingLegInfo.insert(0, {
            'name': 'Current Location',
            'distance': mapService.formatDistance(
                (firstLegSummary['lengthInMeters'] as num).toDouble()),
            'duration': mapService.formatDuration(
                (firstLegSummary['travelTimeInSeconds'] as num).toInt()),
            'latlng': _currentLatLng,
            'type': 'start',
          });
        }

        if (mounted) {
          setState(() {
            _remainingDistance = '${totalDistance.toStringAsFixed(1)} km';
            _remainingDuration = mapService.formatDuration(totalDuration);
            _remainingLegInfo = remainingLegInfo;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _remainingDistance = '--';
            _remainingDuration = '--';
            _remainingLegInfo = [];
          });
        }
      }
    } catch (e) {
      debugPrint('[TomTom] _updateRemainingDistanceAndTime error: $e');
      if (mounted) {
        setState(() {
          _remainingDistance = '--';
          _remainingDuration = '--';
          _remainingLegInfo = [];
        });
      }
    }
  }

  /// Animates camera to fit source + all stops with 60 px padding on each side.
  void _moveCameraToFitAllMarkers() {
    if (_sourceLatLng == null || _stops.isEmpty) return;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: [_sourceLatLng!, ..._stops],
        padding: const EdgeInsets.all(60),
      ),
    );
  }

  /// Requests location permission, gets current position, and sets it as the source.
  Future<void> _setInitialLocation() async {
    try {
      final location = Location();

      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          _useFallbackLocation();
          return;
        }
      }

      PermissionStatus permissionGranted = await location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          _useFallbackLocation();
          return;
        }
      }

      final currentLocation = await location.getLocation();
      final currentLatLng = LatLng(
        currentLocation.latitude!,
        currentLocation.longitude!,
      );

      if (!mounted) return;
      setState(() {
        _initialCameraPosition = currentLatLng;
        _isLoading = false;
        _currentLatLng = currentLatLng;
        _sourceLatLng = currentLatLng;
        sourceController.text = 'Your Location';
      });
      _addCurrentLocationMarker(currentLatLng);
    } catch (_) {
      _useFallbackLocation();
    }
  }

  /// Renders the map at a default center when the current location can't be
  /// obtained, so the page never gets stuck on the loading overlay. Tells the
  /// user (once) to set their source manually.
  void _useFallbackLocation() {
    if (!mounted || _initialCameraPosition != null) return;
    setState(() {
      _initialCameraPosition = _fallbackCenter;
      _isLoading = false;
    });
    if (!_locationNoticeShown) {
      _locationNoticeShown = true;
      CustomSnackbar.showWarning(
        context,
        'Location unavailable. Set your source manually in "Enter Route".',
      );
    }
  }

  /// Places a green location pin at [position] representing current/source location.
  void _addCurrentLocationMarker(LatLng position) {
    setState(() {
      _markers = [
        ..._markers.where((m) => m.point != position),
        Marker(
          point: position,
          width: 40,
          height: 50,
          alignment: Alignment.bottomCenter,
          child: _buildLocationPin(),
        ),
      ];
    });
  }

  /// Builds a teardrop pin (mobo color) for the current/source location.
  Widget _buildLocationPin() {
    const color = AppStyle.primaryColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: const Icon(Icons.person_pin_circle_outlined, color: Colors.white, size: 18),
        ),
        Container(
          width: 3,
          height: 10,
          decoration: const BoxDecoration(
            color: color,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(2)),
          ),
        ),
      ],
    );
  }

  /// Shows the modal bottom sheet for selecting pickings, source, and stops.
  ///
  /// Supports multi-select pickings (auto-fills stops from destination_point),
  /// source field with Mapbox autocomplete, and dynamic stop fields.
  void _showEnterRootPopup({bool fromAddStop = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool isDropdownActive = false;

    bool popCalled = false;
    bool needsAutoRoute = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        bool isFetchingStops = false;
        bool didAddStopField = false;

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter sheetSetState) {
            if (fromAddStop && !didAddStopField) {
              didAddStopField = true;
              if (_stopSearchControllers.last.text.trim().isNotEmpty) {
                _stopSearchControllers.add(TextEditingController());
                _stopSuggestions.add([]);
              }
            }

            final theme = Theme.of(context);
            final onSurface = theme.colorScheme.onSurface;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SafeArea(
                top: false,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  curve: Curves.easeInOut,
                  constraints: BoxConstraints(
                    minHeight: isDropdownActive
                        ? MediaQuery.of(context).size.height * 0.5
                        : MediaQuery.of(context).size.height * 0.25,
                  ),
                  child: Stack(
                    children: [
                      Padding(
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Enter Route',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      _fieldHeading('Pickings', isDark, isRequired: true),
                      Builder(
                        builder: (context) {
                          final selectedMaps = pickings
                              .where(
                                  (p) => selectedPickings.contains(p['id']))
                              .toList();
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              _showPickingSelectSheet(
                                pickings: pickings,
                                selectedIds: selectedPickings.toList(),
                                onConfirm: (value) async {
                                  sheetSetState(() => isFetchingStops = true);
                                  try {
                                    selectedPickings = value
                                        .map((e) => e['id'] as int)
                                        .toList();
                                    selectedPickingNames = value
                                        .map((e) => e['name'] as String)
                                        .toList();
                                    _stops.clear();
                                    for (var c in _stopSearchControllers) {
                                      c.dispose();
                                    }
                                    _stopSearchControllers.clear();
                                    _stopSuggestions.clear();

                                    final Set<String> uniqueDestinations = {};
                                    for (var picking in value) {
                                      final dest = picking['destination_point']
                                              as String? ??
                                          '';
                                      if (dest.isNotEmpty &&
                                          uniqueDestinations.add(dest)) {
                                        _stopSearchControllers.add(
                                            TextEditingController(text: dest));
                                        _stopSuggestions.add([]);
                                        final stopLatLng = await mapService
                                            .getLatLngFromPlace(dest, _apiKey,
                                                proximity: _currentLatLng);
                                        if (stopLatLng != null) {
                                          _stops.add(stopLatLng);
                                        }
                                      }
                                    }
                                    if (_stopSearchControllers.isEmpty ||
                                        _stopSearchControllers.last.text
                                            .trim()
                                            .isNotEmpty) {
                                      _stopSearchControllers
                                          .add(TextEditingController());
                                      _stopSuggestions.add([]);
                                    }
                                  } catch (_) {
                                  } finally {
                                    setState(() {});
                                    sheetSetState(() {
                                      shouldValidate = false;
                                      isFetchingStops = false;
                                    });
                                  }
                                },
                              );
                            },
                            child: Container(
                              decoration: _fieldShadow,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF2A2A2A)
                                      : const Color(0xffF8FAFB),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: selectedMaps.isEmpty
                                          ? Text(
                                              'Select Pickings',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: onSurface
                                                    .withValues(alpha: 0.5),
                                              ),
                                            )
                                          : Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: selectedMaps
                                                  .map((item) => _pickingTag(
                                                      item['name']
                                                              ?.toString() ??
                                                          ''))
                                                  .toList(),
                                            ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: onSurface.withValues(alpha: 0.6),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      if (shouldValidate) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Pickings cannot be empty',
                            style: TextStyle(
                              color: Colors.red[400],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 18),

                      _fieldHeading('Source Location', isDark),
                      Focus(
                        onFocusChange: (hasFocus) async {
                          if (!hasFocus) {
                            await Future.delayed(
                                const Duration(milliseconds: 150));
                            sheetSetState(() => _sourceSuggestions.clear());
                          }
                        },
                        child: MoboTextField(
                          controller: sourceController,
                          hintText: 'Search location',
                          onChanged: (value) async {
                            final suggestions = await mapService
                                .fetchSuggestions(value, _apiKey,
                                    proximity: _currentLatLng);
                            sheetSetState(() => _sourceSuggestions = [
                                  'Your Location',
                                  ...suggestions,
                                ]);
                          },
                        ),
                      ),
                      if (_sourceSuggestions.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[850] : Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _sourceSuggestions.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: onSurface.withValues(alpha: 0.08),
                            ),
                            itemBuilder: (context, index) {
                              return InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  final selected = _sourceSuggestions[index];
                                  sourceController.text = selected;
                                  sheetSetState(
                                      () => _sourceSuggestions.clear());
                                  if (selected == 'Your Location') {
                                    if (_currentLatLng != null) {
                                      setState(
                                          () => _sourceLatLng = _currentLatLng);
                                    }
                                  } else {
                                    _sourceLatLng = await mapService
                                        .getLatLngFromPlace(selected, _apiKey,
                                            proximity: _currentLatLng);
                                  }
                                  setState(() {});
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _sourceSuggestions[index] ==
                                                'Your Location'
                                            ? Icons.my_location
                                            : Icons.location_on_outlined,
                                        size: 18,
                                        color:
                                            onSurface.withValues(alpha: 0.5),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _sourceSuggestions[index],
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: onSurface,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                      ...List.generate(_stopSearchControllers.length, (index) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 18),
                              _fieldHeading('Stop ${index + 1}', isDark),
                              Focus(
                                onFocusChange: (hasFocus) async {
                                  if (!hasFocus) {
                                    await Future.delayed(
                                        const Duration(milliseconds: 150));
                                    if (index < _stopSuggestions.length) {
                                      sheetSetState(() =>
                                          _stopSuggestions[index].clear());
                                    }
                                  }
                                },
                                child: MoboTextField(
                                  controller: _stopSearchControllers[index],
                                  hintText: 'Add your stop',
                                  onChanged: (value) async {
                                    final suggestions = await mapService
                                        .fetchSuggestions(value, _apiKey,
                                            proximity: _currentLatLng);
                                    sheetSetState(() {
                                      if (_stopSuggestions.length <= index) {
                                        _stopSuggestions.add(suggestions);
                                      } else {
                                        _stopSuggestions[index] = suggestions;
                                      }
                                    });
                                  },
                                ),
                              ),
                              if (_stopSuggestions[index].isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.grey[850]
                                        : Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    padding: EdgeInsets.zero,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount:
                                        _stopSuggestions[index].length,
                                    separatorBuilder: (_, __) => Divider(
                                      height: 1,
                                      color:
                                          onSurface.withValues(alpha: 0.08),
                                    ),
                                    itemBuilder: (context, si) {
                                      return InkWell(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        onTap: () async {
                                          final nav = Navigator.of(context);
                                          _stopSearchControllers[index]
                                                  .text =
                                              _stopSuggestions[index][si];
                                          sheetSetState(() =>
                                              _stopSuggestions[index]
                                                  .clear());
                                          final stopLatLng = await mapService
                                              .getLatLngFromPlace(
                                            _stopSearchControllers[index]
                                                .text,
                                            _apiKey,
                                            proximity: _currentLatLng,
                                          );
                                          if (stopLatLng != null) {
                                            setState(() {
                                              if (_stops.length > index) {
                                                _stops[index] = stopLatLng;
                                              } else if (fromAddStop &&
                                                  _stops.isNotEmpty) {
                                                _stops.insert(0, stopLatLng);
                                                final ctrl =
                                                    _stopSearchControllers
                                                        .removeAt(index);
                                                _stopSearchControllers
                                                    .insert(0, ctrl);
                                                final sugg =
                                                    _stopSuggestions
                                                        .removeAt(index);
                                                _stopSuggestions.insert(
                                                    0, sugg);
                                              } else {
                                                _stops.add(stopLatLng);
                                              }
                                            });

                                            if (fromAddStop && mounted &&
                                                !popCalled) {
                                              needsAutoRoute = true;
                                              popCalled = true;
                                              nav.pop();
                                            }
                                          }
                                        },
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 14,
                                                  vertical: 12),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.location_on_outlined,
                                                size: 18,
                                                color: onSurface.withValues(
                                                    alpha: 0.5),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  _stopSuggestions[index]
                                                      [si],
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: onSurface,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              const SizedBox(height: 12),
                            ],
                          );
                        }),

                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                minimumSize:
                                    const Size(double.infinity, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                side: BorderSide(
                                    color: theme.primaryColor),
                                foregroundColor: theme.primaryColor,
                              ),
                              child: const Text(
                                'Cancel',
                                style:
                                    TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                minimumSize:
                                    const Size(double.infinity, 44),
                                backgroundColor: theme.primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                elevation: 0,
                              ),
                              onPressed: () async {
                                if (!fromAddStop && selectedPickings.isEmpty) {
                                  setState(
                                      () => shouldValidate = true);
                                  if (!popCalled) {
                                    popCalled = true;
                                    Navigator.of(context).pop(true);
                                  }
                                  _showEnterRootPopup();
                                  return;
                                }
                                needsAutoRoute = false;
                                if (!popCalled) {
                                  popCalled = true;
                                  Navigator.of(context).pop(true);
                                }
                                if (!mounted) return;
                                setState(() {
                                  _showLocationNames = true;
                                  _showOtherFABs = false;
                                  _showLayer = false;
                                  _showStopLocationFields = true;
                                  _infoCard = false;
                                  if (fromAddStop) {
                                    _isNavigationStarted = false;
                                  }
                                  sourceSearchController.text =
                                      sourceController.text;
                                });
                                await _getOptimizedRoute();
                                if (mounted) setState(() {});
                              },
                              icon: const Icon(
                                  HugeIcons.strokeRoundedNavigation03,
                                  size: 18),
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Show Directions',
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
                      ),
                      if (isFetchingStops)
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                            child: Container(
                              color: (isDark ? Colors.black : Colors.white)
                                  .withValues(alpha: 0.6),
                              child: const Center(
                                child: LoadingWidget(
                                  size: 40,
                                  variant: LoadingVariant.staggeredDots,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      if (!needsAutoRoute || !mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _showLocationNames = true;
          _showOtherFABs = false;
          _showLayer = false;
          _showStopLocationFields = true;
          _infoCard = false;
          _isNavigationStarted = false;
          sourceSearchController.text = sourceController.text;
        });
        _getOptimizedRoute();
      });
    });
  }

  /// Left-aligned static heading shown above an input box in the bottom sheet.
  /// When [isRequired] is true a red `*` marks the field as mandatory.
  Widget _fieldHeading(String text, bool isDark, {bool isRequired = false}) {
    final style = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: isDark ? Colors.white70 : Colors.black87,
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: RichText(
          text: TextSpan(
            text: text,
            style: style,
            children: isRequired
                ? const [
                    TextSpan(
                      text: ' *',
                      style: TextStyle(color: Color(0xFFD32F2F)),
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
  }

  /// Returns a borderless, filled [InputDecoration] matching the [MoboTextField]
  /// design — no resting border, soft fill, brand-colored focus ring. Used by
  /// the Pickings dropdown (and its search box) so it matches the text fields.
  InputDecoration _fieldDecoration(bool isDark, String label) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final fill = isDark ? const Color(0xFF2A2A2A) : const Color(0xffF8FAFB);
    OutlineInputBorder borderOf(Color color, double width) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: label,
      hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.5)),
      isDense: true,
      filled: true,
      fillColor: fill,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: borderOf(Colors.transparent, 0),
      enabledBorder: borderOf(Colors.transparent, 0),
      focusedBorder: borderOf(AppStyle.primaryColor, 1),
      errorBorder: borderOf(Colors.transparent, 0),
      focusedErrorBorder: borderOf(AppStyle.primaryColor, 1),
    );
  }

  /// Soft shadow used behind filled fields so they get the elevated
  /// "no border + shadow" look of [MoboTextField].
  BoxDecoration get _fieldShadow => BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            spreadRadius: 1,
            offset: const Offset(0, 3),
          ),
        ],
      );

  /// A pink (mobo) pill used to show a selected picking inside the Pickings
  /// field.
  Widget _pickingTag(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppStyle.primaryColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppStyle.primaryColor.withValues(alpha: 0.5),
        ),
      ),
      child: Text(
        name,
        style: const TextStyle(
          color: AppStyle.primaryColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Multi-select picker for pickings — mirrors the company-selection design
  /// (search box, mobo checkboxes, Reset/Confirm). Calls [onConfirm] with the
  /// chosen picking maps when the user confirms.
  void _showPickingSelectSheet({
    required List<Map<String, dynamic>> pickings,
    required List<int> selectedIds,
    required Future<void> Function(List<Map<String, dynamic>>) onConfirm,
  }) {
    final tempSelected = selectedIds.toSet();
    String query = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final isDark = Theme.of(sheetCtx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            final filtered = query.trim().isEmpty
                ? pickings
                : pickings.where((p) {
                    final name = (p['name']?.toString() ?? '').toLowerCase();
                    return name.contains(query.toLowerCase());
                  }).toList();

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetCtx).size.height * 0.8,
              ),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Select Pickings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        onChanged: (v) => setSheet(() => query = v),
                        decoration:
                            _fieldDecoration(isDark, 'Search Pickings'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No pickings found',
                                style: TextStyle(
                                  color:
                                      isDark ? Colors.white54 : Colors.black54,
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final p = filtered[index];
                                final id = p['id'] as int;
                                final name = p['name']?.toString() ?? '-';
                                final checked = tempSelected.contains(id);
                                return Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 4, 16, 4),
                                  child: Material(
                                    color: checked
                                        ? AppStyle.primaryColor
                                            .withValues(alpha: 0.08)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () => setSheet(() {
                                        if (checked) {
                                          tempSelected.remove(id);
                                        } else {
                                          tempSelected.add(id);
                                        }
                                      }),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 14),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                name,
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: checked
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                                  color: isDark
                                                      ? Colors.white
                                                      : Colors.black87,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            MoboCheckbox(
                                              size: 26,
                                              value: checked,
                                              onChanged: (val) =>
                                                  setSheet(() {
                                                if (val) {
                                                  tempSelected.add(id);
                                                } else {
                                                  tempSelected.remove(id);
                                                }
                                              }),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: MoboButton.secondary(
                              label: 'Reset',
                              height: 48,
                              onPressed: () =>
                                  setSheet(() => tempSelected.clear()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: MoboButton.primary(
                              label: 'Confirm',
                              height: 48,
                              onPressed: () async {
                                final value = pickings
                                    .where((p) =>
                                        tempSelected.contains(p['id']))
                                    .toList();
                                Navigator.pop(sheetCtx);
                                await onConfirm(value);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: _initialCameraPosition == null
          ? const LoadingOverlay()
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _initialCameraPosition!,
                    initialZoom: 15.0,
                    onPositionChanged: (position, hasGesture) {
                      if (hasGesture) {
                        setState(() => _isMapManuallyMoved = true);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      key: ValueKey(_currentMapStyle),
                      urlTemplate: _currentMapStyle == 'sat/main'
                          ? 'https://api.tomtom.com/map/1/tile/$_currentMapStyle/{z}/{x}/{y}.jpg?key=$_apiKey'
                          : 'https://api.tomtom.com/map/1/tile/$_currentMapStyle/{z}/{x}/{y}.png?key=$_apiKey',
                      userAgentPackageName: 'com.cybrosys.mobo_delivery',
                    ),
                    if (_polylines.isNotEmpty)
                      PolylineLayer(polylines: _polylines),
                    MarkerLayer(markers: [
                      ..._markers,
                      if (_movingMarker != null) _movingMarker!,
                    ]),
                  ],
                ),

                if (!isOnline)
                  ErrorStateWidget(
                    title: 'No Internet Connection',
                    message: 'Internet is not accessible. Please check your connection.',
                    onRetry: _initializeServices,
                  ),

                if (!_infoCard && _showLocationNames) ...[
                  Positioned(
                    top: 40,
                    left: 16,
                    right: 72,
                    child: SearchInputs(
                      sourceController: sourceSearchController,
                      stopControllers: _stopSearchControllers,
                      showStopFields: _showStopLocationFields,
                    ),
                  ),
                  Positioned(
                    top: 40,
                    right: 16,
                    child: GestureDetector(
                      onTap: _resetNavigation,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2C3E) : Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: isDark ? Colors.white70 : const Color(0xFF70757A),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: 16,
                    right: 16,
                    child: RouteInfoCard(
                      routeDuration: _routeDuration,
                      routeDistance: _routeDistance,
                      legInfo: _legInfo,
                      onStartPressed:
                          (_sourceLatLng != null && _stops.isNotEmpty)
                              ? _startNavigation
                              : null,
                      onAddStopPressed: () {
                        setState(() => _showStopLocationFields = true);
                        _showEnterRootPopup(fromAddStop: true);
                      },
                    ),
                  ),
                ],

                if (_isNavigationStarted) ...[
                  Positioned(
                    top: 40,
                    left: 16,
                    right: 16,
                    child: NavigationHeader(
                      onClose: _resetNavigation,
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    bottom: _showRemainingInfo ? 20 : -300,
                    left: 16,
                    right: 16,
                    child: RemainingInfoCard(
                      remainingDistance: _remainingDistance,
                      remainingDuration: _remainingDuration,
                      remainingLegInfo: _remainingLegInfo,
                      onFocusPressed: (latLng) {
                        if (latLng != null) {
                          _mapController.move(latLng, 15);
                          setState(() => _isMapManuallyMoved = true);
                        }
                      },
                      onAddRoutePressed: () {
                        setState(() {
                          _showStopLocationFields = true;
                          _infoCard = true;
                        });
                        _showEnterRootPopup(fromAddStop: true);
                      },
                    ),
                  ),
                ],

                if (_isLoading)
                  Container(
                    color: Colors.black.withValues(alpha: 0.5),
                    child: const Center(
                      child: LoadingWidget(
                        size: 40,
                        variant: LoadingVariant.staggeredDots,
                      ),
                    ),
                  ),
              ],
            ),

      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_showOtherFABs) ...[
            FloatingActionButton(
              heroTag: 'routeEnterRoot',
              backgroundColor: isDark ? const Color(0xFF2C2C3E) : Colors.white,
              foregroundColor: AppStyle.primaryColor,
              elevation: 4,
              onPressed: _showEnterRootPopup,
              child: const Icon(HugeIcons.strokeRoundedRoute03),
            ),
            const SizedBox(height: 10),
            FloatingActionButton(
              heroTag: 'routeRecenterInitial',
              backgroundColor: isDark ? const Color(0xFF2C2C3E) : Colors.white,
              foregroundColor: AppStyle.primaryColor,
              elevation: 4,
              onPressed: () {
                if (_initialCameraPosition != null) {
                  _mapController.move(_initialCameraPosition!, 15.0);
                }
              },
              child: const Icon(HugeIcons.strokeRoundedCenterFocus),
            ),
            const SizedBox(height: 10),
          ],
          if (_showLayer)
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (!_showOtherFABs)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, child) => ClipRect(
                      child: Align(
                        alignment: Alignment.centerRight,
                        widthFactor: v,
                        child: child,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildMapTypeIcon('basic/main',
                            HugeIcons.strokeRoundedMaps, 'Normal'),
                        _buildMapTypeIcon('sat/main',
                            HugeIcons.strokeRoundedSatellite02, 'Satellite'),
                        _buildMapTypeIcon('basic/night',
                            HugeIcons.strokeRoundedMountain, 'Night'),
                        _buildMapTypeIcon('hybrid/main',
                            HugeIcons.strokeRoundedGlobe02, 'Hybrid'),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                FloatingActionButton(
                  backgroundColor:
                      isDark ? const Color(0xFF2C2C3E) : Colors.white,
                  foregroundColor: AppStyle.primaryColor,
                  elevation: 4,
                  heroTag: 'mapTypeToggle',
                  tooltip: 'Change Map Style',
                  onPressed: () =>
                      setState(() => _showOtherFABs = !_showOtherFABs),
                  child: const Icon(HugeIcons.strokeRoundedGlobal),
                ),
              ],
            ),
          if (_isNavigationStarted) ...[
            const SizedBox(height: 10),
            FloatingActionButton(
              heroTag: 'routeToggleRemainingInfo',
              backgroundColor: isDark ? const Color(0xFF2C2C3E) : Colors.white,
              foregroundColor: AppStyle.primaryColor,
              elevation: 4,
              tooltip: _showRemainingInfo
                  ? 'Hide Remaining Route'
                  : 'Show Remaining Route',
              onPressed: () =>
                  setState(() => _showRemainingInfo = !_showRemainingInfo),
              child: Icon(
                _showRemainingInfo ? Icons.visibility_off : Icons.visibility,
              ),
            ),
            if (_isMapManuallyMoved && _currentLatLng != null) ...[
              const SizedBox(height: 10),
              FloatingActionButton(
                heroTag: 'routeRecenterCurrent',
                backgroundColor: isDark ? const Color(0xFF2C2C3E) : Colors.white,
                foregroundColor: const Color(0xFF1A73E8),
                elevation: 4,
                tooltip: 'Re-center on current location',
                onPressed: () {
                  _mapController.move(_currentLatLng!, 17.0);
                  setState(() => _isMapManuallyMoved = false);
                },
                child: const Icon(Icons.my_location),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Starts live navigation: subscribes to GPS, starts the periodic distance timer.
  Future<void> _startNavigation() async {
    setState(() => _isLoading = true);
    setState(() {
      _isNavigationStarted = true;
      _isMapManuallyMoved = false;
      _movingMarker = null;
      _markers = [
        for (int i = 0; i < _stops.length; i++)
          Marker(
            point: _stops[i],
            width: 40,
            height: 50,
            alignment: Alignment.bottomCenter,
            child: _buildStopMarker(i),
          ),
      ];
    });

    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _isLoading = false);
          CustomSnackbar.showWarning(
            context,
            'Turn on location to start live navigation.',
          );
        }
        return;
      }
    }

    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        if (mounted) {
          setState(() => _isLoading = false);
          CustomSnackbar.showWarning(
            context,
            'Location permission is required for live navigation.',
          );
        }
        return;
      }
    }

    _locationSubscription?.cancel();
    LatLng? lastPosition;
    List<LatLng> currentPolylinePoints =
        _polylines.isNotEmpty ? _polylines.first.points : [];

    _locationSubscription =
        _location.onLocationChanged.listen((locationData) async {
      if (locationData.latitude == null || locationData.longitude == null) {
        return;
      }
      final currentLatLng = LatLng(
        locationData.latitude!,
        locationData.longitude!,
      );
      double bearing = _lastBearing;

      if (lastPosition != null && _isPhoneRotated) {
        bearing = mapService.calculateBearing(lastPosition!, currentLatLng);
      }

      if (currentPolylinePoints.isNotEmpty) {
        final distance = mapService.distanceToPolyline(
            currentLatLng, currentPolylinePoints);
        if (distance > 50.0) {
          setState(() {
            _sourceLatLng = currentLatLng;
            sourceController.text = 'Your Location';
          });
          await _getOptimizedRoute();
          currentPolylinePoints =
              _polylines.isNotEmpty ? _polylines.first.points : [];
          if (_polylines.isEmpty) {
            await mapService.playWrongPathSound();
          }
        }
      }

      setState(() {
        _movingMarker = Marker(
          point: currentLatLng,
          width: 40,
          height: 40,
          child: Transform.rotate(
            angle: bearing * math.pi / 180,
            child: _navigationIcon!,
          ),
        );
        _currentLatLng = currentLatLng;
      });

      if (!_isMapManuallyMoved) {
        _mapController.move(currentLatLng, 17.0);
      }

      lastPosition = currentLatLng;
      _lastBearing = bearing;
    });

    _distanceUpdateTimer?.cancel();
    _distanceUpdateTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _updateRemainingDistanceAndTime(),
    );
    await _updateRemainingDistanceAndTime();

    if (mounted) {
      setState(() {
        _showLocationNames = false;
        _isLoading = false;
      });
    }
  }

  /// Resets all navigation state back to the idle map view.
  void _resetNavigation() {
    setState(() {
      _isNavigationStarted = false;
      _infoCard = false;
      _routeDuration = '';
      _routeDistance = '';
      _remainingDuration = '';
      _remainingDistance = '';
      _selectedTravelMode = 'driving';
      _showLocationNames = false;
      _showLayer = true;
      _showOtherFABs = true;
      _polylines.clear();
      _markers.clear();
      _movingMarker = null;
      _legInfo = [];
      _remainingLegInfo = [];
      _locationSubscription?.cancel();
      _distanceUpdateTimer?.cancel();
      for (final c in _stopSearchControllers) {
        c.dispose();
      }
      _stopSearchControllers
        ..clear()
        ..add(TextEditingController());
      sourceController.text = 'Your Location';
      selectedPickings.clear();
      selectedPickingNames.clear();
      _showStopLocationFields = false;
      _stops.clear();
      if (_currentLatLng != null) {
        _addCurrentLocationMarker(_currentLatLng!);
        _mapController.move(_currentLatLng!, 15);
      }
    });
  }

  /// Builds a small style-selection FAB with white background.
  Widget _buildMapTypeIcon(String style, IconData icon, String tooltip) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive = _currentMapStyle == style;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: FloatingActionButton.small(
        heroTag: tooltip,
        tooltip: tooltip,
        backgroundColor: isActive
            ? AppStyle.primaryColor
            : (isDark ? const Color(0xFF2C2C3E) : Colors.white),
        foregroundColor: isActive
            ? Colors.white
            : (isDark ? Colors.white70 : const Color(0xFF5F6368)),
        elevation: 3,
        onPressed: () {
          setState(() {
            _currentMapStyle = style;
            _showOtherFABs = true;
          });
        },
        child: Icon(icon),
      ),
    );
  }

}
