import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_delivery_app/Dashboard/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The account switcher paints each row from the avatar cached in the stored
/// account entry. Changing a picture has to write it there, or the account the
/// user just left keeps showing its old photo after switching away.
void main() {
  const accountsKey = 'loggedInAccounts';

  /// Two accounts on the same server, as the switcher stores them.
  /// `saveAccount` normalises the URL it writes, so these carry the
  /// normalised form.
  List<Map<String, dynamic>> seedAccounts() => [
        {
          'userId': 2,
          'userLogin': 'alice',
          'url': 'https://erp.example.com',
          'database': 'prod',
          'image': 'OLD_ALICE',
        },
        {
          'userId': 7,
          'userLogin': 'bob',
          'url': 'https://erp.example.com',
          'database': 'prod',
          'image': 'OLD_BOB',
        },
      ];

  Future<List<Map<String, dynamic>>> readBack() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(accountsKey)!;
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({
      accountsKey: jsonEncode(seedAccounts()),
    });
  });

  group('updateAccountImage', () {
    test('writes the new avatar onto the matching account', () async {
      final ok = await DashboardStorageService().updateAccountImage(
        userId: 2,
        url: 'https://erp.example.com',
        database: 'prod',
        image: 'NEW_ALICE',
      );

      expect(ok, isTrue);
      final accounts = await readBack();
      expect(accounts.firstWhere((a) => a['userId'] == 2)['image'],
          'NEW_ALICE');
    });

    test('leaves the other account alone', () async {
      await DashboardStorageService().updateAccountImage(
        userId: 2,
        url: 'https://erp.example.com',
        database: 'prod',
        image: 'NEW_ALICE',
      );

      final accounts = await readBack();
      expect(
          accounts.firstWhere((a) => a['userId'] == 7)['image'], 'OLD_BOB');
    });

    test('matches when the session URL is not in normalised form', () async {
      /// The session keeps whatever the user typed; `saveAccount` normalised
      /// what it stored. Comparing them raw missed the account entirely,
      /// which silently skipped the update.
      for (final typed in [
        'erp.example.com',
        'https://erp.example.com/',
        '  https://erp.example.com  ',
      ]) {
        SharedPreferences.setMockInitialValues({
          accountsKey: jsonEncode(seedAccounts()),
        });

        final ok = await DashboardStorageService().updateAccountImage(
          userId: 2,
          url: typed,
          database: 'prod',
          image: 'NEW_ALICE',
        );

        expect(ok, isTrue, reason: 'should match for "$typed"');
        final accounts = await readBack();
        expect(accounts.firstWhere((a) => a['userId'] == 2)['image'],
            'NEW_ALICE',
            reason: 'should have updated for "$typed"');
      }
    });

    test('matches when the id arrives as a string', () async {
      final ok = await DashboardStorageService().updateAccountImage(
        userId: '2',
        url: 'https://erp.example.com',
        database: 'prod',
        image: 'NEW_ALICE',
      );
      expect(ok, isTrue);
    });

    test('does not match a different database on the same server', () async {
      final ok = await DashboardStorageService().updateAccountImage(
        userId: 2,
        url: 'https://erp.example.com',
        database: 'staging',
        image: 'NEW_ALICE',
      );

      expect(ok, isFalse);
      final accounts = await readBack();
      expect(accounts.firstWhere((a) => a['userId'] == 2)['image'],
          'OLD_ALICE');
    });

    test('does not match a different user on the same server', () async {
      final ok = await DashboardStorageService().updateAccountImage(
        userId: 99,
        url: 'https://erp.example.com',
        database: 'prod',
        image: 'X',
      );
      expect(ok, isFalse);
    });

    test('a cleared picture is stored as empty, not left stale', () async {
      await DashboardStorageService().updateAccountImage(
        userId: 2,
        url: 'https://erp.example.com',
        database: 'prod',
        image: null,
      );

      final accounts = await readBack();
      expect(accounts.firstWhere((a) => a['userId'] == 2)['image'], '');
    });
  });
}
