import 'dart:convert';
import 'dart:io';

/// Handles network communication with server.
///
/// Currently supports:
/// - Fetching database list from Odoo server
class NetworkService {
  /// Fetches database list from given server URL.
  ///
  /// Steps:
  /// - Normalizes URL (adds https if missing)
  /// - Removes trailing slash
  /// - Sends JSON RPC request to `/web/database/list`
  /// - Returns list of database names
  ///
  /// Returns an empty list when the server answers with a JSON-RPC error,
  /// which is how Odoo replies when database listing is disabled
  /// (`list_db = False`). Callers fall back to manual database entry.
  ///
  /// Throws:
  /// - Exception if the network request fails or the response isn't JSON
  Future<List<String>> fetchDatabaseList(String url) async {
    try {
      String normalizedUrl = url.trim();
      if (!normalizedUrl.startsWith('http://') &&
          !normalizedUrl.startsWith('https://')) {
        normalizedUrl = 'https://$normalizedUrl';
      }
      if (normalizedUrl.endsWith('/')) {
        normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 1);
      }

      final HttpClient httpClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12)
        ..idleTimeout = const Duration(seconds: 10)
        ..maxConnectionsPerHost = 5
        ..badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;

      final request = await httpClient.postUrl(
        Uri.parse('$normalizedUrl/web/database/list'),
      );

      request.headers.set('Content-Type', 'application/json');
      request.write(
        jsonEncode({'jsonrpc': '2.0', 'method': 'call', 'params': {}, 'id': 1}),
      );

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      httpClient.close();

      final dynamic jsonResponse = jsonDecode(responseBody);
      if (jsonResponse is! Map) return [];
      if (jsonResponse.containsKey('error')) return [];

      final dynamic result = jsonResponse['result'];
      if (result is List) {
        return result.map((db) => db.toString()).toList();
      }
      return [];
    } catch (e) {
      throw Exception('Error fetching database list: $e');
    }
  }
}
