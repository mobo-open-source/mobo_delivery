import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Maximum time to wait for a server response before failing with a
/// [TimeoutException]. Generous, because some Odoo writes are heavy, but
/// bounded so a screen can never wait forever.
const Duration kRequestTimeout = Duration(seconds: 60);

/// Maximum time to wait while establishing the TCP connection.
const Duration kConnectionTimeout = Duration(seconds: 30);

/// Enforces an overall timeout on every request, headers *and* body.
///
/// `connectionTimeout` alone only limits the TCP connect, and timing out the
/// send only covers the response headers — a server that answers and then
/// stalls part-way through the body leaves the read hanging with no limit at
/// all, which is how a screen ends up on its loading state indefinitely. The
/// body limit is a gap-between-chunks one, so a slow but progressing download
/// still completes.
class SharedHttpClient extends http.BaseClient {
  SharedHttpClient(this._inner, this._timeout);

  final http.Client _inner;
  final Duration _timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request).timeout(_timeout);
    return http.StreamedResponse(
      response.stream.timeout(_timeout),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  /// Deliberately does nothing.
  ///
  /// [ioClient] is a single process-wide transport shared by every
  /// `OdooClient` the app builds, and `OdooClient.close()` closes whatever
  /// http client it was handed. So one `OdooClient` being discarded — which
  /// happens routinely on logout, on a session refresh and on every account
  /// switch — used to close the transport *every other* client in the app was
  /// still using. From that moment on, every request in the process failed
  /// with `ClientException: HTTP request failed. Client is already closed.`,
  /// and nothing short of restarting the app could recover it.
  ///
  /// That failure was especially hard to read: it arrives at the call site
  /// looking like a transport fault, so the app blamed the network while the
  /// server was healthy the whole time. The shared transport's lifetime is
  /// the process's; individual clients releasing their reference must not
  /// shorten it.
  @override
  void close() {}
}

/// Creates an [HttpClient] that accepts self-signed certificates.
///
/// On-premise Odoo servers are routinely deployed behind one, and refusing
/// here would lock those users out entirely.
HttpClient _getHttpClient() {
  final client = HttpClient()
    ..connectionTimeout = kConnectionTimeout
    ..badCertificateCallback = (X509Certificate cert, String host, int port) =>
        true;
  return client;
}

/// Shared HTTP client: accepts self-signed certificates and bounds every
/// request. Passed to every `OdooClient` so no RPC can hang indefinitely.
final http.BaseClient ioClient = SharedHttpClient(
  IOClient(_getHttpClient()),
  kRequestTimeout,
);
