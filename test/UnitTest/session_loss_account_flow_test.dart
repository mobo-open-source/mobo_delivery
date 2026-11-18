import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_delivery_app/core/company/session/company_session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A screen left mounted under the add-account flow (Configuration, the
/// pickings list) must not be able to sign the user out from underneath it.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'isLoggedIn': true});
  });

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        routes: {'/login': (_) => const Text('login screen')},
        home: Builder(
          builder: (context) {
            captured = context;
            return const Text('screen underneath');
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets('session loss is ignored while the add-account flow is open', (
    tester,
  ) async {
    final context = await pumpHost(tester);

    CompanySessionManager.beginAccountFlow();
    addTearDown(CompanySessionManager.endAccountFlow);

    await tester.runAsync(() => CompanySessionManager.onSessionLost(context));
    await tester.pump();

    expect(find.text('Logging out...'), findsNothing);
    expect(find.text('screen underneath'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('isLoggedIn'), isTrue);
  });

  testWidgets('session loss still logs out once the flow has closed', (
    tester,
  ) async {
    final context = await pumpHost(tester);

    CompanySessionManager.beginAccountFlow();
    CompanySessionManager.endAccountFlow();

    // logout() waits on real timers and storage, so it runs on the real clock
    // from start to finish; starting it under the fake test clock and waiting
    // on the real one never lets its delays fire.
    await tester.runAsync(() => CompanySessionManager.onSessionLost(context));
    await tester.pumpAndSettle();
    expect(find.text('login screen'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('isLoggedIn'), isFalse);
  });
}
