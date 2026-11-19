import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:location/location.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:http/http.dart' as http;
import '../../../shared/utils/globals.dart';
import '../../../core/colors/app_colors.dart';
import '../../../shared/widgets/snackbar.dart';
import '../services/external_maps_service.dart';
import '../services/map_service.dart';
import '../services/odoo_map_service.dart';
import '../services/route_navigation_bus.dart';
import '../services/route_plan_bus.dart';
import '../../../shared/widgets/loaders/loading_widget.dart';
import '../../../shared/widgets/loading_overlay.dart';
import '../../../shared/widgets/error_state_widget.dart';
import 'package:dropdown_search/dropdown_search.dart';
import '../../../shared/widgets/inputs/mobo_text_field.dart';
import '../../../shared/widgets/dialogs/common_dialog.dart';
import '../widgets/maps_app_picker_sheet.dart';
import '../widgets/navigation_header.dart';
import '../widgets/remaining_info_card.dart';
import '../widgets/route_info_card.dart';
import '../widgets/search_inputs.dart';

/// Zoom bounds for the route map. Below [_kMinMapZoom] the tile server stops
/// serving imagery, which is what left large blank areas when zooming out.
const double _kMinMapZoom = 3;
const double _kMaxMapZoom = 18;

/// Ignore GPS jitter below roughly a metre so the pin doesn't rebuild the
/// map on every tick while the device is stationary.
const double _kMinPinMoveDegrees = 0.00001;

/// How long to wait for a position fix before showing the map without one.
/// `getLocation` never completes on a device that cannot produce a fix (a
/// simulator with no simulated location, or GPS indoors), and the page used
/// to sit on its loading overlay for as long as it waited.
const Duration _kLocationTimeout = Duration(seconds: 12);

/// Default TomTom key, byte-XOR'd against [_kKeyPad] so it isn't a
/// plaintext, grep/scan-able string in source control. This is
/// obfuscation, not real secrecy — anyone decompiling the shipped binary
/// can still recover it — but it keeps the key out of the repo/diff text.
/// [TOMTOM_API_KEY] in `.env` still overrides this when set.
const int _kKeyPad = 0x5A;
const List<int> _kDefaultTomTomKeyXor = [
  11,
  12,
  25,
  31,
  99,
  108,
  16,
  99,
  19,
  105,
  50,
  98,
  9,
  40,
  8,
  55,
  43,
  42,
  30,
  111,
  28,
  31,
  25,
  17,
  54,
  40,
  18,
  44,
  53,
  29,
  55,
  109,
];
String _defaultTomTomKey() =>
    String.fromCharCodes(_kDefaultTomTomKeyXor.map((b) => b ^ _kKeyPad));

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
  bool _locationNoticePending = false;

  /// Set while the map is showing [_fallbackCenter] because no position
  /// could be had, so the page can say so and offer a retry instead of
  /// silently showing somewhere that is not the user.
  bool _locationUnavailable = false;
  bool _isLocating = false;

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

  /// The single current/source location pin, kept out of [_markers].
  Marker? _currentLocationMarker;

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
  String? _routeError;
  String _selectedTravelMode = 'driving';
  StreamSubscription<LocationData>? _locationSubscription;
  final Location _location = Location();
  double _lastBearing = 0.0;
  Widget? _navigationIcon;
  StreamSubscription? _gyroscopeSubscription;
  StreamSubscription<void>? _planSub;
  bool _isPhoneRotated = false;
  LatLng? _currentLatLng;
  bool _showLayer = true;
  List<Map<String, dynamic>> pickings = [];
  bool _pickingsLoading = true;
  bool _pickingsLoadFailed = false;

  /// Lets [_fetchPickings] push a rebuild into the "Enter Route" sheet if
  /// it's open when the fetch finishes — the sheet is a separate route, so
  /// the outer `setState` this widget normally uses does not reach it.
  void Function(VoidCallback)? _activeSheetSetState;
  List<int> selectedPickings = [];
  List<String> selectedPickingNames = [];

  /// Inline warning for the route sheet's picking picker. Kept on the State
  /// rather than in the sheet builder so it reads the same whichever way the
  /// dropdown was closed, and survives the sheet rebuilding.
  String? _pickingsNotice;

  /// Set once the driver has closed the pickings notice. A notice they have
  /// already read should not greet them again every time the sheet opens;
  /// a *different* notice is new information and clears this.
  bool _pickingsNoticeDismissed = false;

  /// Which pickings each stop field came from, parallel to
  /// [_stopSearchControllers]. Empty for a stop the user added by hand. Two
  /// pickings for the same address share one stop, so this is a set.
  ///
  /// Kept beside the controllers so selecting or deselecting a picking adds
  /// or removes only that picking's stop and leaves hand-added stops alone.
  final List<Set<int>> _stopPickingIds = [<int>{}];

  /// The pickings the stop fields currently reflect. Selection changes are
  /// applied as a difference against this, which makes applying the same
  /// selection twice — "Done" and the dismiss it triggers — a no-op.
  Set<int> _syncedPickingIds = <int>{};

  /// The selection sync in flight, so "Show Directions" tapped mid-lookup
  /// waits for it, and two syncs never interleave.
  Future<void>? _stopsRebuild;

  /// Bumped whenever the route is cleared, so a lookup that was in flight
  /// at that moment drops its result instead of writing into the new state.
  int _stopsGeneration = 0;

  /// Places already located, keyed by normalised text. Routing re-reads every
  /// stop's text, so an edited stop is always located again while unchanged
  /// stops cost no extra request.
  final Map<String, LatLng> _geocodeCache = {};

  /// Places looked up and not found (or not reachable). Retried on the next
  /// lookup, never cached as a failure.
  final Set<String> _geocodeMisses = {};

  /// Inline error under a stop field, keyed by its controller so it stays
  /// with the field when stops are reordered or removed. Shown in the sheet
  /// rather than as a snackbar, which would sit behind the sheet.
  final Map<TextEditingController, String> _stopFieldErrors = {};

  final ExternalMapsService _externalMaps = const ExternalMapsService();
  bool _openingExternalMaps = false;

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

  /// Mapbox public access token — loaded from .env at start, may be overridden by Odoo.
  // ignore: prefer_final_fields
  String _apiKey = '';

  @override
  void initState() {
    super.initState();
    _apiKey = dotenv.env['TOMTOM_API_KEY'] ?? _defaultTomTomKey();
    _initializeServices();
    _setInitialLocation();
    _loadCustomMarker();
    _listenToGyroscope();

    _planSub = RoutePlanBus.stream.listen((_) {
      if (!mounted) return;
      _showEnterRootPopup();
    });
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
      if (mounted) {
        setState(() {
          isOnline = false;
          _pickingsLoading = false;
        });
      } else {
        _pickingsLoading = false;
      }
      return;
    }
    if (mounted) setState(() => isOnline = true);

    await _fetchPickings();
  }

  /// Fetches the pickings list for the "Enter Route" sheet's picker.
  ///
  /// Reports its loading/failure state so the sheet can show a proper
  /// loading/retry UI instead of a bare, indistinguishable "No data found"
  /// — and pushes a rebuild into the sheet via [_activeSheetSetState] if
  /// it's already open when this finishes, since it lives in a separate
  /// route that the outer `setState` below does not reach.
  Future<void> _fetchPickings() async {
    void update(VoidCallback fn) {
      if (mounted) setState(fn);
      try {
        _activeSheetSetState?.call(fn);
      } catch (_) {}
    }

    update(() {
      _pickingsLoading = true;
      _pickingsLoadFailed = false;
    });

    try {
      await odooService.initializeOdooClient();
      final fetched = await odooService.fetchStockPickings().timeout(
        const Duration(seconds: 20),
      );
      update(() {
        pickings = fetched;
        _pickingsLoading = false;
      });
    } catch (e) {
      update(() {
        _pickingsLoading = false;
        _pickingsLoadFailed = true;
      });
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
    _gyroscopeSubscription = gyroscopeEventStream().listen((
      GyroscopeEvent event,
    ) {
      _isPhoneRotated = event.z.abs() > 0.5;
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _planSub?.cancel();
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
      child: const Icon(
        HugeIcons.strokeRoundedNavigation03,
        color: Colors.white,
        size: 20,
      ),
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
    final n = _stops.length;
    if (_sourceLatLng == null || n < 2) return;

    // Only the first [n] fields are on the route (see _resolveStopFields);
    // anything after them is unresolved or blank and keeps its place.
    final intermediate = List<int>.generate(n - 1, (i) => i);
    final sortedIndices = <int>[];
    LatLng current = _sourceLatLng!;

    while (intermediate.isNotEmpty) {
      int bestIdx = intermediate.first;
      double bestDist = mapService.distanceBetweenPoints(
        current,
        _stops[bestIdx],
      );
      for (final i in intermediate) {
        final d = mapService.distanceBetweenPoints(current, _stops[i]);
        if (d < bestDist) {
          bestDist = d;
          bestIdx = i;
        }
      }
      sortedIndices.add(bestIdx);
      intermediate.remove(bestIdx);
      current = _stops[bestIdx];
    }
    sortedIndices.add(n - 1);

    final stops = sortedIndices.map((i) => _stops[i]).toList();
    final ctrls = sortedIndices.map((i) => _stopSearchControllers[i]).toList();
    final ids = sortedIndices.map((i) => _stopPickingIds[i]).toList();

    _stops
      ..clear()
      ..addAll(stops);
    _stopSearchControllers.replaceRange(0, n, ctrls);
    _stopPickingIds.replaceRange(0, n, ids);
    for (final s in _stopSuggestions) {
      s.clear();
    }
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

    void surfaceError(String friendly, {String? toastOverride}) {
      if (!mounted) return;
      CustomSnackbar.showError(context, toastOverride ?? friendly);
      setState(() {
        _polylines.clear();
        _routeDistance = '--';
        _routeDuration = '--';
        _legInfo = [];
        _routeError = friendly;
      });
    }

    try {
      // A picking's stop is added when the picker closes; tapping straight
      // through to here must not read the list before that lands. A failed
      // sync has already been reported in the sheet, so it isn't fatal here.
      try {
        await _stopsRebuild;
      } catch (_) {}
      if (!mounted) return;

      if (_apiKey.isEmpty) {
        surfaceError(
          'Map service isn\'t configured. Please contact your administrator '
          'or set the TomTom API key in Profile settings.',
          toastOverride:
              'TomTom API key is missing. Check .env or Profile settings.',
        );
        return;
      }

      if (_sourceLatLng == null) {
        if (_currentLatLng != null) {
          _sourceLatLng = _currentLatLng;
          sourceController.text = 'Your Location';
        } else if (sourceController.text.trim().isNotEmpty &&
            sourceController.text != 'Your Location') {
          _sourceLatLng = await mapService.getLatLngFromPlace(
            sourceController.text,
            _apiKey,
            proximity: _currentLatLng,
          );
        }
      }

      if (_sourceLatLng == null) {
        final usingGps = sourceController.text == 'Your Location';
        surfaceError(
          usingGps
              ? 'We couldn\'t get your current location. Please enable GPS '
                    'and grant location permission, or type a source address.'
              : 'We couldn\'t resolve the source address. Try selecting a '
                    'suggestion or use "Your location" instead.',
          toastOverride:
              'Source location not set. Enable GPS or enter manually.',
        );
        return;
      }

      // Every stop is located from its current text, so an edited stop is
      // routed to where it now says, not where it used to point.
      final generation = _stopsGeneration;
      final unresolvedStops = await _resolveStopFields();
      // The route was closed while the stops were being located.
      if (!mounted || generation != _stopsGeneration) return;
      setState(() {});

      if (_stops.isEmpty) {
        // Three different situations used to share one "could not resolve"
        // message, which pointed at geocoding even when nothing was ever
        // sent to it — no stop at all, or a picking with no address in Odoo.
        final anyStopTyped = _stopSearchControllers.any(
          (c) => c.text.trim().isNotEmpty,
        );
        if (!anyStopTyped && _pickingsNotice != null) {
          surfaceError(_pickingsNotice!);
        } else if (!anyStopTyped) {
          surfaceError(
            'Add a stop, or select a picking whose customer has an address '
            'in Odoo.',
            toastOverride: 'No stops to route to yet.',
          );
        } else {
          surfaceError(
            'None of the stops could be located on the map. Edit them and '
            'pick a suggestion, or check your connection.',
            toastOverride: 'Could not locate any of the stops.',
          );
        }
        return;
      }

      if (unresolvedStops.isNotEmpty) {
        CustomSnackbar.showWarning(
          context,
          'Left out of the route because it could not be located: '
          '${unresolvedStops.join(', ')}. Edit the stop to fix it.',
        );
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

      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) {
        surfaceError(
          travelMode == 'bicycle'
              ? 'Bike routing is unavailable for this trip. '
                    'Try a shorter distance or switch to Drive mode.'
              : 'We couldn\'t compute a route between these '
                    'locations. Please check your stops and try again.',
        );
        return;
      }

      final json = jsonDecode(response.body);

      if (json['routes'] != null && (json['routes'] as List).isNotEmpty) {
        final route = json['routes'][0];
        final legs = route['legs'] as List;
        final polylinePoints = mapService.parseRoutePoints(legs);

        if (polylinePoints.isEmpty) {
          if (mounted) {
            CustomSnackbar.showError(
              context,
              'Route geometry could not be parsed.',
            );
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
          'end_address':
              _stopSearchControllers.isNotEmpty &&
                  _stopSearchControllers[0].text.isNotEmpty
              ? _stopSearchControllers[0].text
              : 'Stop 1',
          'distance': mapService.formatDistance(
            (leg0Summary['lengthInMeters'] as num).toDouble(),
          ),
          'duration': mapService.formatDuration(
            (leg0Summary['travelTimeInSeconds'] as num).toInt(),
          ),
        });
        totalDistance +=
            (leg0Summary['lengthInMeters'] as num).toDouble() / 1000;
        totalDuration += (leg0Summary['travelTimeInSeconds'] as num).toInt();

        for (int i = 1; i < legs.length; i++) {
          final legSummary = legs[i]['summary'];
          totalDistance +=
              (legSummary['lengthInMeters'] as num).toDouble() / 1000;
          totalDuration += (legSummary['travelTimeInSeconds'] as num).toInt();
          legInfo.add({
            'start_address':
                i - 1 < _stopSearchControllers.length &&
                    _stopSearchControllers[i - 1].text.isNotEmpty
                ? _stopSearchControllers[i - 1].text
                : 'Stop $i',
            'end_address':
                i < _stopSearchControllers.length &&
                    _stopSearchControllers[i].text.isNotEmpty
                ? _stopSearchControllers[i].text
                : 'Stop ${i + 1}',
            'distance': mapService.formatDistance(
              (legSummary['lengthInMeters'] as num).toDouble(),
            ),
            'duration': mapService.formatDuration(
              (legSummary['travelTimeInSeconds'] as num).toInt(),
            ),
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
          _routeError = null;
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
        surfaceError(
          'These stops aren\'t connected by any drivable road. Try '
          'different stops or another travel mode.',
        );
      }
    } catch (_) {
      surfaceError(
        'Something went wrong while computing the route. Please check your '
        'connection and try again.',
        toastOverride:
            'Couldn\'t get the route. Check your connection and '
            'try again.',
      );
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
              BoxShadow(
                color: Colors.black38,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Container(
          width: 3,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(2),
            ),
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
      return;
    }

    final List<LatLng> polylinePoints = _polylines.first.points;
    for (int i = 0; i < polylinePoints.length; i++) {
      mapService.distanceToSegment(
        _currentLatLng!,
        polylinePoints[i],
        polylinePoints[i],
      );
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
      final distance = mapService.distanceBetweenPoints(
        _currentLatLng!,
        remainingPoints[i],
      );
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
          totalDistance +=
              (legSummary['lengthInMeters'] as num).toDouble() / 1000;
          totalDuration += (legSummary['travelTimeInSeconds'] as num).toInt();

          final name =
              remainingNames[i < remainingNames.length
                  ? i
                  : remainingNames.length - 1];
          final latlng =
              remainingPoints[i < remainingPoints.length
                  ? i
                  : remainingPoints.length - 1];
          final isVisited = i < visitedStops.length ? visitedStops[i] : false;

          remainingLegInfo.add({
            'name': name,
            'distance': mapService.formatDistance(
              (legSummary['lengthInMeters'] as num).toDouble(),
            ),
            'duration': mapService.formatDuration(
              (legSummary['travelTimeInSeconds'] as num).toInt(),
            ),
            'latlng': latlng,
            'type': isVisited ? 'visited_stop' : 'stop',
          });
        }

        if (nextPointIndex > 0 && legs.isNotEmpty) {
          final firstLegSummary = legs[0]['summary'];
          remainingLegInfo.insert(0, {
            'name': 'Current Location',
            'distance': mapService.formatDistance(
              (firstLegSummary['lengthInMeters'] as num).toDouble(),
            ),
            'duration': mapService.formatDuration(
              (firstLegSummary['travelTimeInSeconds'] as num).toInt(),
            ),
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
      }
    } catch (_) {
      // Distance/time refresh is cosmetic; a failure must not interrupt
      // navigation already in progress.
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
  ///
  /// The service check and the fix itself are bounded by [_kLocationTimeout];
  /// the permission request is not, since that waits on the user answering
  /// the system prompt. Also serves as the retry from the location card, in
  /// which case the map is already up and is moved to the new position.
  Future<void> _setInitialLocation() async {
    if (_isLocating) return;
    if (mounted) setState(() => _isLocating = true);
    try {
      final location = Location();

      bool serviceEnabled = await location.serviceEnabled().timeout(
        _kLocationTimeout,
      );
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

      final currentLocation = await location.getLocation().timeout(
        _kLocationTimeout,
      );
      final currentLatLng = LatLng(
        currentLocation.latitude!,
        currentLocation.longitude!,
      );

      if (!mounted) return;
      final mapAlreadyShown = _initialCameraPosition != null;
      setState(() {
        _initialCameraPosition = currentLatLng;
        _isLoading = false;
        _locationUnavailable = false;
        _currentLatLng = currentLatLng;
        _sourceLatLng ??= currentLatLng;
        if (sourceController.text.isEmpty) {
          sourceController.text = 'Your Location';
        }
      });
      _setCurrentLocationMarker(currentLatLng);
      if (mapAlreadyShown && !_isNavigationStarted) {
        _mapController.move(currentLatLng, 15.0);
      }
    } catch (_) {
      _useFallbackLocation();
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      } else {
        _isLocating = false;
      }
    }
  }

  /// Renders the map at a default center when the current location can't be
  /// obtained, so the page never gets stuck on the loading overlay. Tells the
  /// user (once) to set their source manually.
  void _useFallbackLocation() {
    if (!mounted) return;
    if (_initialCameraPosition != null) {
      if (_currentLatLng == null) setState(() => _locationUnavailable = true);
      return;
    }
    setState(() {
      _initialCameraPosition = _fallbackCenter;
      _isLoading = false;
      _locationUnavailable = true;
    });
    // The notice is held, not shown. Every tab lives in an IndexedStack, so
    // this page builds and asks for a location while Home is on screen — and
    // on iOS that first attempt fails before the permission prompt resolves,
    // which put the warning in front of a user who was not looking at the
    // map. It is raised instead when they actually open Enter Route, which
    // is the only place its advice can be acted on.
    _locationNoticePending = true;
  }

  /// Shows the held location notice, once, now that the route UI is in front
  /// of the user.
  void _showPendingLocationNotice() {
    if (!mounted || !_locationNoticePending || _locationNoticeShown) return;
    if (_sourceLatLng != null) {
      _locationNoticePending = false;
      return;
    }
    _locationNoticeShown = true;
    _locationNoticePending = false;
    CustomSnackbar.showWarning(
      context,
      'Location unavailable. Set your source manually in "Enter Route".',
    );
  }

  /// Places the pin representing the current/source location.
  ///
  /// Held in its own field rather than appended to [_markers]: GPS readings
  /// drift by a few metres each tick, so de-duplicating by coordinate never
  /// matched and every update used to leave another pin behind.
  void _setCurrentLocationMarker(LatLng position) {
    if (!mounted) return;
    final previous = _currentLocationMarker?.point;
    if (previous != null &&
        (previous.latitude - position.latitude).abs() < _kMinPinMoveDegrees &&
        (previous.longitude - position.longitude).abs() < _kMinPinMoveDegrees) {
      return;
    }
    setState(() {
      _currentLocationMarker = Marker(
        point: position,
        width: 40,
        height: 50,
        alignment: Alignment.bottomCenter,
        child: _buildLocationPin(),
      );
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
              BoxShadow(
                color: Colors.black38,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            HugeIcons.strokeRoundedUserCircle,
            color: Colors.white,
            size: 18,
          ),
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

  // ---------------------------------------------------------------------------
  // Stop fields
  //
  // Three lists describe the stop fields and must always be the same length:
  // [_stopSearchControllers] (the text), [_stopSuggestions] (the open
  // autocomplete list) and [_stopPickingIds] (which pickings the stop came
  // from). Every change goes through the helpers below so they never drift —
  // drift is what let editing one stop move another.
  // ---------------------------------------------------------------------------

  void _addStopField({String text = '', Set<int>? pickingIds, int? at}) {
    final index = at ?? _stopSearchControllers.length;
    _stopSearchControllers.insert(index, TextEditingController(text: text));
    _stopSuggestions.insert(index, <String>[]);
    _stopPickingIds.insert(index, pickingIds ?? <int>{});
  }

  void _removeStopFieldAt(int index) {
    final ctrl = _stopSearchControllers.removeAt(index);
    _stopSuggestions.removeAt(index);
    _stopPickingIds.removeAt(index);
    _stopFieldErrors.remove(ctrl);
    // The field may still be on screen for the rest of this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
  }

  void _moveStopField(int from, int to) {
    if (from == to) return;
    final ctrl = _stopSearchControllers.removeAt(from);
    final sugg = _stopSuggestions.removeAt(from);
    final ids = _stopPickingIds.removeAt(from);
    _stopSearchControllers.insert(to, ctrl);
    _stopSuggestions.insert(to, sugg);
    _stopPickingIds.insert(to, ids);
  }

  /// Drops every stop field and leaves a single empty one.
  void _clearStopFields() {
    while (_stopSearchControllers.isNotEmpty) {
      _removeStopFieldAt(_stopSearchControllers.length - 1);
    }
    _addStopField();
  }

  /// Removes the stop field at [index] at the user's request. A stop that came
  /// from pickings takes those pickings out of the selection too, so the
  /// picker never shows a picking whose stop is gone.
  void _removeStopByUser(int index) {
    if (index < 0 || index >= _stopSearchControllers.length) return;
    final ids = _stopPickingIds[index];
    if (ids.isNotEmpty) {
      final keep = <int>[];
      final keepNames = <String>[];
      for (var i = 0; i < selectedPickings.length; i++) {
        if (ids.contains(selectedPickings[i])) continue;
        keep.add(selectedPickings[i]);
        if (i < selectedPickingNames.length) {
          keepNames.add(selectedPickingNames[i]);
        }
      }
      selectedPickings = keep;
      selectedPickingNames = keepNames;
      _syncedPickingIds = _syncedPickingIds.difference(ids);
    }
    _removeStopFieldAt(index);
    if (_stopSearchControllers.isEmpty) _addStopField();
    _refreshPickingsNoticeFromCache();
  }

  static String _placeKey(String text) => text.trim().toLowerCase();

  /// Locates [text], answering from [_geocodeCache] when it can.
  Future<LatLng?> _geocode(String text) async {
    final key = _placeKey(text);
    if (key.isEmpty) return null;
    final cached = _geocodeCache[key];
    if (cached != null) return cached;
    final latLng = await mapService.getLatLngFromPlace(
      text.trim(),
      _apiKey,
      proximity: _currentLatLng,
    );
    if (latLng != null) {
      _geocodeCache[key] = latLng;
      _geocodeMisses.remove(key);
    } else {
      _geocodeMisses.add(key);
    }
    return latLng;
  }

  /// The destination address of a picking, with Odoo's `false` parts removed.
  static String _pickingDestination(Map<String, dynamic> picking) {
    final raw = picking['destination_point'];
    if (raw is! String) return '';
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s.toLowerCase() != 'false')
        .join(', ');
  }

  /// Applies the current picking selection to the stop fields, then locates
  /// the pickings' addresses so the sheet can warn about any it can't find.
  ///
  /// Only the difference from the last applied selection is touched: a newly
  /// selected picking adds its stop, a deselected one removes its stop, and
  /// stops added by hand are never removed. Calls are queued, so "Done" and
  /// the dismiss it causes run one after the other, the second as a no-op.
  Future<void> _rebuildStopsFromSelectedPickings() {
    final previous = _stopsRebuild ?? Future<void>.value();
    final next = previous
        .catchError((_) {})
        .then((_) => _applyPickingSelection());
    _stopsRebuild = next;
    return next;
  }

  Future<void> _applyPickingSelection() async {
    final generation = _stopsGeneration;
    final selected = selectedPickings.toSet();
    final removed = _syncedPickingIds.difference(selected);
    final added = selectedPickings
        .where((id) => !_syncedPickingIds.contains(id))
        .toList();

    if (removed.isNotEmpty) {
      for (var i = _stopSearchControllers.length - 1; i >= 0; i--) {
        final ids = _stopPickingIds[i];
        if (ids.isEmpty || !ids.any(removed.contains)) continue;
        ids.removeAll(removed);
        if (ids.isEmpty) _removeStopFieldAt(i);
      }
    }

    if (added.isNotEmpty) {
      // A blank field left over from "Add another stop" would otherwise sit
      // between the stops; the new stops take its place.
      for (var i = _stopSearchControllers.length - 1; i >= 0; i--) {
        if (_stopPickingIds[i].isEmpty &&
            _stopSearchControllers[i].text.trim().isEmpty) {
          _removeStopFieldAt(i);
        }
      }
      for (final id in added) {
        final picking = pickings.cast<Map<String, dynamic>?>().firstWhere(
          (p) => p?['id'] == id,
          orElse: () => null,
        );
        if (picking == null) continue;
        final dest = _pickingDestination(picking);
        if (dest.isEmpty) continue;
        final existing = _stopSearchControllers.indexWhere(
          (c) => _placeKey(c.text) == _placeKey(dest),
        );
        if (existing >= 0) {
          _stopPickingIds[existing].add(id);
        } else {
          _addStopField(text: dest, pickingIds: {id});
        }
      }
    }

    _syncedPickingIds = Set.of(selected);
    if (_stopSearchControllers.isEmpty) _addStopField();

    // Locate the selected pickings' addresses now, so a bad address is
    // flagged in the sheet rather than only when routing.
    final toLocate = <String>{
      for (final p in pickings)
        if (selected.contains(p['id'])) _pickingDestination(p),
    }..remove('');
    for (final dest in toLocate) {
      await _geocode(dest);
      if (generation != _stopsGeneration) return;
    }
    _refreshPickingsNoticeFromCache();
  }

  /// Rewrites [_pickingsNotice] for the current selection from what is
  /// already known: pickings with no address in Odoo, and addresses that
  /// were looked up and not found.
  void _refreshPickingsNoticeFromCache() {
    final selected = selectedPickings.toSet();
    final missing = <String>[];
    final unresolved = <String>{};
    for (final p in pickings) {
      if (!selected.contains(p['id'])) continue;
      final dest = _pickingDestination(p);
      if (dest.isEmpty) {
        missing.add(cleanOdooValue(p['name'], fallback: 'Unknown'));
      } else if (_geocodeMisses.contains(_placeKey(dest))) {
        unresolved.add(dest);
      }
    }
    final String? notice;
    if (missing.isNotEmpty) {
      notice =
          '${missing.join(', ')} '
          '${missing.length == 1 ? 'has' : 'have'} '
          'no destination address in Odoo, so '
          '${missing.length == 1 ? "it is" : "they are"} not in the route. '
          'Add a stop below for any you still need to deliver.';
    } else if (unresolved.isNotEmpty) {
      notice =
          'Could not locate: ${unresolved.join(', ')}. Edit the stop or '
          'check your connection.';
    } else {
      notice = null;
    }
    if (notice != _pickingsNotice) _pickingsNoticeDismissed = false;
    _pickingsNotice = notice;
  }

  /// Locates every filled stop field and rebuilds [_stops] from them, in the
  /// fields' order. Fields that resolve are moved to the front so that
  /// `_stops[i]` and `_stopSearchControllers[i]` always describe the same
  /// stop; fields that can't be found are kept (the user's text is not
  /// thrown away) but left out of the route, and returned.
  Future<List<String>> _resolveStopFields() async {
    final generation = _stopsGeneration;
    final resolvedCtrls = <TextEditingController>[];
    final points = <LatLng>[];
    final unresolved = <String>[];

    for (final ctrl in List.of(_stopSearchControllers)) {
      final text = ctrl.text.trim();
      if (text.isEmpty) continue;
      final latLng = await _geocode(text);
      if (generation != _stopsGeneration) return const [];
      if (latLng != null) {
        resolvedCtrls.add(ctrl);
        points.add(latLng);
      } else {
        unresolved.add(text);
      }
    }

    // Order: resolved stops (as typed), then unresolved, then blanks.
    for (var target = 0; target < resolvedCtrls.length; target++) {
      final from = _stopSearchControllers.indexOf(resolvedCtrls[target]);
      if (from >= 0) _moveStopField(from, target);
    }
    _stops
      ..clear()
      ..addAll(points);
    return unresolved;
  }

  /// Shows the modal bottom sheet for selecting pickings, source, and stops.
  ///
  /// Supports multi-select pickings (auto-fills stops from destination_point),
  /// source field with Mapbox autocomplete, and dynamic stop fields.
  void _showEnterRootPopup({bool fromAddStop = false}) {
    _showPendingLocationNotice();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool popCalled = false;
    bool needsAutoRoute = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,

      enableDrag: false,
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),

      sheetAnimationStyle: AnimationStyle(
        duration: const Duration(milliseconds: 320),
        reverseDuration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      builder: (BuildContext context) {
        if (pickings.isEmpty && !_pickingsLoading && !_pickingsLoadFailed) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _fetchPickings());
        }
        bool isFetchingStops = false;
        bool didAddStopField = false;
        bool isPickingDropdownOpen = false;

        final pickingsDropdownKey =
            GlobalKey<DropdownSearchState<Map<String, dynamic>>>();
        final pickingsSearchCtrl = TextEditingController();

        /// Applies the picker's selection to the stop fields, with the sheet
        /// showing its loader meanwhile. Used by every way the selection can
        /// change: "Done", dismissing the picker, and removing a chip.
        Future<void> syncStopsWithPickings() async {
          _activeSheetSetState?.call(() => isFetchingStops = true);
          try {
            await _rebuildStopsFromSelectedPickings();
          } catch (_) {
            _pickingsNotice =
                'Couldn\'t update the stops from the selected pickings. '
                'Check your connection and try again.';
          } finally {
            if (mounted) setState(() {});
            // The sheet may have closed while the lookup ran.
            _activeSheetSetState?.call(() => isFetchingStops = false);
          }
        }

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter sheetSetState) {
            _activeSheetSetState = sheetSetState;
            if (fromAddStop && !didAddStopField) {
              didAddStopField = true;
              if (_stopSearchControllers.last.text.trim().isNotEmpty) {
                _addStopField();
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
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height * 0.70,
                    maxHeight: MediaQuery.of(context).size.height * 0.90,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                              physics: const ClampingScrollPhysics(),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Enter Route',
                                          style: GoogleFonts.manrope(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                        ),
                                      ),

                                      IconButton(
                                        tooltip: 'Close',
                                        onPressed: () => Navigator.pop(context),
                                        icon: Icon(
                                          HugeIcons.strokeRoundedCancel01,
                                          size: 22,
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black54,
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 40,
                                          minHeight: 40,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),

                                  _fieldHeading(
                                    'Pickings',
                                    isDark,
                                    isRequired: true,
                                  ),
                                  _pickingsLoading
                                      ? _buildPickingsLoadingField(isDark)
                                      : (_pickingsLoadFailed &&
                                            pickings.isEmpty)
                                      ? _buildPickingsErrorField(isDark)
                                      : Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: isPickingDropdownOpen
                                                  ? AppStyle.primaryColor
                                                  : Colors.transparent,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: DropdownSearch<Map<String, dynamic>>.multiSelection(
                                            key: pickingsDropdownKey,
                                            items: [
                                              ...pickings.where(
                                                (p) => selectedPickings
                                                    .contains(p['id']),
                                              ),
                                              ...pickings.where(
                                                (p) => !selectedPickings
                                                    .contains(p['id']),
                                              ),
                                            ],
                                            itemAsString: (p) =>
                                                p['name']?.toString() ?? '',
                                            compareFn: (a, b) =>
                                                a['id'] == b['id'],
                                            selectedItems: pickings
                                                .where(
                                                  (p) => selectedPickings
                                                      .contains(p['id']),
                                                )
                                                .toList(),
                                            onBeforePopupOpening: (_) async {
                                              pickingsSearchCtrl.clear();
                                              sheetSetState(
                                                () => isPickingDropdownOpen =
                                                    true,
                                              );
                                              return true;
                                            },
                                            onChanged: (items) {
                                              sheetSetState(() {
                                                selectedPickings = items
                                                    .map((e) => e['id'] as int)
                                                    .toList();
                                                selectedPickingNames = items
                                                    .map(
                                                      (e) =>
                                                          e['name'] as String,
                                                    )
                                                    .toList();
                                              });
                                            },

                                            dropdownBuilder: (context, selectedItems) {
                                              const int maxVisible = 2;
                                              final visibleItems = selectedItems
                                                  .take(maxVisible)
                                                  .toList();
                                              final extraCount =
                                                  selectedItems.length -
                                                  maxVisible;
                                              return Container(
                                                constraints:
                                                    const BoxConstraints(
                                                      minHeight: 24,
                                                    ),
                                                alignment: Alignment.centerLeft,
                                                child: selectedItems.isEmpty
                                                    ? Text(
                                                        'Select Pickings',
                                                        style: TextStyle(
                                                          color: isDark
                                                              ? Colors.white38
                                                              : Colors
                                                                    .grey[500],
                                                          fontStyle:
                                                              FontStyle.italic,
                                                          fontWeight:
                                                              FontWeight.w400,
                                                          fontSize: 14,
                                                        ),
                                                      )
                                                    : Wrap(
                                                        spacing: 6,
                                                        runSpacing: 6,
                                                        children: [
                                                          ...visibleItems.map((
                                                            item,
                                                          ) {
                                                            return Container(
                                                              padding:
                                                                  const EdgeInsets.only(
                                                                    left: 10,
                                                                    right: 6,
                                                                    top: 4,
                                                                    bottom: 4,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color: AppStyle
                                                                    .primaryColor
                                                                    .withValues(
                                                                      alpha:
                                                                          0.12,
                                                                    ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      20,
                                                                    ),
                                                              ),
                                                              child: Row(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                children: [
                                                                  Text(
                                                                    item['name']
                                                                            ?.toString() ??
                                                                        '',
                                                                    style: const TextStyle(
                                                                      fontSize:
                                                                          12,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w500,
                                                                      color: AppStyle
                                                                          .primaryColor,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 4,
                                                                  ),
                                                                  GestureDetector(
                                                                    behavior:
                                                                        HitTestBehavior
                                                                            .opaque,
                                                                    onTap: () {
                                                                      final updated =
                                                                          List<
                                                                              Map<
                                                                                String,
                                                                                dynamic
                                                                              >
                                                                            >.from(
                                                                              selectedItems,
                                                                            )
                                                                            ..removeWhere(
                                                                              (
                                                                                s,
                                                                              ) =>
                                                                                  s['id'] ==
                                                                                  item['id'],
                                                                            );
                                                                      sheetSetState(() {
                                                                        selectedPickings = updated
                                                                            .map(
                                                                              (
                                                                                e,
                                                                              ) =>
                                                                                  e['id']
                                                                                      as int,
                                                                            )
                                                                            .toList();
                                                                        selectedPickingNames = updated
                                                                            .map(
                                                                              (
                                                                                e,
                                                                              ) =>
                                                                                  e['name']
                                                                                      as String,
                                                                            )
                                                                            .toList();
                                                                      });
                                                                      pickingsDropdownKey
                                                                          .currentState
                                                                          ?.changeSelectedItems(
                                                                            updated,
                                                                          );
                                                                      // Removing a chip never opens the
                                                                      // picker, so its dismiss won't
                                                                      // sync the stops for us.
                                                                      syncStopsWithPickings();
                                                                    },
                                                                    child: const Icon(
                                                                      HugeIcons
                                                                          .strokeRoundedCancel01,
                                                                      size: 14,
                                                                      color: AppStyle
                                                                          .primaryColor,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            );
                                                          }),
                                                          if (extraCount > 0)
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        10,
                                                                    vertical: 4,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color: isDark
                                                                    ? Colors
                                                                          .white12
                                                                    : Colors
                                                                          .grey[200],
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      20,
                                                                    ),
                                                              ),
                                                              child: Text(
                                                                '+$extraCount more',
                                                                style: TextStyle(
                                                                  fontSize: 12,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                  color: isDark
                                                                      ? Colors
                                                                            .white54
                                                                      : Colors
                                                                            .grey[700],
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                              );
                                            },
                                            dropdownDecoratorProps: DropDownDecoratorProps(
                                              dropdownSearchDecoration: InputDecoration(
                                                isDense: true,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 14,
                                                    ),
                                                filled: true,
                                                fillColor: isDark
                                                    ? const Color(0xFF2A2A2A)
                                                    : const Color(0xffF8FAFB),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  borderSide: BorderSide.none,
                                                ),
                                                enabledBorder:
                                                    OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                      borderSide:
                                                          BorderSide.none,
                                                    ),
                                                focusedBorder:
                                                    OutlineInputBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                      borderSide:
                                                          BorderSide.none,
                                                    ),
                                              ),
                                            ),
                                            popupProps: PopupPropsMultiSelection.menu(
                                              onDismissed: () async {
                                                sheetSetState(
                                                  () => isPickingDropdownOpen =
                                                      false,
                                                );
                                                await syncStopsWithPickings();
                                              },
                                              showSearchBox: false,
                                              searchFieldProps: TextFieldProps(
                                                controller: pickingsSearchCtrl,
                                              ),
                                              showSelectedItems: true,
                                              menuProps: MenuProps(
                                                backgroundColor: isDark
                                                    ? Colors.grey[850]
                                                    : Colors.white,
                                                elevation: 4,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                              constraints: const BoxConstraints(
                                                maxHeight: 380,
                                              ),
                                              validationWidgetBuilder:
                                                  (context, __) =>
                                                      const SizedBox.shrink(),
                                              selectionWidget:
                                                  (context, item, isSelected) =>
                                                      const SizedBox.shrink(),
                                              onItemAdded: (selectedItems, _) {
                                                sheetSetState(() {
                                                  selectedPickings =
                                                      selectedItems
                                                          .map(
                                                            (e) =>
                                                                e['id'] as int,
                                                          )
                                                          .toList();
                                                  selectedPickingNames =
                                                      selectedItems
                                                          .map(
                                                            (e) =>
                                                                e['name']
                                                                    as String,
                                                          )
                                                          .toList();
                                                });
                                              },
                                              onItemRemoved: (selectedItems, _) {
                                                sheetSetState(() {
                                                  selectedPickings =
                                                      selectedItems
                                                          .map(
                                                            (e) =>
                                                                e['id'] as int,
                                                          )
                                                          .toList();
                                                  selectedPickingNames =
                                                      selectedItems
                                                          .map(
                                                            (e) =>
                                                                e['name']
                                                                    as String,
                                                          )
                                                          .toList();
                                                });
                                              },
                                              title: Container(
                                                decoration: BoxDecoration(
                                                  border: Border(
                                                    bottom: BorderSide(
                                                      color: isDark
                                                          ? Colors.white12
                                                          : const Color(
                                                              0xFFE0E0E0,
                                                            ),
                                                      width: 0.8,
                                                    ),
                                                  ),
                                                ),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.fromLTRB(
                                                            16,
                                                            12,
                                                            16,
                                                            8,
                                                          ),
                                                      child: Text(
                                                        'Select Pickings',
                                                        style: TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: isDark
                                                              ? Colors.white
                                                              : Colors.black87,
                                                        ),
                                                      ),
                                                    ),
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                          ),
                                                      child: TextField(
                                                        controller:
                                                            pickingsSearchCtrl,
                                                        decoration: InputDecoration(
                                                          hintText: 'Search...',
                                                          filled: true,
                                                          fillColor: isDark
                                                              ? Colors.grey[800]
                                                              : const Color(
                                                                  0xFFF3F4F6,
                                                                ),
                                                          prefixIcon: Icon(
                                                            HugeIcons
                                                                .strokeRoundedSearch01,
                                                            size: 20,
                                                            color: isDark
                                                                ? Colors.white54
                                                                : Colors
                                                                      .grey[600],
                                                          ),
                                                          contentPadding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 12,
                                                                vertical: 10,
                                                              ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                            borderSide:
                                                                BorderSide.none,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.fromLTRB(
                                                            16,
                                                            6,
                                                            16,
                                                            10,
                                                          ),
                                                      child: Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          GestureDetector(
                                                            onTap: () {
                                                              pickingsDropdownKey
                                                                  .currentState
                                                                  ?.changeSelectedItems(
                                                                    [],
                                                                  );
                                                              sheetSetState(() {
                                                                selectedPickings
                                                                    .clear();
                                                                selectedPickingNames
                                                                    .clear();
                                                              });
                                                            },
                                                            child: Text(
                                                              'Clear',
                                                              style: TextStyle(
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                color: isDark
                                                                    ? Colors
                                                                          .white38
                                                                    : Colors
                                                                          .grey[500],
                                                              ),
                                                            ),
                                                          ),

                                                          GestureDetector(
                                                            onTap: () async {
                                                              if (isFetchingStops) {
                                                                return;
                                                              }
                                                              pickingsSearchCtrl
                                                                  .clear();
                                                              pickingsDropdownKey
                                                                  .currentState
                                                                  ?.closeDropDownSearch();
                                                              await syncStopsWithPickings();
                                                              _activeSheetSetState
                                                                  ?.call(
                                                                    () => shouldValidate =
                                                                        false,
                                                                  );
                                                            },
                                                            child: Text(
                                                              'Done',
                                                              style: TextStyle(
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: AppStyle
                                                                    .primaryColor,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              itemBuilder: (context, item, isSelected) {
                                                return Container(
                                                  color: Colors.transparent,
                                                  padding:
                                                      const EdgeInsets.only(
                                                        left: 16,
                                                        right: 4,
                                                        top: 4,
                                                        bottom: 4,
                                                      ),
                                                  child: Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          item['name']
                                                                  ?.toString() ??
                                                              '-',
                                                          style: TextStyle(
                                                            fontSize: 15,
                                                            fontWeight:
                                                                FontWeight
                                                                    .normal,
                                                            color: isDark
                                                                ? Colors.white
                                                                : Colors
                                                                      .black87,
                                                          ),
                                                        ),
                                                      ),
                                                      Checkbox(
                                                        value: isSelected,
                                                        onChanged: (_) {},
                                                        checkColor:
                                                            Colors.white,
                                                        fillColor:
                                                            WidgetStateProperty.resolveWith<
                                                              Color
                                                            >(
                                                              (states) =>
                                                                  states.contains(
                                                                    WidgetState
                                                                        .selected,
                                                                  )
                                                                  ? AppStyle
                                                                        .primaryColor
                                                                  : Colors
                                                                        .transparent,
                                                            ),
                                                        side: const BorderSide(
                                                          color: AppStyle
                                                              .primaryColor,
                                                          width: 1.5,
                                                        ),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),

                                  if (shouldValidate) ...[
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Select a picking or add a stop',
                                        style: TextStyle(
                                          color: Colors.red[400],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],

                                  if (_pickingsNotice != null &&
                                      !_pickingsNoticeDismissed) ...[
                                    const SizedBox(height: 10),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: AppColors.warningIconBackground,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: AppColors.warning.withValues(
                                            alpha: 0.4,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            HugeIcons.strokeRoundedAlert02,
                                            size: 16,
                                            color: AppColors.warning,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _pickingsNotice!,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isDark
                                                    ? AppColors.warningIcon
                                                    : AppColors.warning,
                                              ),
                                            ),
                                          ),
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () => sheetSetState(
                                              () => _pickingsNoticeDismissed =
                                                  true,
                                            ),
                                            child: const Padding(
                                              padding: EdgeInsets.only(
                                                left: 8,
                                                top: 1,
                                              ),
                                              child: Icon(
                                                HugeIcons.strokeRoundedCancel01,
                                                size: 14,
                                                color: AppColors.warning,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 18),

                                  _fieldHeading('Source Location', isDark),
                                  if (sourceController.text == 'Your Location')
                                    _buildCurrentLocationChip(
                                      isDark: isDark,
                                      onSurface: onSurface,
                                      onClear: () {
                                        sheetSetState(() {
                                          sourceController.clear();
                                          _sourceSuggestions.clear();
                                        });
                                        setState(() => _sourceLatLng = null);
                                      },
                                    )
                                  else
                                    Focus(
                                      onFocusChange: (hasFocus) async {
                                        if (hasFocus) {
                                          sheetSetState(() {
                                            if (_sourceSuggestions.isEmpty) {
                                              _sourceSuggestions = [
                                                'Your Location',
                                              ];
                                            }
                                          });
                                        } else {
                                          await Future.delayed(
                                            const Duration(milliseconds: 150),
                                          );
                                          sheetSetState(
                                            () => _sourceSuggestions.clear(),
                                          );
                                        }
                                      },
                                      child: MoboTextField(
                                        controller: sourceController,
                                        hintText: 'Search location',
                                        onChanged: (value) async {
                                          if (value.trim().isEmpty) {
                                            sheetSetState(
                                              () => _sourceSuggestions = [
                                                'Your Location',
                                              ],
                                            );
                                            return;
                                          }
                                          final suggestions = await mapService
                                              .fetchSuggestions(
                                                value,
                                                _apiKey,
                                                proximity: _currentLatLng,
                                              );
                                          sheetSetState(
                                            () => _sourceSuggestions = [
                                              'Your Location',
                                              ...suggestions,
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  if (_sourceSuggestions.isNotEmpty &&
                                      sourceController.text != 'Your Location')
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
                                        itemCount: _sourceSuggestions.length,
                                        separatorBuilder: (_, __) => Divider(
                                          height: 1,
                                          color: onSurface.withValues(
                                            alpha: 0.08,
                                          ),
                                        ),
                                        itemBuilder: (context, index) {
                                          return InkWell(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            onTap: () async {
                                              final selected =
                                                  _sourceSuggestions[index];
                                              sourceController.text = selected;
                                              sheetSetState(
                                                () =>
                                                    _sourceSuggestions.clear(),
                                              );
                                              if (selected == 'Your Location') {
                                                if (_currentLatLng != null) {
                                                  setState(
                                                    () => _sourceLatLng =
                                                        _currentLatLng,
                                                  );
                                                }
                                              } else {
                                                _sourceLatLng = await mapService
                                                    .getLatLngFromPlace(
                                                      selected,
                                                      _apiKey,
                                                      proximity: _currentLatLng,
                                                    );
                                              }
                                              setState(() {});
                                            },
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 12,
                                                  ),
                                              child:
                                                  _sourceSuggestions[index] ==
                                                      'Your Location'
                                                  ? Row(
                                                      children: [
                                                        SizedBox(
                                                          width: 20,
                                                          height: 20,
                                                          child: Stack(
                                                            alignment: Alignment
                                                                .center,
                                                            children: [
                                                              Container(
                                                                width: 20,
                                                                height: 20,
                                                                decoration: BoxDecoration(
                                                                  color:
                                                                      const Color(
                                                                        0xFF4285F4,
                                                                      ).withValues(
                                                                        alpha:
                                                                            0.18,
                                                                      ),
                                                                  shape: BoxShape
                                                                      .circle,
                                                                ),
                                                              ),
                                                              Container(
                                                                width: 10,
                                                                height: 10,
                                                                decoration: const BoxDecoration(
                                                                  color: Color(
                                                                    0xFF4285F4,
                                                                  ),
                                                                  shape: BoxShape
                                                                      .circle,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 10,
                                                        ),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Text(
                                                                'Your location',
                                                                style: TextStyle(
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                  color:
                                                                      onSurface,
                                                                ),
                                                              ),
                                                              const Text(
                                                                'Using GPS',
                                                                style: TextStyle(
                                                                  fontSize: 11,
                                                                  color: Color(
                                                                    0xFF4285F4,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    )
                                                  : Row(
                                                      children: [
                                                        Icon(
                                                          HugeIcons
                                                              .strokeRoundedLocation01,
                                                          size: 18,
                                                          color: onSurface
                                                              .withValues(
                                                                alpha: 0.5,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          width: 10,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            _sourceSuggestions[index],
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              color: onSurface,
                                                            ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),

                                  ...List.generate(_stopSearchControllers.length, (
                                    index,
                                  ) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        const SizedBox(height: 18),
                                        _stopFieldHeading(index, isDark),
                                        Focus(
                                          onFocusChange: (hasFocus) async {
                                            if (hasFocus) return;
                                            final ctrl =
                                                _stopSearchControllers[index];
                                            await Future.delayed(
                                              const Duration(milliseconds: 150),
                                            );
                                            final i = _stopSearchControllers
                                                .indexOf(ctrl);
                                            if (i < 0) return;
                                            _activeSheetSetState?.call(
                                              () => _stopSuggestions[i].clear(),
                                            );
                                          },
                                          child: MoboTextField(
                                            controller:
                                                _stopSearchControllers[index],
                                            hintText: 'Add your stop',
                                            showShadow: false,
                                            suffixIcon: _canRemoveStop(index)
                                                ? IconButton(
                                                    tooltip: 'Remove stop',
                                                    icon: Icon(
                                                      HugeIcons
                                                          .strokeRoundedCancel01,
                                                      size: 18,
                                                      color: onSurface
                                                          .withValues(
                                                            alpha: 0.5,
                                                          ),
                                                    ),
                                                    onPressed: () {
                                                      FocusScope.of(
                                                        context,
                                                      ).unfocus();
                                                      sheetSetState(
                                                        () => _removeStopByUser(
                                                          index,
                                                        ),
                                                      );
                                                      pickingsDropdownKey
                                                          .currentState
                                                          ?.changeSelectedItems(
                                                            pickings
                                                                .where(
                                                                  (
                                                                    p,
                                                                  ) => selectedPickings
                                                                      .contains(
                                                                        p['id'],
                                                                      ),
                                                                )
                                                                .toList(),
                                                          );
                                                      setState(() {});
                                                    },
                                                  )
                                                : null,
                                            onChanged: (value) async {
                                              final ctrl =
                                                  _stopSearchControllers[index];
                                              if (_stopFieldErrors.containsKey(
                                                    ctrl,
                                                  ) ||
                                                  shouldValidate) {
                                                sheetSetState(() {
                                                  _stopFieldErrors.remove(ctrl);
                                                  shouldValidate = false;
                                                });
                                              }
                                              final suggestions =
                                                  await mapService
                                                      .fetchSuggestions(
                                                        value,
                                                        _apiKey,
                                                        proximity:
                                                            _currentLatLng,
                                                      );
                                              // The field may have been
                                              // removed, or typed on since.
                                              final i = _stopSearchControllers
                                                  .indexOf(ctrl);
                                              if (i < 0 || ctrl.text != value) {
                                                return;
                                              }
                                              _activeSheetSetState?.call(
                                                () => _stopSuggestions[i] =
                                                    suggestions,
                                              );
                                            },
                                          ),
                                        ),
                                        if (_stopFieldErrors[_stopSearchControllers[index]]
                                            case final error?)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                              left: 2,
                                            ),
                                            child: Text(
                                              error,
                                              style: TextStyle(
                                                color: Colors.red[400],
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        if (_stopSuggestions[index].isNotEmpty)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isDark
                                                  ? Colors.grey[850]
                                                  : Colors.grey[50],
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: ListView.separated(
                                              shrinkWrap: true,
                                              padding: EdgeInsets.zero,
                                              physics:
                                                  const NeverScrollableScrollPhysics(),
                                              itemCount: _stopSuggestions[index]
                                                  .length,
                                              separatorBuilder: (_, __) =>
                                                  Divider(
                                                    height: 1,
                                                    color: onSurface.withValues(
                                                      alpha: 0.08,
                                                    ),
                                                  ),
                                              itemBuilder: (context, si) {
                                                return InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  onTap: () async {
                                                    final nav = Navigator.of(
                                                      context,
                                                    );
                                                    final ctrl =
                                                        _stopSearchControllers[index];
                                                    final picked =
                                                        _stopSuggestions[index][si];
                                                    ctrl.text = picked;
                                                    FocusScope.of(
                                                      context,
                                                    ).unfocus();
                                                    sheetSetState(() {
                                                      _stopSuggestions[index]
                                                          .clear();
                                                      _stopFieldErrors.remove(
                                                        ctrl,
                                                      );
                                                    });
                                                    final stopLatLng =
                                                        await _geocode(picked);
                                                    final i =
                                                        _stopSearchControllers
                                                            .indexOf(ctrl);
                                                    if (!mounted || i < 0) {
                                                      return;
                                                    }
                                                    if (stopLatLng == null) {
                                                      _activeSheetSetState?.call(
                                                        () => _stopFieldErrors[ctrl] =
                                                            'Couldn\'t locate this place. '
                                                            'Try another suggestion or '
                                                            'check your connection.',
                                                      );
                                                      return;
                                                    }
                                                    // A stop added during a
                                                    // route joins before the
                                                    // final destination, which
                                                    // stays last.
                                                    final hasOtherStops =
                                                        _stopSearchControllers
                                                            .any(
                                                              (c) =>
                                                                  c != ctrl &&
                                                                  c.text
                                                                      .trim()
                                                                      .isNotEmpty,
                                                            );
                                                    if (fromAddStop &&
                                                        hasOtherStops &&
                                                        i ==
                                                            _stopSearchControllers
                                                                    .length -
                                                                1) {
                                                      _moveStopField(i, 0);
                                                    }
                                                    setState(() {});
                                                    _activeSheetSetState?.call(
                                                      () {},
                                                    );
                                                    if (fromAddStop &&
                                                        !popCalled) {
                                                      needsAutoRoute = true;
                                                      popCalled = true;
                                                      nav.pop();
                                                    }
                                                  },
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 14,
                                                          vertical: 12,
                                                        ),
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          HugeIcons
                                                              .strokeRoundedLocation01,
                                                          size: 18,
                                                          color: onSurface
                                                              .withValues(
                                                                alpha: 0.5,
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          width: 10,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            _stopSuggestions[index][si],
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              color: onSurface,
                                                            ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
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

                                  if (_stopSearchControllers.isEmpty ||
                                      _stopSearchControllers.last.text
                                          .trim()
                                          .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: () {
                                          sheetSetState(_addStopField);
                                        },
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 6,
                                          ),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          foregroundColor:
                                              AppStyle.primaryColor,
                                        ),
                                        icon: const Icon(
                                          HugeIcons.strokeRoundedAdd01,
                                          size: 18,
                                        ),
                                        label: Text(
                                          'Add another stop',
                                          style: GoogleFonts.manrope(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppStyle.primaryColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => Navigator.pop(context),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(
                                        double.infinity,
                                        44,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      side: BorderSide(
                                        color: theme.primaryColor,
                                      ),
                                      foregroundColor: theme.primaryColor,
                                    ),
                                    child: const Text(
                                      'Cancel',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(
                                        double.infinity,
                                        44,
                                      ),
                                      backgroundColor: theme.primaryColor,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      elevation: 0,
                                    ),
                                    onPressed: () async {
                                      // Edit opens this sheet without
                                      // "fromAddStop", and a route can be
                                      // made of typed stops alone.
                                      final hasTypedStop =
                                          _stopSearchControllers.any(
                                            (c) => c.text.trim().isNotEmpty,
                                          );
                                      if (!fromAddStop &&
                                          selectedPickings.isEmpty &&
                                          !hasTypedStop) {
                                        // Say so where the driver is
                                        // looking, without closing the sheet.
                                        setState(() => shouldValidate = true);
                                        sheetSetState(() {});
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
                                          RouteNavigationBus.set(false);
                                        }
                                        sourceSearchController.text =
                                            sourceController.text;
                                      });
                                      await _getOptimizedRoute();
                                      if (mounted) setState(() {});
                                    },
                                    icon: const Icon(
                                      HugeIcons.strokeRoundedNavigation03,
                                      size: 18,
                                    ),
                                    label: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'Show Directions',
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
      _activeSheetSetState = null;
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
        RouteNavigationBus.set(false);
        _getOptimizedRoute();
      });
    });
  }

  /// Left-aligned static heading shown above an input box in the bottom sheet.
  /// When [isRequired] is true a red `*` marks the field.
  /// A stop can be removed when it holds something, or when it isn't the
  /// only field — the sheet always keeps one field to type into.
  bool _canRemoveStop(int index) =>
      _stopSearchControllers.length > 1 ||
      _stopSearchControllers[index].text.trim().isNotEmpty;

  /// "Stop N", followed by the picking(s) it was filled from, so the driver
  /// can tell which stops came from Odoo and which they typed. The reference
  /// reads as part of the heading rather than sitting out on the right, and
  /// it stays out of the field so the address keeps its full width.
  Widget _stopFieldHeading(int index, bool isDark) {
    final ids = _stopPickingIds[index];
    final names = [
      for (final p in pickings)
        if (ids.contains(p['id'])) cleanOdooValue(p['name'], fallback: ''),
    ].where((n) => n.isNotEmpty).toList();
    if (names.isEmpty) return _fieldHeading('Stop ${index + 1}', isDark);
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6),
      child: Row(
        children: [
          RequiredLabel('Stop ${index + 1}'),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '\u00b7 ${names.join(', ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white54 : Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldHeading(String text, bool isDark, {bool isRequired = false}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: RequiredLabel(text, isRequired: isRequired),
      ),
    );
  }

  /// Placeholder shown in the Pickings field while [_fetchPickings] is in
  /// flight, so opening the sheet before it finishes reads as "loading"
  /// rather than the indistinguishable, seemingly-empty "No data found".
  Widget _buildPickingsLoadingField(bool isDark) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? Colors.grey[850] : Colors.grey[100],
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppStyle.primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Loading pickings…',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// Floats over the map while it is showing [_fallbackCenter], so a map of
  /// somewhere else is not mistaken for the user's surroundings, and gives a
  /// way to try again without leaving the tab.
  Widget _buildLocationUnavailableCard(bool isDark) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(14),
      color: isDark ? const Color(0xFF2C2C3E) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Icon(
              HugeIcons.strokeRoundedLocationOffline01,
              color: AppStyle.primaryColor,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Location unavailable',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Couldn\'t get your position. Retry, or set a source in Enter Route.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            _isLocating
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppStyle.primaryColor,
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: _setInitialLocation,
                    style: TextButton.styleFrom(
                      foregroundColor: AppStyle.primaryColor,
                    ),
                    child: const Text(
                      'Retry',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  /// Shown in the Pickings field when [_fetchPickings] fails, with a tap
  /// target to retry instead of leaving the field looking like it simply
  /// has no pickings to offer.
  Widget _buildPickingsErrorField(bool isDark) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _fetchPickings,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isDark ? Colors.grey[850] : Colors.grey[100],
        ),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(
              HugeIcons.strokeRoundedAlert02,
              size: 16,
              color: Colors.red[400],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Could not load pickings.',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white60 : Colors.grey[600],
                ),
              ),
            ),
            Text(
              'Retry',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppStyle.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentLocationChip({
    required bool isDark,
    required Color onSurface,
    required VoidCallback onClear,
  }) {
    return _GpsLocationChip(
      isDark: isDark,
      onSurface: onSurface,
      onClear: onClear,
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
                    minZoom: _kMinMapZoom,
                    maxZoom: _kMaxMapZoom,
                    backgroundColor: isDark
                        ? const Color(0xFF1B2733)
                        : const Color(0xFFAAD3DF),
                    cameraConstraint: CameraConstraint.contain(
                      bounds: LatLngBounds(
                        const LatLng(-85.0, -180.0),
                        const LatLng(85.0, 180.0),
                      ),
                    ),
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
                    MarkerLayer(
                      markers: [
                        ..._markers,
                        if (_currentLocationMarker != null)
                          _currentLocationMarker!,
                        if (_movingMarker != null) _movingMarker!,
                      ],
                    ),
                  ],
                ),

                if (!isOnline) ErrorStateWidget(onRetry: _initializeServices),

                if (!_infoCard &&
                    _showLocationNames &&
                    !_isNavigationStarted) ...[
                  Positioned(
                    top: 40,
                    left: 16,
                    right: 16,
                    child: SearchInputs(
                      sourceController: sourceSearchController,
                      // Once routed, only the stops on the route; one that
                      // couldn't be located stays in the sheet to be fixed.
                      stopControllers: _stops.isEmpty
                          ? _stopSearchControllers
                          : _stopSearchControllers.take(_stops.length).toList(),
                      showStopFields: _showStopLocationFields,
                      onClose: _resetNavigation,
                      onEdit: _isLoading ? null : () => _showEnterRootPopup(),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: RouteInfoCard(
                      routeDuration: _routeDuration,
                      routeDistance: _routeDistance,
                      legInfo: _legInfo,
                      routeError: _routeError,
                      onStartPressed:
                          (_routeError == null &&
                              _sourceLatLng != null &&
                              _stops.isNotEmpty)
                          ? _startNavigation
                          : null,
                      onAddStopPressed: () {
                        setState(() => _showStopLocationFields = true);
                        _showEnterRootPopup(fromAddStop: true);
                      },
                      onOpenInMapsPressed:
                          (_routeError == null && _stops.isNotEmpty)
                          ? _openInExternalMaps
                          : null,
                      isOpeningInMaps: _openingExternalMaps,
                    ),
                  ),
                ],

                if (_isNavigationStarted) ...[
                  Positioned(
                    top: 40,
                    left: 16,
                    right: 16,
                    child: NavigationHeader(onClose: _resetNavigation),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: RemainingInfoCard(
                      remainingDistance: _remainingDistance,
                      remainingDuration: _remainingDuration,
                      remainingLegInfo: _remainingLegInfo,
                      isLoading: false,
                      onFocusPressed: (latLng) {
                        if (latLng != null) {
                          _mapController.move(latLng, 15);
                          setState(() => _isMapManuallyMoved = true);
                        }
                      },
                      onOpenInMapsPressed: _stops.isNotEmpty
                          ? _openInExternalMaps
                          : null,
                      isOpeningInMaps: _openingExternalMaps,
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

                if (_locationUnavailable &&
                    isOnline &&
                    !_isNavigationStarted &&
                    !(!_infoCard && _showLocationNames))
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: _buildLocationUnavailableCard(isDark),
                  ),

                if (_isLoading)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppStyle.primaryColor,
                      ),
                    ),
                  ),
              ],
            ),

      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: _isNavigationStarted ? 310 : 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (_showOtherFABs) ...[
              FloatingActionButton(
                heroTag: 'routeEnterRoot',
                backgroundColor: isDark
                    ? const Color(0xFF2C2C3E)
                    : Colors.white,
                foregroundColor: AppStyle.accentOf(context),
                elevation: 4,
                onPressed: _showEnterRootPopup,
                child: const Icon(HugeIcons.strokeRoundedRoute03),
              ),
              const SizedBox(height: 10),
              FloatingActionButton(
                heroTag: 'routeRecenterInitial',
                backgroundColor: isDark
                    ? const Color(0xFF2C2C3E)
                    : Colors.white,
                foregroundColor: AppStyle.accentOf(context),
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
                          _buildMapTypeIcon(
                            'basic/main',
                            HugeIcons.strokeRoundedMaps,
                            'Normal',
                          ),
                          _buildMapTypeIcon(
                            'sat/main',
                            HugeIcons.strokeRoundedSatellite02,
                            'Satellite',
                          ),
                          _buildMapTypeIcon(
                            'basic/night',
                            HugeIcons.strokeRoundedMountain,
                            'Night',
                          ),
                          _buildMapTypeIcon(
                            'hybrid/main',
                            HugeIcons.strokeRoundedGlobe02,
                            'Hybrid',
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  FloatingActionButton(
                    backgroundColor: isDark
                        ? const Color(0xFF2C2C3E)
                        : Colors.white,
                    foregroundColor: AppStyle.accentOf(context),
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
              if (_isMapManuallyMoved && _currentLatLng != null) ...[
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: 'routeRecenterCurrent',
                  backgroundColor: isDark
                      ? const Color(0xFF2C2C3E)
                      : Colors.white,
                  foregroundColor: AppStyle.primaryColor,
                  elevation: 4,
                  tooltip: 'Re-center on current location',
                  onPressed: () {
                    _mapController.move(_currentLatLng!, 17.0);
                    setState(() => _isMapManuallyMoved = false);
                  },
                  child: const Icon(HugeIcons.strokeRoundedLocation03),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Starts live navigation: subscribes to GPS, starts the periodic distance timer.
  Future<void> _startNavigation() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _isLoading = false);
          CustomSnackbar.showWarning(
            context,
            'Turn on location services to start live navigation.',
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

    if (_currentLatLng != null && _sourceLatLng != null) {
      final distanceToStart = mapService.distanceBetweenPoints(
        _currentLatLng!,
        _sourceLatLng!,
      );
      if (distanceToStart > 5000) {
        if (!mounted) return;
        final km = (distanceToStart / 1000).toStringAsFixed(1);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return CommonDialog(
              title: 'Far from Route Start',
              message:
                  'Your current location is $km km away from the route\'s '
                  'starting point. Navigation may re-route immediately or '
                  'be inaccurate. Continue anyway?',
              icon: HugeIcons.strokeRoundedLocation01,
              topIconCentered: true,
              secondaryLabel: 'Cancel',
              onSecondary: () => Navigator.pop(ctx, false),
              primaryLabel: 'Continue',
              onPrimary: () => Navigator.pop(ctx, true),
            );
          },
        );
        if (confirmed != true) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }
      }
    }

    if (!mounted) return;
    RouteNavigationBus.set(true);
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

    _locationSubscription?.cancel();
    LatLng? lastPosition;
    List<LatLng> currentPolylinePoints = _polylines.isNotEmpty
        ? _polylines.first.points
        : [];

    _locationSubscription = _location.onLocationChanged.listen((
      locationData,
    ) async {
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
          currentLatLng,
          currentPolylinePoints,
        );
        if (distance > 50.0) {
          setState(() {
            _sourceLatLng = currentLatLng;
            sourceController.text = 'Your Location';
          });
          await _getOptimizedRoute();
          currentPolylinePoints = _polylines.isNotEmpty
              ? _polylines.first.points
              : [];
          if (_polylines.isEmpty) {
            await mapService.playWrongPathSound();
            if (mounted) {
              CustomSnackbar.showWarning(
                context,
                'You are off route and a new route could not be calculated. '
                'Check your connection or adjust your destination.',
              );
            }
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
        _locationUnavailable = false;
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

  /// Hands the planned route to a map app on the phone.
  ///
  /// Android sends every stop to Google Maps (or the browser when it isn't
  /// installed). iOS asks between Google Maps, when installed, and Apple
  /// Maps; otherwise it goes straight to Apple Maps. Whatever a link can't
  /// carry is said out loud rather than silently dropped.
  Future<void> _openInExternalMaps() async {
    if (_openingExternalMaps) return;
    if (_stops.isEmpty) {
      CustomSnackbar.showWarning(
        context,
        'Get directions first, then open the route in Maps.',
      );
      return;
    }
    final stops = List<LatLng>.of(_stops);
    final firstStopName = _stopSearchControllers.isNotEmpty
        ? _stopSearchControllers.first.text
        : null;
    // Starting from the phone's own location lets Google Maps begin
    // turn-by-turn navigation; a typed source opens as a route preview.
    final fromDevice =
        _isNavigationStarted || sourceController.text == 'Your Location';
    final origin = fromDevice ? null : _sourceLatLng;

    setState(() => _openingExternalMaps = true);
    try {
      var app = ExternalMapsApp.google;
      if (Platform.isIOS) {
        final hasGoogle = await _externalMaps.isGoogleMapsInstalled();
        if (!mounted) return;
        if (hasGoogle) {
          final choice = await showMapsAppPicker(
            context,
            stopCount: stops.length,
          );
          if (choice == null || !mounted) return;
          app = choice;
        } else {
          app = ExternalMapsApp.apple;
        }
      }

      final link = app == ExternalMapsApp.google
          ? _externalMaps.googleDirections(
              origin: origin,
              stops: stops,
              travelMode: _selectedTravelMode,
            )
          : _externalMaps.appleDirections(
              origin: origin,
              destination: stops.first,
              destinationAddress: firstStopName,
              travelMode: _selectedTravelMode,
              stopsTotal: stops.length,
            );

      final opened = await _externalMaps.open(link.uri);
      if (!mounted) return;
      if (!opened) {
        CustomSnackbar.showError(
          context,
          app == ExternalMapsApp.google
              ? 'Couldn\'t open Google Maps. Install Google Maps or a web '
                    'browser and try again.'
              : 'Couldn\'t open Apple Maps. Check it hasn\'t been removed '
                    'from this iPhone and try again.',
        );
      } else if (link.isTruncated) {
        CustomSnackbar.showWarning(
          context,
          app == ExternalMapsApp.google
              ? 'Google Maps takes up to ${ExternalMapsService.googleMaxStops} '
                    'stops, so the first ${link.stopsSent} of '
                    '${link.stopsTotal} were sent. The rest are still on '
                    'this route.'
              : 'Apple Maps opened with your next stop only. Use Google Maps '
                    'for the whole route.',
        );
      }
    } catch (_) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Couldn\'t open the route in Maps. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _openingExternalMaps = false);
    }
  }

  /// Resets all navigation state back to the idle map view.
  void _resetNavigation() {
    RouteNavigationBus.set(false);
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
      _currentLocationMarker = null;
      _movingMarker = null;
      _legInfo = [];
      _remainingLegInfo = [];
      _locationSubscription?.cancel();
      _distanceUpdateTimer?.cancel();
      _clearStopFields();
      sourceController.text = 'Your Location';
      // The label now says "Your Location", so the point must match it.
      _sourceLatLng = _currentLatLng;
      selectedPickings.clear();
      selectedPickingNames.clear();
      // Forget what the stops were built from too. Leaving this behind is
      // what made re-selecting the same picking after closing a route add
      // no stop at all ("No stops to route to yet") until an app restart.
      _syncedPickingIds = <int>{};
      _stopsRebuild = null;
      _stopsGeneration++;
      _pickingsNotice = null;
      _pickingsNoticeDismissed = false;
      _routeError = null;
      shouldValidate = false;
      _showStopLocationFields = false;
      _stops.clear();
      if (_currentLatLng != null) {
        _setCurrentLocationMarker(_currentLatLng!);
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

/// Animated "Your location / Using GPS" chip with a light-green pulsing dot.
/// Owns its own [AnimationController] so it doesn't pollute the parent state.
class _GpsLocationChip extends StatefulWidget {
  final bool isDark;
  final Color onSurface;
  final VoidCallback onClear;

  const _GpsLocationChip({
    required this.isDark,
    required this.onSurface,
    required this.onClear,
  });

  @override
  State<_GpsLocationChip> createState() => _GpsLocationChipState();
}

class _GpsLocationChipState extends State<_GpsLocationChip>
    with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF4CAF50);
  late final AnimationController _controller;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _pulseScale = Tween<double>(
      begin: 1.0,
      end: 3.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _pulseOpacity = Tween<double>(
      begin: 0.7,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: widget.isDark
            ? const Color(0xFF2A2A2A)
            : const Color(0xffF8FAFB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 54,
              height: 54,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (_, __) => Opacity(
                      opacity: _pulseOpacity.value,
                      child: Transform.scale(
                        scale: _pulseScale.value,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.35),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),

                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: _green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      HugeIcons.strokeRoundedGps01,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Your location',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: widget.isDark
                        ? Colors.white
                        : const Color(0xFF202124),
                  ),
                ),
                const SizedBox(height: 1),
                const Text(
                  'Using GPS',
                  style: TextStyle(
                    fontSize: 11,
                    color: _green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: widget.onClear,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                HugeIcons.strokeRoundedCancel01,
                size: 16,
                color: widget.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
