import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_delivery_app/LoginPage/services/network_service.dart';

/// HTTP OVERRIDES
class MockHttpOverrides extends HttpOverrides {
  final int statusCode;
  final dynamic responseBody;
  final bool throwSocketError;

  MockHttpOverrides({
    this.statusCode = 200,
    this.responseBody,
    this.throwSocketError = false,
  });

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    if (throwSocketError) {
      throw const SocketException('No Internet');
    }
    return MockHttpClient(statusCode: statusCode, responseBody: responseBody);
  }
}

/// MOCK HTTP CLIENT
class MockHttpClient implements HttpClient {
  final int statusCode;
  final dynamic responseBody;

  MockHttpClient({required this.statusCode, required this.responseBody});

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    return MockHttpClientRequest(
      statusCode: statusCode,
      responseBody: responseBody,
    );
  }

  @override
  void close({bool force = false}) {}

  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout = const Duration(seconds: 10);

  @override
  int? maxConnectionsPerHost;

  @override
  bool Function(X509Certificate cert, String host, int port)?
  badCertificateCallback;

  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// MOCK REQUEST
class MockHttpClientRequest implements HttpClientRequest {
  final int statusCode;
  final dynamic responseBody;

  MockHttpClientRequest({required this.statusCode, required this.responseBody});

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  void write(Object? obj) {}

  @override
  Future<HttpClientResponse> close() async {
    return MockHttpClientResponse(
      statusCode: statusCode,
      responseBody: responseBody,
    );
  }

  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// MOCK RESPONSE
class MockHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  final int statusCode;
  final dynamic responseBody;

  MockHttpClientResponse({
    required this.statusCode,
    required this.responseBody,
  });

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final body = responseBody is String
        ? responseBody
        : jsonEncode(responseBody ?? {});
    final bytes = utf8.encode(body);

    return Stream<List<int>>.fromIterable([bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// FAKE HEADERS
class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _headers = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers[name] = [value.toString()];
  }

  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('NetworkService.fetchDatabaseList', () {
    /// POSITIVE CASE
    test('returns database list when server responds with result', () async {
      await HttpOverrides.runZoned(
        () async {
          final service = NetworkService();

          final result = await service.fetchDatabaseList(
            'https://demo.odoo.com',
          );

          expect(result.databases, equals(['test_db']));
          expect(result.listingDisabled, isFalse);
        },
        createHttpClient: (_) {
          return MockHttpClient(
            statusCode: 200,
            responseBody: {
              "jsonrpc": "2.0",
              "id": 1,
              "result": ["test_db"],
            },
          );
        },
      );
    });

    /// EMPTY DB LIST
    test('an empty result is Odoo answering, not a bad address', () async {
      await HttpOverrides.runZoned(
        () async {
          final service = NetworkService();

          final result = await service.fetchDatabaseList(
            'https://demo.odoo.com',
          );

          expect(result.databases, isEmpty);
          expect(result.listingDisabled, isFalse);
        },
        createHttpClient: (_) {
          return MockHttpClient(
            statusCode: 200,
            responseBody: {"jsonrpc": "2.0", "id": 1, "result": []},
          );
        },
      );
    });

    /// A JSON-RPC error is Odoo declining to list, which is the one case
    /// where asking the user to type a database name is reasonable.
    test(
      'a JSON-RPC error marks listing as disabled, not a bad address',
      () async {
        await HttpOverrides.runZoned(
          () async {
            final service = NetworkService();

            final result = await service.fetchDatabaseList(
              'https://demo.odoo.com',
            );

            expect(result.databases, isEmpty);
            expect(result.listingDisabled, isTrue);
          },
          createHttpClient: (_) {
            return MockHttpClient(
              statusCode: 500,
              responseBody: {"error": "Internal Server Error"},
            );
          },
        );
      },
    );

    /// NEGATIVE CASE - INVALID URL
    test(
      'an unusable address is not mistaken for a server that declines',
      () async {
        final service = NetworkService();

        await expectLater(
          () => service.fetchDatabaseList('%%%invalid-url%%%'),
          throwsA(isA<NotAnOdooServerException>()),
        );
      },
    );

    /// NEGATIVE CASE - MALFORMED JSON
    test('throws exception when response is not valid JSON', () async {
      await HttpOverrides.runZoned(
        () async {
          final service = NetworkService();

          // HTML is not JSON-RPC, so nothing confirms this is Odoo.
          await expectLater(
            () => service.fetchDatabaseList('http://fake-server'),
            throwsA(isA<NotAnOdooServerException>()),
          );
        },
        createHttpClient: (_) {
          return MockHttpClient(
            statusCode: 200,
            responseBody: "<html>500 error</html>",
          );
        },
      );
    });

    /// NEGATIVE CASE - NETWORK FAILURE
    test('throws exception on network failure', () async {
      await HttpOverrides.runZoned(
        () async {
          final service = NetworkService();

          await expectLater(
            () => service.fetchDatabaseList('http://fake-server'),
            throwsA(isA<NotAnOdooServerException>()),
          );
        },
        createHttpClient: (_) {
          throw const SocketException('No Internet');
        },
      );
    });
  });
}
