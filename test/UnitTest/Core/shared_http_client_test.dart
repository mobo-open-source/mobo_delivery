import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:odoo_delivery_app/core/security/self_signed.dart';

void main() {
  group('SharedHttpClient', () {
    test('survives close() so one caller cannot break every other', () async {
      var requests = 0;
      final client = SharedHttpClient(
        MockClient((request) async {
          requests++;
          return http.Response('{"result": true}', 200);
        }),
        const Duration(seconds: 5),
      );

      await client.get(Uri.parse('https://example.invalid/web/dataset/call_kw'));
      expect(requests, 1);

      // An OdooClient being discarded closes the http client it was handed.
      // Because that client is shared process-wide, this must not disable it.
      client.close();

      await client.get(Uri.parse('https://example.invalid/web/dataset/call_kw'));
      expect(
        requests,
        2,
        reason: 'the shared transport must still serve requests after close()',
      );
    });

    test('repeated close() is harmless', () async {
      final client = SharedHttpClient(
        MockClient((request) async => http.Response('ok', 200)),
        const Duration(seconds: 5),
      );

      client.close();
      client.close();

      final response = await client.get(Uri.parse('https://example.invalid/'));
      expect(response.statusCode, 200);
    });

    test('a request that never completes fails with a timeout', () async {
      final client = SharedHttpClient(
        MockClient((request) => Completer<http.Response>().future),
        const Duration(milliseconds: 100),
      );

      await expectLater(
        client.get(Uri.parse('https://example.invalid/')),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
