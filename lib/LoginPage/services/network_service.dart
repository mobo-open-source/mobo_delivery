import 'dart:convert';
import 'dart:io';

/// What a server said when asked for its database list.
///
/// The distinction that matters is whether an Odoo server answered at all.
/// A mistyped address fails at the transport or returns something that is not
/// JSON-RPC; only Odoo replies to `/web/database/list` with a well-formed
/// envelope, so an `error` in that envelope is positive proof of a real Odoo
/// server that is declining to list — which is the one case where asking the
/// user to type a database name is reasonable.
class DatabaseListResult {
  const DatabaseListResult._(this.databases, this.listingDisabled);

  /// The server returned its databases.
  const DatabaseListResult.databases(List<String> databases)
    : this._(databases, false);

  /// A real Odoo server answered and refused to list its databases, which is
  /// how it replies when `list_db = False`.
  const DatabaseListResult.listingDisabled() : this._(const [], true);

  final List<String> databases;

  /// True only when Odoo itself declined. Never true for an unreachable host,
  /// a non-Odoo server, or a malformed response.
  final bool listingDisabled;
}

/// Raised when the address could not be confirmed as an Odoo server.
///
/// Covers the mistyped-URL cases — DNS failure, refused connection, timeout,
/// TLS failure, and anything that answers without speaking JSON-RPC.
class NotAnOdooServerException implements Exception {
  const NotAnOdooServerException(this.reason);

  final Object reason;

  @override
  String toString() => 'Error fetching database list: $reason';
}

/// Handles network communication with the Odoo server.
class NetworkService {
  /// Upper bound on the whole database-list request.
  static const Duration _databaseListTimeout = Duration(seconds: 20);

  /// Asks [url] for its database list.
  ///
  /// Throws [NotAnOdooServerException] when the address could not be
  /// confirmed as Odoo, so the caller can tell a typo apart from a server
  /// that simply will not list.
  Future<DatabaseListResult> fetchDatabaseList(String url) async {
    String normalizedUrl = url.trim();
    if (!normalizedUrl.startsWith('http://') &&
        !normalizedUrl.startsWith('https://')) {
      normalizedUrl = 'https://$normalizedUrl';
    }
    if (normalizedUrl.endsWith('/')) {
      normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 1);
    }

    String responseBody;
    try {
      final HttpClient httpClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12)
        ..idleTimeout = const Duration(seconds: 10)
        ..maxConnectionsPerHost = 5
        ..badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;

      // Bounded end to end. `connectionTimeout` only limits the TCP connect:
      // waiting for the response headers and reading the body had no limit at
      // all, so a server that accepted the connection and then stalled left
      // this screen on its spinner indefinitely.
      responseBody = await () async {
        final request = await httpClient.postUrl(
          Uri.parse('$normalizedUrl/web/database/list'),
        );

        request.headers.set('Content-Type', 'application/json');
        request.write(
          jsonEncode({
            'jsonrpc': '2.0',
            'method': 'call',
            'params': {},
            'id': 1,
          }),
        );

        final response = await request.close();
        return response.transform(utf8.decoder).join();
      }().timeout(_databaseListTimeout).whenComplete(httpClient.close);
    } catch (e) {
      throw NotAnOdooServerException(e);
    }

    dynamic jsonResponse;
    try {
      jsonResponse = jsonDecode(responseBody);
    } catch (e) {
      // HTML, a proxy error page, anything that is not JSON-RPC.
      throw NotAnOdooServerException(e);
    }

    if (jsonResponse is! Map) {
      throw const NotAnOdooServerException('Unexpected response format');
    }

    if (jsonResponse.containsKey('error')) {
      // A JSON-RPC error here is Odoo answering. Nothing else replies to this
      // endpoint in this shape, so this is the genuine `list_db = False` case.
      return const DatabaseListResult.listingDisabled();
    }

    final dynamic result = jsonResponse['result'];
    if (result is List) {
      return DatabaseListResult.databases(
        result.map((db) => db.toString()).toList(),
      );
    }

    // A JSON-RPC envelope with neither a list nor an error is still Odoo
    // answering, just with nothing useful.
    return const DatabaseListResult.listingDisabled();
  }
}
