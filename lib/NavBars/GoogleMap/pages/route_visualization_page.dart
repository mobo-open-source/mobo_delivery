import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:location/location.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:http/http.dart' as http;
import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/snackbar.dart';
import '../services/map_service.dart';
import '../services/odoo_map_service.dart';
import '../widgets/navigation_header.dart';
import '../widgets/remaining_info_card.dart';
import '../widgets/route_info_card.dart';
import '../widgets/search_inputs.dart';

/// Full-screen page for route planning and real-time navigation visualization.
///
/// Features:
///   - Select multiple stock pickings → auto-populate stops from destination points
///   - Source location (defaults to current GPS or manual entry)
///   - Google Directions API route calculation with waypoints optimization
///   - Live location tracking with custom blue dot marker & bearing
///   - Remaining distance/time updates + leg-by-leg info
///   - Map type switching, manual camera control, offline warning
///   - Gyroscope-based rotation detection (for bearing adjustment)
class RouteVisualizationPage extends StatefulWidget {
  const RouteVisualizationPage({super.key});

  @override
  State<RouteVisualizationPage> createState() => _RouteVisualizationPageState();
}

/// Manages map controller, location tracking, route calculation, markers/polylines,
/// UI overlays, navigation state, and real-time updates.
///
/// Responsibilities:
///   - Initialize location services, custom marker, gyroscope listener
///   - Fetch pickings from Odoo and populate stop fields
///   - Calculate & display optimized route (Google Directions API)
///   - Track user location, update blue dot marker + bearing
///   - Periodically refresh remaining distance/time
///   - Handle offline mode, map type switching, stop addition
class _RouteVisualizationPageState extends State<RouteVisualizationPage> {
  final OdooMapService odooService = OdooMapService();
  final MapService mapService = MapService();

  CameraPosition? _initialCameraPosition;
  late GoogleMapController _googleMapController;
  final TextEditingController sourceController = TextEditingController();
  final TextEditingController sourceSearchController = TextEditingController();
  final List<TextEditingController> _stopSearchControllers = [
    TextEditingController(),
  ];
  final List<List<String>> _stopSuggestions = [[]];
  bool _showLocationNames = false;
  final Set<Marker> _markers = {};
  List<String> _sourceSuggestions = [];
  final List<LatLng> _stops = [];
  LatLng? _sourceLatLng;
  Set<Polyline> _polylines = {};
  MapType _currentMapType = MapType.normal;
  OverlayEntry? _mapTypeOverlayEntry;
  bool _showOtherFABs = true;
  String _routeDuration = '';
  String _routeDistance = '';
  List<Map<String, String>> _legInfo = [];
  String _selectedTravelMode = 'driving';
  StreamSubscription<LocationData>? _locationSubscription;
  Location _location = Location();
  double _lastBearing = 0.0;
  BitmapDescriptor? _navigationIcon;
  StreamSubscription? _gyroscopeSubscription;
  bool _isPhoneRotated = false;
  LatLng? _currentLatLng;
  bool _showLayer = true;
  List<Map<String, dynamic>> pickings = [];
  List<int> selectedPickings = [];
  List<String> selectedPickingNames = [];
  bool shouldValidate = false;
  bool _isMapManuallyMoved = false;
  Timer? _blinkTimer;
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

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _setInitialLocation();
    _loadCustomMarker();
    _listenToGyroscope();
  }

  /// Initializes Odoo client, checks connectivity, fetches pickings.
  Future<void> _initializeServices() async {
    isOnline = await odooService.checkNetworkConnectivity();
    await odooService.initializeOdooClient();
    pickings = await odooService.fetchStockPickings();
    setState(() {});
  }

  /// Listens to gyroscope events to detect phone rotation (used for bearing).
  void _listenToGyroscope() {
    _gyroscopeSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
      if (event.z.abs() > 0.5) {
        _isPhoneRotated = true;
      } else {
        _isPhoneRotated = false;
      }
    });
  }

  @override
  void dispose() {
    _googleMapController.dispose();
    _locationSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _blinkTimer?.cancel();
    _distanceUpdateTimer?.cancel();
    sourceController.dispose();
    sourceSearchController.dispose();
    for (var controller in _stopSearchControllers) {
      controller.dispose();
    }
    mapService.audioPlayer.dispose();
    super.dispose();
  }

  /// Loads custom blue dot navigation icon from assets.
  void _loadCustomMarker() async {
    _navigationIcon = await mapService.createBlueDotMarker(1.0);
    setState(() {});
  }

  /// Calculates optimized route using Google Directions API with waypoints.
  ///
  /// Flow:
  ///   1. Builds origin, destination, waypoints string
  ///   2. Calls Directions API (driving/walking/etc. mode)
  ///   3. Decodes polyline → draws route
  ///   4. Calculates total distance/duration + leg-by-leg info
  ///   5. Places start/stop markers
  ///   6. Fits camera bounds to show entire route
  Future<void> _getOptimizedRoute() async {
    setState(() {
      _isLoading = true;
    });
    try {
      if (_sourceLatLng == null || _stops.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }
      final String apiKey = await odooService.getMapToken();
      String origin = '${_sourceLatLng!.latitude},${_sourceLatLng!.longitude}';
      String destination = '${_stops.last.latitude},${_stops.last.longitude}';

      String waypoints = '';
      if (_stops.length > 1) {
        List<String> stopCoords = _stops
            .sublist(0, _stops.length - 1)
            .map((s) => '${s.latitude},${s.longitude}')
            .toList();
        waypoints = '&waypoints=optimize:true|${stopCoords.join('|')}';
      }

      final String url =
          'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination$waypoints&mode=$_selectedTravelMode&key=$apiKey';

      final response = await http.get(Uri.parse(url));
      final json = jsonDecode(response.body);
      if (json['status'] == 'OK') {
        final route = json['routes'][0];
        final overviewPolyline = route['overview_polyline']['points'];
        final polylinePoints = mapService.decodePolyline(overviewPolyline);
        final legs = route['legs'];

        double totalDistance = 0;
        int totalDuration = 0;
        List<Map<String, String>> legInfo = [];

        legInfo.add({
          'start_address': sourceController.text.isEmpty
              ? 'Your Location'
              : sourceController.text,
          'end_address': _stopSearchControllers[0].text.isEmpty
              ? 'Stop 1'
              : _stopSearchControllers[0].text,
          'distance': legs[0]['distance']['text'],
          'duration': legs[0]['duration']['text'],
        });

        totalDistance += legs[0]['distance']['value'] / 1000;
        totalDuration += (legs[0]['duration']['value'] as num).toInt();

        for (int i = 1; i < legs.length; i++) {
          final leg = legs[i];
          totalDistance += leg['distance']['value'] / 1000;
          totalDuration += (leg['duration']['value'] as num).toInt();

          String startAddress = _stopSearchControllers[i - 1].text.isEmpty
              ? 'Stop $i'
              : _stopSearchControllers[i - 1].text;
          String endAddress = _stopSearchControllers[i].text.isEmpty
              ? 'Stop ${i + 1}'
              : _stopSearchControllers[i].text;

          legInfo.add({
            'start_address': startAddress,
            'end_address': endAddress,
            'distance': leg['distance']['text'],
            'duration': leg['duration']['text'],
          });
        }

        String formattedDistance = '${totalDistance.toStringAsFixed(1)} km';
        String formattedDuration = mapService.formatDuration(totalDuration);

        setState(() {
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              color: Colors.blue[900]!,
              width: 10,
              points: polylinePoints,
            ),
          );

          _routeDistance = formattedDistance;
          _routeDuration = formattedDuration;
          _remainingDistance = formattedDistance;
          _remainingDuration = formattedDuration;
          _legInfo = legInfo;

          _markers.clear();
          if (_sourceLatLng != null) {
            _markers.add(
              Marker(
                markerId: const MarkerId('start'),
                position: _sourceLatLng!,
                infoWindow: const InfoWindow(title: 'Start'),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen,
                ),
              ),
            );
          }

          for (int i = 0; i < _stops.length; i++) {
            _markers.add(
              Marker(
                markerId: MarkerId('stop$i'),
                position: _stops[i],
                infoWindow: InfoWindow(
                  title: _stopSearchControllers[i].text.isEmpty
                      ? 'Stop ${i + 1}'
                      : _stopSearchControllers[i].text,
                ),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueOrange,
                ),
              ),
            );
          }
        });
        _moveCameraToFitAllMarkers();
      } else {
        setState(() {
          _polylines.clear();
          _routeDistance = '--';
          _routeDuration = '--';
          _remainingDistance = '--';
          _remainingDuration = '--';
          _legInfo = [];
          _remainingLegInfo = [];
        });
      }
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Periodically updates remaining distance/time from current location to next stops.
  ///
  /// Re-queries Directions API with current position as origin.
  /// Marks visited stops (within 50m) and plays sound.
  /// Updates remaining leg info card.
  Future<void> _updateRemainingDistanceAndTime() async {
    if (!_isNavigationStarted || _currentLatLng == null || _polylines.isEmpty) {
      setState(() {
        _remainingDistance = '--';
        _remainingDuration = '--';
        _remainingLegInfo = [];
      });
      return;
    }

    final String apiKey = await odooService.getMapToken();
    final List<LatLng> polylinePoints = _polylines.first.points;

    double minDistance = double.infinity;
    int closestIndex = 0;
    for (int i = 0; i < polylinePoints.length; i++) {
      double distance = mapService.distanceToSegment(
        _currentLatLng!,
        polylinePoints[i],
        polylinePoints[i],
      );
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    List<LatLng> remainingPoints = List.from(_stops);
    List<String> remainingNames = _stopSearchControllers
        .asMap()
        .entries
        .map((e) => e.value.text.isEmpty ? 'Stop ${e.key + 1}' : e.value.text)
        .toList();

    List<bool> visitedStops = List.filled(_stops.length, false);
    int nextPointIndex = -1;
    double minDistanceToPoint = double.infinity;
    LatLng? nextPoint;

    for (int i = 0; i < remainingPoints.length; i++) {
      double distance = mapService.distanceBetweenPoints(
        _currentLatLng!,
        remainingPoints[i],
      );
      if (distance <= 50) {
        visitedStops[i] = true;
        await mapService.playReachPointSound();
      } else if (distance < minDistanceToPoint) {
        minDistanceToPoint = distance;
        nextPointIndex = i;
        nextPoint = remainingPoints[i];
      }
    }

    if (nextPointIndex == -1) {
      nextPointIndex = remainingPoints.length - 1;
      nextPoint = remainingPoints.last;
    }

    List<Map<String, dynamic>> remainingLegInfo = [];
    double totalDistance = 0;
    int totalDuration = 0;

    String origin = '${_currentLatLng!.latitude},${_currentLatLng!.longitude}';
    List<LatLng> routePoints = remainingPoints;
    List<String> routeNames = remainingNames;

    if (routePoints.isEmpty) {
      setState(() {
        _remainingDistance = '0 km';
        _remainingDuration = '0 min';
        _remainingLegInfo = [];
      });
      return;
    }

    String waypoints = '';
    if (routePoints.length > 1) {
      List<String> stopCoords = routePoints
          .map((s) => '${s.latitude},${s.longitude}')
          .toList();
      waypoints = '&waypoints=optimize:true|${stopCoords.join('|')}';
    }

    String destination =
        '${routePoints.last.latitude},${routePoints.last.longitude}';
    final String url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination$waypoints&mode=$_selectedTravelMode&key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));
      final json = jsonDecode(response.body);

      if (json['status'] == 'OK') {
        final route = json['routes'][0];
        final legs = route['legs'];

        for (int i = 0; i < legs.length; i++) {
          final leg = legs[i];
          totalDistance += leg['distance']['value'] / 1000;
          totalDuration += (leg['duration']['value'] as num).toInt();

          String name =
          routeNames[i < routeNames.length ? i : routeNames.length - 1];
          LatLng latlng =
          routePoints[i < routePoints.length ? i : routePoints.length - 1];
          bool isVisited = i < visitedStops.length ? visitedStops[i] : false;

          remainingLegInfo.add({
            'name': name,
            'distance': leg['distance']['text'],
            'duration': leg['duration']['text'],
            'latlng': latlng,
            'type': isVisited ? 'visited_stop' : 'stop',
          });
        }

        if (nextPointIndex > 0) {
          remainingLegInfo.insert(0, {
            'name': 'Current Location',
            'distance': legs[0]['distance']['text'],
            'duration': legs[0]['duration']['text'],
            'latlng': _currentLatLng,
            'type': 'start',
          });
        }

        setState(() {
          _remainingDistance = '${totalDistance.toStringAsFixed(1)} km';
          _remainingDuration = mapService.formatDuration(totalDuration);
          _remainingLegInfo = remainingLegInfo;
        });
      } else {
        setState(() {
          _remainingDistance = '--';
          _remainingDuration = '--';
          _remainingLegInfo = [];
        });
      }
    } catch (e) {
      setState(() {
        _remainingDistance = '--';
        _remainingDuration = '--';
        _remainingLegInfo = [];
      });
    }
  }

  /// Animates camera to fit all markers (source + all stops) with padding.
  void _moveCameraToFitAllMarkers() {
    LatLngBounds bounds;
    if (_sourceLatLng != null && _stops.isNotEmpty) {
      List<LatLng> allPoints = [_sourceLatLng!, ..._stops];
      final southwest = LatLng(
        allPoints.map((p) => p.latitude).reduce(math.min),
        allPoints.map((p) => p.longitude).reduce(math.min),
      );
      final northeast = LatLng(
        allPoints.map((p) => p.latitude).reduce(math.max),
        allPoints.map((p) => p.longitude).reduce(math.max),
      );
      bounds = LatLngBounds(southwest: southwest, northeast: northeast);
      _googleMapController.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 60),
      );
    }
  }

  /// Requests location permission, gets current position, sets as source.
  Future<void> _setInitialLocation() async {
    Location location = Location();

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
    LatLng currentLatLng = LatLng(
      currentLocation.latitude!,
      currentLocation.longitude!,
    );

    setState(() {
      _initialCameraPosition = CameraPosition(
        target: LatLng(currentLocation.latitude!, currentLocation.longitude!),
        zoom: 15,
      );
      _currentLatLng = currentLatLng;
      _sourceLatLng = currentLatLng;
      sourceController.text = 'Your Location';
      if (_currentLatLng != null) {
        _sourceLatLng = _currentLatLng;
      }
    });

    _addCurrentLocationMarker(
      LatLng(currentLocation.latitude!, currentLocation.longitude!),
    );
  }

  /// Adds red marker for current location (initial position).
  Future<void> _addCurrentLocationMarker(LatLng position) async {
    setState(() {
      _markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: position,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
      );
    });
  }

  /// Shows modal bottom sheet to select pickings, set source, add manual stops.
  ///
  /// Multi-select dropdown for pickings (auto-fills stops from destination_point)
  /// Source field with suggestions ("Your Location" + places)
  /// Dynamic stop fields with place autocomplete
  /// Validates non-empty pickings before proceeding
  void _showEnterRootPopup({bool fromAddStop = false}) {
    final isDark = Theme
        .of(context)
        .brightness == Brightness.dark;
    bool _isDropdownActive = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        bool _isFetchingStops = false;

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter bottomSheetSetState) {
            if (fromAddStop && _stopSearchControllers.last.text
                .trim()
                .isNotEmpty) {
              _stopSearchControllers.add(TextEditingController());
              _stopSuggestions.add([]);
            }
            return AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeInOut,
              constraints: BoxConstraints(
                minHeight: _isDropdownActive
                  ? MediaQuery.of(context).size.height * 0.5
                    : MediaQuery.of(context).size.height * 0.25
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  top: 16,
                  left: 16,
                  right: 16,
                  bottom: MediaQuery
                      .of(context)
                      .viewInsets
                      .bottom + 16,
                ),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Enter Route',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 12),
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
                            decoration: InputDecoration(
                              labelText: "Search Pickings",
                              labelStyle: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          onDismissed: () {
                            bottomSheetSetState(() {
                              _isDropdownActive = false;
                            });
                          },
                        ),
                        onBeforePopupOpening: (List<Map<String, dynamic>> selectedItems) async {
                          bottomSheetSetState(() {
                            _isDropdownActive = true;
                          });
                          return true;
                        },
                        items: pickings,
                        itemAsString: (item) => item?['name'] ?? '',
                        selectedItems: pickings
                            .where((p) => selectedPickings.contains(p['id']))
                            .toList(),
                        onChanged: (List<Map<String, dynamic>> value) async {
                          bottomSheetSetState(() {
                            _isFetchingStops = true;
                          });
                          try {
                            selectedPickings =
                                value.map((e) => e['id'] as int).toList();
                            selectedPickingNames =
                                value.map((e) => e['name'] as String).toList();
                            _stops.clear();
                            for (var controller in _stopSearchControllers) {
                              controller.dispose();
                            }
                            _stopSearchControllers.clear();
                            _stopSuggestions.clear();
                            Set<String> uniqueDestinations = {};
                            for (var picking in value) {
                              String destinationPlace = picking['destination_point'] ??
                                  '';
                              if (destinationPlace.isNotEmpty &&
                                  !uniqueDestinations.contains(
                                      destinationPlace)) {
                                uniqueDestinations.add(destinationPlace);
                                _stopSearchControllers.add(
                                  TextEditingController(text: destinationPlace),
                                );
                                _stopSuggestions.add([]);
                                try {
                                  LatLng? stopLatLng = await mapService
                                      .getLatLngFromPlace(
                                    destinationPlace,
                                    await odooService.getMapToken(),
                                  );
                                  if (stopLatLng != null) {
                                    _stops.add(stopLatLng);
                                  }
                                } catch (e) {
                                  Navigator.of(context).pop(true);
                                  setState(() {
                                    selectedPickings.clear();
                                  });
                                  if (context.mounted) {
                                    CustomSnackbar.showError(context, "Could not fetch location. Please check your API key or server.");
                                  }
                                }
                              }
                            }
                            if (_stopSearchControllers.isEmpty ||
                                _stopSearchControllers.last.text
                                    .trim()
                                    .isNotEmpty) {
                              _stopSearchControllers.add(
                                  TextEditingController());
                              _stopSuggestions.add([]);
                            }
                          } catch (e) {
                            Navigator.of(context).pop(true);
                            if (context.mounted) {
                              CustomSnackbar.showError(context, "Something went wrong while choosing pickings.");
                            }
                          } finally {
                            setState(() {});
                            bottomSheetSetState(() {
                              shouldValidate = false;
                              _isFetchingStops = false;
                            });
                          }
                        },
                        dropdownDecoratorProps: DropDownDecoratorProps(
                          dropdownSearchDecoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            hintText: "Select Pickings",
                            hintStyle: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.white24
                                    : AppStyle.primaryColor.withOpacity(0.5),
                                width: 1.5,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: isDark ? Colors.white : AppStyle
                                    .primaryColor,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),

                      if (shouldValidate) ...[
                        const SizedBox(height: 10),
                        Text(
                          "Pickings cannot be empty",
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      TextField(
                        controller: sourceController,
                        style: TextStyle(
                          fontWeight: FontWeight.w400,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          hintText: 'Source Location',
                          hintStyle: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.white24
                                  : AppStyle.primaryColor.withOpacity(0.5),
                              width: 1.5,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: isDark ? Colors.white : AppStyle
                                  .primaryColor,
                              width: 2,
                            ),
                          ),
                        ),
                        onChanged: (value) async {
                          final suggestions = await mapService.fetchSuggestions(
                            value,
                            await odooService.getMapToken(),
                          );
                          bottomSheetSetState(() {
                            _sourceSuggestions =
                            ['Your Location', ...suggestions];
                          });
                        },
                      ),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _sourceSuggestions.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            title: Text(
                              _sourceSuggestions[index],
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            onTap: () async {
                              final selectedSuggestion = _sourceSuggestions[index];
                              sourceController.text = selectedSuggestion;
                              bottomSheetSetState(() {
                                _sourceSuggestions.clear();
                              });
                              if (selectedSuggestion == 'Your Location') {
                                if (_currentLatLng != null) {
                                  setState(() {
                                    _sourceLatLng = _currentLatLng;
                                  });
                                }
                              } else {
                                _sourceLatLng =
                                await mapService.getLatLngFromPlace(
                                  sourceController.text,
                                  await odooService.getMapToken(),
                                );
                              }
                              setState(() {});
                            },
                          );
                        },
                      ),
                      if (_isFetchingStops)
                        Container(
                          color: Colors.transparent,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      if (selectedPickings.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        ...List.generate(
                            _stopSearchControllers.length, (index) {
                          return Column(
                            children: [
                              TextField(
                                controller: _stopSearchControllers[index],
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  hintText: _stopSearchControllers[index].text
                                      .trim()
                                      .isEmpty
                                      ? 'Add your stop'
                                      : 'Stop ${index + 1}',
                                  hintStyle: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: isDark
                                          ? Colors.white24
                                          : AppStyle.primaryColor.withOpacity(
                                          0.5),
                                      width: 1.5,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: isDark ? Colors.white : AppStyle
                                          .primaryColor,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                onChanged: (value) async {
                                  final suggestions = await mapService
                                      .fetchSuggestions(
                                    value,
                                    await odooService.getMapToken(),
                                  );
                                  bottomSheetSetState(() {
                                    if (_stopSuggestions.length <= index) {
                                      _stopSuggestions.add(suggestions);
                                    } else {
                                      _stopSuggestions[index] = suggestions;
                                    }
                                  });
                                },
                              ),
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _stopSuggestions[index].length,
                                itemBuilder: (context, suggestionIndex) {
                                  return ListTile(
                                    title: Text(
                                      _stopSuggestions[index][suggestionIndex],
                                      style: TextStyle(
                                        color: isDark ? Colors.white : Colors
                                            .black,
                                      ),
                                    ),
                                    onTap: () async {
                                      _stopSearchControllers[index].text =
                                      _stopSuggestions[index][suggestionIndex];
                                      bottomSheetSetState(() {
                                        _stopSuggestions[index].clear();
                                      });
                                      LatLng? stopLatLng = await mapService
                                          .getLatLngFromPlace(
                                        _stopSearchControllers[index].text,
                                        await odooService.getMapToken(),
                                      );
                                      if (stopLatLng != null) {
                                        setState(() {
                                          if (_stops.length > index) {
                                            _stops[index] = stopLatLng;
                                          } else {
                                            _stops.add(stopLatLng);
                                          }
                                        });
                                      }
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                            ],
                          );
                        }),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? Colors.white : AppStyle
                                .primaryColor,
                            foregroundColor: isDark ? Colors.black : Colors
                                .white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            if (selectedPickings.isEmpty) {
                              setState(() {
                                shouldValidate = true;
                              });
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
                              sourceSearchController.text =
                                  sourceController.text;
                              for (int i = 0; i <
                                  _stopSearchControllers.length; i++) {
                                if (i < _stops.length &&
                                    _stopSearchControllers[i].text.isNotEmpty) {
                                  _stopSearchControllers[i].text =
                                      _stopSearchControllers[i].text;
                                }
                              }
                            });
                            await _getOptimizedRoute();
                            setState(() {});
                          },
                          icon: const Icon(HugeIcons.strokeRoundedNavigation03),
                          label: Text(
                            'Show Directions',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.black : Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
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
    final isDark = Theme
        .of(context)
        .brightness == Brightness.dark;

    return Scaffold(
      body: _initialCameraPosition == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        children: [
          GoogleMap(
            mapType: _currentMapType,
            initialCameraPosition: _initialCameraPosition!,
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            onMapCreated: (controller) =>
            _googleMapController = controller,
            markers: _markers,
            polylines: _polylines,
            onCameraMoveStarted: () {
              setState(() {
                _isMapManuallyMoved = true;
              });
            },
          ),
          if (!isOnline) ...[
            Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(HugeIcons.strokeRoundedWifiDisconnected03,
                        color: Colors.white, size: 80),
                    SizedBox(height: 16),
                    Text(
                      'Internet is not accessible',
                      style: TextStyle(
                        fontSize: 20,
                        color: isDark ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (!_infoCard) ...[
            if (_showLocationNames) ...[
              Positioned(
                top: 40,
                left: 16,
                right: 16,
                child: SearchInputs(
                  sourceController: sourceSearchController,
                  stopControllers: _stopSearchControllers,
                  showStopFields: _showStopLocationFields,
                ),
              ),
              Positioned(
                top: 40,
                right: 16,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? Colors.white : AppStyle.primaryColor,
                      width: 2,
                    ),
                  ),
                  child: CircleAvatar(
                    backgroundColor: isDark
                        ? Color(0xff3c3c3c)
                        : Colors.white,
                    child: IconButton(
                      icon: Icon(
                        Icons.close,
                        color: isDark ? Colors.white : AppStyle.primaryColor,
                      ),
                      onPressed: () {
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
                          _legInfo = [];
                          _remainingLegInfo = [];
                          for (final c in _stopSearchControllers) {
                            c.dispose();
                          }
                          _stopSearchControllers
                            ..clear()
                            ..add(TextEditingController());
                          sourceSearchController.text =
                              sourceController.text;
                          sourceController.text = 'Your Location';
                          for (var controller in _stopSearchControllers) {
                            controller.text = '';
                          }
                          selectedPickings.clear();
                          selectedPickingNames.clear();
                          _showStopLocationFields = false;
                          _locationSubscription?.cancel();
                          _distanceUpdateTimer?.cancel();
                          _stops.clear();
                          if (_currentLatLng != null) {
                            _addCurrentLocationMarker(_currentLatLng!);
                            _googleMapController.animateCamera(
                              CameraUpdate.newCameraPosition(
                                CameraPosition(
                                  target: _currentLatLng!,
                                  zoom: 15,
                                ),
                              ),
                            );
                          }
                        });
                      },
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
                      ? () async {
                    setState(() {
                      _isLoading = true;
                    });
                    setState(() {
                      _isNavigationStarted = true;
                      _isMapManuallyMoved = false;
                      _markers.removeWhere(
                            (m) => m.markerId.value == 'moving_marker',
                      );
                      for (int i = 0; i < _stops.length; i++) {
                        _markers.add(
                          Marker(
                            markerId: MarkerId('stop$i'),
                            position: _stops[i],
                            infoWindow: InfoWindow(
                              title:
                              _stopSearchControllers[i]
                                  .text
                                  .isEmpty
                                  ? 'Stop ${i + 1}'
                                  : _stopSearchControllers[i].text,
                            ),
                            icon:
                            BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueOrange,
                            ),
                          ),
                        );
                      }
                    });

                    bool serviceEnabled = await _location
                        .serviceEnabled();
                    if (!serviceEnabled) {
                      serviceEnabled = await _location
                          .requestService();
                      if (!serviceEnabled) {
                        setState(() {
                          _isLoading = false;
                        });
                        return;
                      }
                    }

                    PermissionStatus permissionGranted =
                    await _location.hasPermission();
                    if (permissionGranted ==
                        PermissionStatus.denied) {
                      permissionGranted = await _location
                          .requestPermission();
                      if (permissionGranted !=
                          PermissionStatus.granted) {
                        setState(() {
                          _isLoading = false;
                        });
                        return;
                      }
                    }

                    _locationSubscription?.cancel();
                    LatLng? lastPosition;
                    List<LatLng> currentPolylinePoints =
                    _polylines.isNotEmpty
                        ? _polylines.first.points
                        : [];

                    _locationSubscription = _location
                        .onLocationChanged
                        .listen((locationData) async {
                      if (locationData.latitude == null ||
                          locationData.longitude == null) {
                        setState(() {
                          _isLoading = false;
                        });
                        return;
                      }
                      final currentLatLng = LatLng(
                        locationData.latitude!,
                        locationData.longitude!,
                      );
                      double bearing = _lastBearing;

                      if (lastPosition != null &&
                          _isPhoneRotated) {
                        bearing = mapService.calculateBearing(
                          lastPosition!,
                          currentLatLng,
                        );
                      }

                      const double offRouteThreshold = 50.0;
                      bool isOffRoute = false;
                      if (currentPolylinePoints.isNotEmpty) {
                        double distance = mapService
                            .distanceToPolyline(
                          currentLatLng,
                          currentPolylinePoints,
                        );
                        if (distance > offRouteThreshold) {
                          isOffRoute = true;
                        }
                      }

                      if (isOffRoute) {
                        setState(() {
                          _sourceLatLng = currentLatLng;
                          sourceController.text =
                          'Your Location';
                        });
                        currentPolylinePoints =
                        _polylines.isNotEmpty
                            ? _polylines.first.points
                            : [];

                        if (_polylines.isEmpty) {
                          await mapService.playWrongPathSound();
                        }
                      }

                      setState(() {
                        _markers.removeWhere(
                              (m) =>
                          m.markerId.value ==
                              'moving_marker',
                        );
                        _markers.add(
                          Marker(
                            markerId: const MarkerId(
                              'moving_marker',
                            ),
                            position: currentLatLng,
                            rotation: bearing,
                            anchor: const Offset(0.5, 0.5),
                            flat: true,
                            icon: _navigationIcon!,
                          ),
                        );
                        _currentLatLng = currentLatLng;
                      });

                      if (!_isMapManuallyMoved) {
                        _googleMapController.animateCamera(
                          CameraUpdate.newCameraPosition(
                            CameraPosition(
                              target: currentLatLng,
                              zoom: 17.0,
                              bearing: bearing,
                              tilt: 45,
                            ),
                          ),
                        );
                      }

                      lastPosition = currentLatLng;
                      _lastBearing = bearing;
                    });

                    _distanceUpdateTimer?.cancel();
                    _distanceUpdateTimer = Timer.periodic(
                      Duration(seconds: 30),
                          (timer) {
                        _updateRemainingDistanceAndTime();
                      },
                    );
                    await _updateRemainingDistanceAndTime();

                    setState(() {
                      _showLocationNames = false;
                      _isLoading = false;
                    });
                  }
                      : null,
                  onAddStopPressed: () async {
                    setState(() {
                      _showStopLocationFields = true;
                    });
                    _showEnterRootPopup(fromAddStop: true);
                  },
                  onTravelModeChanged: (mode) {
                    setState(() {
                      _selectedTravelMode = mode;
                    });
                    _getOptimizedRoute();
                  },
                ),
              ),
            ],
          ],
          if (_isNavigationStarted) ...[
            Positioned(
              top: 40,
              left: 16,
              right: 16,
              child: NavigationHeader(
                selectedTravelMode: _selectedTravelMode,
                onClose: () {
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
                    if (_currentLatLng != null) {
                      _addCurrentLocationMarker(_currentLatLng!);
                      _googleMapController.animateCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(
                            target: _currentLatLng!,
                            zoom: 15,
                          ),
                        ),
                      );
                    }
                    _stops.clear();
                    selectedPickings.clear();
                    selectedPickingNames.clear();
                  });
                },
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
                    _googleMapController.animateCamera(
                      CameraUpdate.newCameraPosition(
                        CameraPosition(target: latLng, zoom: 15),
                      ),
                    );
                    setState(() {
                      _isMapManuallyMoved = true;
                    });
                  }
                },
                onAddRoutePressed: () async {
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
              color: Colors.black.withOpacity(0.5),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_showOtherFABs) ...[
            FloatingActionButton(
              backgroundColor: isDark ? Colors.black : AppStyle.primaryColor,
              onPressed: () {
                _showEnterRootPopup();
              },
              child: const Icon(
                  HugeIcons.strokeRoundedRoute03, color: Colors.white),
            ),
            const SizedBox(height: 10),
            FloatingActionButton(
              backgroundColor: isDark ? Colors.black : AppStyle.primaryColor,
              onPressed: () {
                _googleMapController.animateCamera(
                  CameraUpdate.newCameraPosition(_initialCameraPosition!),
                );
              },
              child: const Icon(
                HugeIcons.strokeRoundedCenterFocus,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (_showLayer) ...[
            Builder(
              builder: (context) =>
                  FloatingActionButton(
                    backgroundColor: isDark ? Colors.black : AppStyle
                        .primaryColor,
                    onPressed: () {
                      setState(() {
                        _showOtherFABs = !_showOtherFABs;
                      });
                      _showMapTypeOptions(context);
                    },
                    heroTag: 'mapTypeToggle',
                    child: const Icon(
                      HugeIcons.strokeRoundedGlobal,
                      color: Colors.white,
                    ),
                    tooltip: 'Change Map View',
                  ),
            ),
          ],
          if (_isNavigationStarted) ...[
            const SizedBox(height: 10),
            FloatingActionButton(
              backgroundColor: isDark ? Colors.black : AppStyle.primaryColor,
              onPressed: () {
                setState(() {
                  _showRemainingInfo = !_showRemainingInfo;
                });
              },
              child: Icon(
                _showRemainingInfo ? Icons.visibility_off : Icons.visibility,
                color: Colors.white,
              ),
              tooltip: _showRemainingInfo
                  ? 'Hide Remaining Route'
                  : 'Show Remaining Route',
            ),
          ],
        ],
      ),
    );
  }

  /// Builds small FAB for each map type option (normal, satellite, terrain, hybrid).
  Widget _buildMapTypeIcon(MapType type, IconData icon, String tooltip) {
    final isDark = Theme
        .of(context)
        .brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: FloatingActionButton.small(
        heroTag: tooltip,
        tooltip: tooltip,
        backgroundColor: isDark
            ? Colors.black87
            : AppStyle.primaryColor.withOpacity(0.8),
        onPressed: () {
          setState(() {
            _currentMapType = type;
          });
          _mapTypeOverlayEntry?.remove();
          _mapTypeOverlayEntry = null;
          setState(() {
            _showOtherFABs = true;
          });
        },
        child: Icon(icon, color: Colors.white),
      ),
    );
  }

  /// Shows overlay with map type selection buttons (appears above FAB).
  void _showMapTypeOptions(BuildContext context) {
    _mapTypeOverlayEntry?.remove();

    _mapTypeOverlayEntry = OverlayEntry(
      builder: (_) =>
          GestureDetector(
            onTap: () {
              _mapTypeOverlayEntry?.remove();
              _mapTypeOverlayEntry = null;
              setState(() => _showOtherFABs = true);
            },
            child: Container(
              color: Colors.black.withOpacity(0.2),
              child: Stack(
                children: [
                  Positioned(
                    bottom: 90,
                    right: 20,
                    child: Material(
                      color: Colors.transparent,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _buildMapTypeIcon(
                            MapType.normal,
                            HugeIcons.strokeRoundedMaps,
                            'Normal',
                          ),
                          _buildMapTypeIcon(
                            MapType.satellite,
                            HugeIcons.strokeRoundedSatellite02,
                            'Satellite',
                          ),
                          _buildMapTypeIcon(
                            MapType.terrain,
                            HugeIcons.strokeRoundedMountain,
                            'Terrain',
                          ),
                          _buildMapTypeIcon(
                            MapType.hybrid,
                            HugeIcons.strokeRoundedMaps,
                            'Hybrid',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );

    Overlay.of(context).insert(_mapTypeOverlayEntry!);
  }
}
