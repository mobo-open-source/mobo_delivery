import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

/// Service that checks whether the device has internet access **and** can reach the Odoo server.
///
/// Combines:
///   - General network connectivity check via `connectivity_plus`
///   - Active server ping (GET request to `/web` endpoint with timeout)
///
/// Returns `true` only if both conditions are satisfied:
///   - Device has some form of network connection (Wi-Fi/mobile)
///   - Odoo server responds with HTTP 200 within 5 seconds
///
/// Used throughout the app to determine offline mode and enable/disable sync features.
class ConnectivityService {
  final String url;

  ConnectivityService(this.url);

  /// Checks if the device is connected to the internet **and** can reach the Odoo server.
  ///
  /// Flow:
  ///   1. Quick connectivity check via `connectivity_plus`
  ///   2. If connected → attempts a lightweight GET to `$url/web`
  ///   3. Returns `true` only on successful 200 response
  ///   4. Returns `false` on timeout, exception, or non-200 status
  ///
  /// Timeout is set to 5 seconds to avoid long blocking calls.
  /// Throws no exceptions — always returns boolean (fail-safe).
  Future<bool> isConnectedToOdoo() async {
    var connectivity = await Connectivity().checkConnectivity();
    if (connectivity != ConnectivityResult.none) return true;

    try {
      final response = await http.get(Uri.parse('$url/web'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
