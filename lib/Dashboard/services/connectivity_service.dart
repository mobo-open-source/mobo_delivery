import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Service responsible for monitoring and providing network connectivity status.
///
/// Implements a singleton pattern to provide a single connectivity listener
/// across the entire application.
///
/// Features:
/// • Real-time connectivity monitoring
/// • One-time connectivity check support
/// • ChangeNotifier integration for UI updates
/// • Initialization safety to prevent duplicate listeners
///
/// Uses `connectivity_plus` package internally.
class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService instance = ConnectivityService._internal();
  factory ConnectivityService() => instance;

  /// Private internal constructor for singleton instance.
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isConnected = true;
  bool _isInitialized = false;

  bool get isConnected => _isConnected;
  bool get isInitialized => _isInitialized;

  /// Initializes connectivity monitoring.
  ///
  /// Ensures:
  /// • Service is initialized only once
  /// • Current connectivity state is checked immediately
  /// • Connectivity stream listener is registered
  ///
  /// Notifies listeners once initialization is complete.
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _checkConnectivity();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        _updateConnectivityStatus(results);
      },
    );
    _isInitialized = true;
    notifyListeners();
  }

  /// Performs initial connectivity check.
  ///
  /// Updates current connectivity state and notifies listeners
  /// if connection status changes.
  ///
  /// Falls back to disconnected state if an exception occurs.
  Future<void> _checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateConnectivityStatus(results);
    } catch (e) {
      _isConnected = false;
      notifyListeners();
    }
  }

  /// Updates connectivity state based on connectivity results.
  ///
  /// Compares previous and new connectivity states and notifies
  /// listeners only if the connection status has changed.
  ///
  /// [results] List of connectivity results from connectivity_plus.
  void _updateConnectivityStatus(List<ConnectivityResult> results) {
    final wasConnected = _isConnected;
    _isConnected = !results.contains(ConnectivityResult.none);

    if (wasConnected != _isConnected) {
      notifyListeners();
    }
  }

  /// Performs a one-time connectivity check without subscribing to stream updates.
  ///
  /// Returns:
  /// • true → If device is connected to network
  /// • false → If device is offline or error occurs
  Future<bool> checkConnectivityOnce() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return !results.contains(ConnectivityResult.none);
    } catch (e) {
      return false;
    }
  }

  /// Cancels connectivity subscription and releases resources.
  ///
  /// Called automatically when service is disposed.
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}