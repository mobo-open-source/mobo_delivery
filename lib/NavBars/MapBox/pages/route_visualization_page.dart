import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:dropdown_search/dropdown_search.dart';
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

  /// Current Mapbox style ID (streets-v11, satellite-v9, outdoors-v11, satellite-streets-v11).
  String _currentMapStyle = 'streets-v11';
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
    _apiKey = dotenv.env['MAPBOX_ACCESS_TOKEN'] ?? '';
    _initializeServices();
    _setInitialLocation();
    _loadCustomMarker();
    _listenToGyroscope();
  }

  /// Initializes Odoo client, checks connectivity, fetches pickings.
  /// Overrides the Mapbox token with an Odoo-configured value if available.
  Future<void> _initializeServices() async {
    isOnline = await odooService.checkNetworkConnectivity();
    await odooService.initializeOdooClient();
    pickings = await odooService.fetchStockPickings();
    try {
      final token = await odooService.getMapToken();
      if (token.isNotEmpty) _apiKey = token;
    } catch (_) {
      // Use .env token as fallback; non-critical.
    }
    if (_apiKey.isEmpty && mounted) {
      CustomSnackbar.showError(
        context,
        'Mapbox token not configured. Set MAPBOX_ACCESS_TOKEN in .env or Profile settings.',
      );
    }
    if (mounted) setState(() {});
  }

  /// Listens to gyroscope events to detect phone rotation (used for bearing updates).
  void _listenToGyroscope() {
    _gyroscopeSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
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

  /// Maps internal travel mode string to the corresponding Mapbox routing profile.
  String _getMapboxProfile(String travelMode) {
    switch (travelMode) {
      case 'walking':
        return 'walking';
      case 'bicycling':
        return 'cycling';
      default:
        return 'driving-traffic';
    }
  }

  /// Calculates route using Mapbox Directions API.
  ///
  /// Flow:
  ///   1. Builds coordinates string: origin + ordered stops (lng,lat format)
  ///   2. Calls Mapbox Directions API with polyline geometry
  ///   3. Decodes polyline → draws route overlay
  ///   4. Computes total distance/duration + leg-by-leg info
  ///   5. Places start/stop markers on the map
  ///   6. Fits camera bounds to show entire route
  Future<void> _getOptimizedRoute() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // Guard: token must be present.
      if (_apiKey.isEmpty) {
        CustomSnackbar.showError(context,
            'Mapbox token is missing. Check .env or Profile settings.');
        return;
      }

      // Guard: source + at least one stop required.
      if (_sourceLatLng == null) {
        CustomSnackbar.showError(
            context, 'Source location not set. Enable GPS or enter manually.');
        return;
      }
      if (_stops.isEmpty) {
        CustomSnackbar.showError(
            context, 'No stops found. Select a picking or add a stop manually.');
        return;
      }

      // Mapbox coordinates: longitude first, semicolon-separated.
      final allCoords = [
        '${_sourceLatLng!.longitude},${_sourceLatLng!.latitude}',
        ..._stops.map((s) => '${s.longitude},${s.latitude}'),
      ];
      final profile = _getMapboxProfile(_selectedTravelMode);
      final url =
          'https://api.mapbox.com/directions/v5/mapbox/$profile/${allCoords.join(';')}'
          '?geometries=polyline&overview=full&steps=false&access_token=$_apiKey';

      debugPrint('[MapBox] Directions URL: $url');

      final response = await http.get(Uri.parse(url));
      debugPrint('[MapBox] Directions response (${response.statusCode}): ${response.body.substring(0, response.body.length.clamp(0, 300))}');

      if (response.statusCode != 200) {
        if (mounted) {
          CustomSnackbar.showError(
              context, 'Route request failed (HTTP ${response.statusCode}).');
        }
        return;
      }

      final json = jsonDecode(response.body);

      if (json['code'] == 'Ok' &&
          json['routes'] != null &&
          (json['routes'] as List).isNotEmpty) {
        final route = json['routes'][0];
        final polylinePoints =
            mapService.decodePolyline(route['geometry'] as String);

        if (polylinePoints.isEmpty) {
          if (mounted) {
            CustomSnackbar.showError(context, 'Route geometry could not be decoded.');
          }
          return;
        }

        final legs = route['legs'] as List;

        double totalDistance = 0;
        int totalDuration = 0;
        final List<Map<String, String>> legInfo = [];

        // First leg: source → stop 0.
        legInfo.add({
          'start_address': sourceController.text.isEmpty
              ? 'Your Location'
              : sourceController.text,
          'end_address': _stopSearchControllers.isNotEmpty &&
                  _stopSearchControllers[0].text.isNotEmpty
              ? _stopSearchControllers[0].text
              : 'Stop 1',
          'distance':
              mapService.formatDistance((legs[0]['distance'] as num).toDouble()),
          'duration':
              mapService.formatDuration((legs[0]['duration'] as num).toInt()),
        });
        totalDistance += (legs[0]['distance'] as num).toDouble() / 1000;
        totalDuration += (legs[0]['duration'] as num).toInt();

        // Subsequent legs.
        for (int i = 1; i < legs.length; i++) {
          final leg = legs[i];
          totalDistance += (leg['distance'] as num).toDouble() / 1000;
          totalDuration += (leg['duration'] as num).toInt();
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
                mapService.formatDistance((leg['distance'] as num).toDouble()),
            'duration':
                mapService.formatDuration((leg['duration'] as num).toInt()),
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
        // API returned an error code — show it to the user.
        final errorCode = json['code'] ?? 'Unknown';
        final errorMsg = json['message'] ?? 'No route found between these locations.';
        debugPrint('[MapBox] Directions error: code=$errorCode, message=$errorMsg');
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
      debugPrint('[MapBox] _getOptimizedRoute exception: $e\n$stack');
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

    final profile = _getMapboxProfile(_selectedTravelMode);
    final allCoords = [
      '${_currentLatLng!.longitude},${_currentLatLng!.latitude}',
      ...remainingPoints.map((s) => '${s.longitude},${s.latitude}'),
    ];
    final url =
        'https://api.mapbox.com/directions/v5/mapbox/$profile/${allCoords.join(';')}'
        '?geometries=polyline&overview=full&access_token=$_apiKey';

    try {
      final response = await http.get(Uri.parse(url));
      final json = jsonDecode(response.body);

      if (json['code'] == 'Ok' && (json['routes'] as List).isNotEmpty) {
        final legs = json['routes'][0]['legs'] as List;
        double totalDistance = 0;
        int totalDuration = 0;
        final List<Map<String, dynamic>> remainingLegInfo = [];

        for (int i = 0; i < legs.length; i++) {
          final leg = legs[i];
          totalDistance += (leg['distance'] as num).toDouble() / 1000;
          totalDuration += (leg['duration'] as num).toInt();

          final name = remainingNames[
              i < remainingNames.length ? i : remainingNames.length - 1];
          final latlng = remainingPoints[
              i < remainingPoints.length ? i : remainingPoints.length - 1];
          final isVisited = i < visitedStops.length ? visitedStops[i] : false;

          remainingLegInfo.add({
            'name': name,
            'distance': mapService.formatDistance(
                (leg['distance'] as num).toDouble()),
            'duration': mapService.formatDuration(
                (leg['duration'] as num).toInt()),
            'latlng': latlng,
            'type': isVisited ? 'visited_stop' : 'stop',
          });
        }

        if (nextPointIndex > 0 && legs.isNotEmpty) {
          remainingLegInfo.insert(0, {
            'name': 'Current Location',
            'distance': mapService.formatDistance(
                (legs[0]['distance'] as num).toDouble()),
            'duration': mapService.formatDuration(
                (legs[0]['duration'] as num).toInt()),
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
      debugPrint('[MapBox] _updateRemainingDistanceAndTime error: $e');
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
    final location = Location();

    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) return;
    }

    PermissionStatus permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return;
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

  /// Builds a green teardrop pin for the current/source location.
  Widget _buildLocationPin() {
    const color = Color(0xFF2ECC71);
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        bool isFetchingStops = false;
        // Guard: only add new stop field ONCE when popup opens, not on every
        // StatefulBuilder rebuild (which would create duplicate empty fields).
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
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      // Drag handle
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

                      // Pickings multi-select dropdown.
                      DropdownSearch<Map<String, dynamic>>.multiSelection(
                        popupProps: PopupPropsMultiSelection.menu(
                          showSearchBox: true,
                          selectionWidget: (context, item, isSelected) {
                            return Checkbox(
                              value: isSelected,
                              onChanged: (_) {},
                              activeColor: AppStyle.primaryColor,
                              checkColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            );
                          },
                          searchFieldProps: TextFieldProps(
                            decoration:
                                _fieldDecoration(isDark, 'Search Pickings'),
                          ),
                          onDismissed: () =>
                              sheetSetState(() => isDropdownActive = false),
                        ),
                        onBeforePopupOpening: (_) async {
                          sheetSetState(() => isDropdownActive = true);
                          return true;
                        },
                        items: pickings,
                        itemAsString: (item) => item?['name'] ?? '',
                        selectedItems: pickings
                            .where((p) => selectedPickings.contains(p['id']))
                            .toList(),
                        onChanged: (List<Map<String, dynamic>> value) async {
                          sheetSetState(() => isFetchingStops = true);
                          try {
                            selectedPickings =
                                value.map((e) => e['id'] as int).toList();
                            selectedPickingNames =
                                value.map((e) => e['name'] as String).toList();
                            _stops.clear();
                            for (var c in _stopSearchControllers) {
                              c.dispose();
                            }
                            _stopSearchControllers.clear();
                            _stopSuggestions.clear();

                            final Set<String> uniqueDestinations = {};
                            for (var picking in value) {
                              final dest =
                                  picking['destination_point'] as String? ?? '';
                              if (dest.isNotEmpty &&
                                  uniqueDestinations.add(dest)) {
                                _stopSearchControllers.add(
                                    TextEditingController(text: dest));
                                _stopSuggestions.add([]);
                                try {
                                  final stopLatLng =
                                      await mapService.getLatLngFromPlace(
                                          dest, _apiKey,
                                          proximity: _currentLatLng);
                                  if (stopLatLng != null) {
                                    _stops.add(stopLatLng);
                                  }
                                } catch (_) {
                                  if (context.mounted) {
                                    Navigator.of(context).pop(true);
                                    setState(() => selectedPickings.clear());
                                    CustomSnackbar.showError(
                                      context,
                                      'Could not fetch location. Check Mapbox token or server.',
                                    );
                                  }
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
                            if (context.mounted) {
                              Navigator.of(context).pop(true);
                              CustomSnackbar.showError(
                                context,
                                'Something went wrong while choosing pickings.',
                              );
                            }
                          } finally {
                            setState(() {});
                            sheetSetState(() {
                              shouldValidate = false;
                              isFetchingStops = false;
                            });
                          }
                        },
                        dropdownDecoratorProps: DropDownDecoratorProps(
                          dropdownSearchDecoration:
                              _fieldDecoration(isDark, 'Select Pickings'),
                        ),
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

                      const SizedBox(height: 12),

                      // Source location field with Mapbox autocomplete.
                      TextField(
                        controller: sourceController,
                        style: TextStyle(fontSize: 14, color: onSurface),
                        decoration: _fieldDecoration(
                            isDark, 'Source Location'),
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

                      if (isFetchingStops)
                        const Center(
                          child: LoadingWidget(
                            size: 30,
                            variant: LoadingVariant.staggeredDots,
                          ),
                        ),

                      // Stop fields with Mapbox autocomplete.
                      if (selectedPickings.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        ...List.generate(_stopSearchControllers.length, (index) {
                          return Column(
                            children: [
                              TextField(
                                controller: _stopSearchControllers[index],
                                style: TextStyle(
                                    fontSize: 14, color: onSurface),
                                decoration: _fieldDecoration(
                                  isDark,
                                  _stopSearchControllers[index]
                                          .text
                                          .trim()
                                          .isEmpty
                                      ? 'Add your stop'
                                      : 'Stop ${index + 1}',
                                ),
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
                                                final insertAt =
                                                    _stops.length - 1;
                                                _stops.insert(
                                                    insertAt, stopLatLng);
                                                final ctrl =
                                                    _stopSearchControllers
                                                        .removeAt(index);
                                                final sugg =
                                                    _stopSuggestions
                                                        .removeAt(index);
                                                _stopSearchControllers
                                                    .insert(
                                                        _stopSearchControllers
                                                                .length -
                                                            1,
                                                        ctrl);
                                                _stopSuggestions.insert(
                                                    _stopSuggestions
                                                            .length -
                                                        1,
                                                    sugg);
                                              } else {
                                                _stops.add(stopLatLng);
                                              }
                                            });
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
                      ],

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
                                if (selectedPickings.isEmpty) {
                                  setState(
                                      () => shouldValidate = true);
                                  Navigator.of(context).pop(true);
                                  _showEnterRootPopup();
                                  return;
                                }
                                Navigator.of(context).pop(true);
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
                                setState(() {});
                              },
                              icon: const Icon(
                                  HugeIcons.strokeRoundedNavigation03,
                                  size: 18),
                              label: const Text(
                                'Show Directions',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600),
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
            ),
            ),
            );
          },
        );
      },
    );
  }

  /// Returns a consistent [InputDecoration] for text fields in the bottom sheet.
  InputDecoration _fieldDecoration(bool isDark, String label) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final surfaceVariant = Theme.of(context).colorScheme.surfaceContainerHighest;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: onSurface.withValues(alpha: 0.7)),
      isDense: true,
      filled: true,
      fillColor: isDark ? surfaceVariant : Colors.grey[50],
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: onSurface),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: onSurface.withValues(alpha: 0.4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: onSurface, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: onSurface.withValues(alpha: 0.4)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: onSurface, width: 1.5),
      ),
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
                // ── Mapbox tile map ──────────────────────────────────────────
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
                      urlTemplate:
                          'https://api.mapbox.com/styles/v1/mapbox/$_currentMapStyle'
                          '/tiles/256/{z}/{x}/{y}@2x?access_token=$_apiKey',
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

                // ── Offline warning ──────────────────────────────────────────
                if (!isOnline)
                  ErrorStateWidget(
                    title: 'No Internet Connection',
                    message: 'Internet is not accessible. Please check your connection.',
                    onRetry: _initializeServices,
                  ),

                // ── Route planning overlays ──────────────────────────────────
                if (!_infoCard && _showLocationNames) ...[
                  Positioned(
                    top: 40,
                    left: 16,
                    right: 80,
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
                      selectedTravelMode: _selectedTravelMode,
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
                      onTravelModeChanged: (mode) {
                        setState(() => _selectedTravelMode = mode);
                        _getOptimizedRoute();
                      },
                    ),
                  ),
                ],

                // ── Active navigation overlays ───────────────────────────────
                if (_isNavigationStarted) ...[
                  Positioned(
                    top: 40,
                    left: 16,
                    right: 16,
                    child: NavigationHeader(
                      selectedTravelMode: _selectedTravelMode,
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

                // ── Loading overlay ──────────────────────────────────────────
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

      // ── FABs ──────────────────────────────────────────────────────────────
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_showOtherFABs) ...[
            FloatingActionButton(
              backgroundColor: isDark ? const Color(0xFF2C2C3E) : Colors.white,
              foregroundColor: AppStyle.primaryColor,
              elevation: 4,
              onPressed: _showEnterRootPopup,
              child: const Icon(HugeIcons.strokeRoundedRoute03),
            ),
            const SizedBox(height: 10),
            FloatingActionButton(
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
                // Style buttons slide in from right when popup is open
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
                        _buildMapTypeIcon('streets-v11',
                            HugeIcons.strokeRoundedMaps, 'Normal'),
                        _buildMapTypeIcon('satellite-v9',
                            HugeIcons.strokeRoundedSatellite02, 'Satellite'),
                        _buildMapTypeIcon('outdoors-v11',
                            HugeIcons.strokeRoundedMountain, 'Terrain'),
                        _buildMapTypeIcon('satellite-streets-v11',
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
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    }

    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        if (mounted) setState(() => _isLoading = false);
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

      // Off-route detection.
      if (currentPolylinePoints.isNotEmpty) {
        final distance = mapService.distanceToPolyline(
            currentLatLng, currentPolylinePoints);
        if (distance > 50.0) {
          setState(() {
            _sourceLatLng = currentLatLng;
            sourceController.text = 'Your Location';
          });
          currentPolylinePoints =
              _polylines.isNotEmpty ? _polylines.first.points : [];
          if (_polylines.isEmpty) {
            await mapService.playWrongPathSound();
          }
        }
      }

      // Update live navigation marker with bearing rotation.
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
