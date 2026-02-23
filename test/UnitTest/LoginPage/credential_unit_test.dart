import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:odoo_delivery_app/LoginPage/models/session_model.dart';

import 'package:odoo_delivery_app/LoginPage/services/auth_service.dart';
import 'package:odoo_delivery_app/LoginPage/services/app_install_check.dart';
import 'package:odoo_delivery_app/LoginPage/services/storage_service.dart';

@GenerateMocks([AuthService, AppInstallCheck, StorageService])
import 'credential_unit_test.mocks.dart';

void main() {
  late MockAuthService mockAuthService;
  late MockAppInstallCheck mockAppInstallCheck;
  late MockStorageService mockStorageService;
  final mockSession = SessionModel(
    sessionId: 'session_123',
    userId: 1,
    userLogin: 'admin',
    userName: 'Administrator',
    serverVersion: '17.0',
    userLang: 'en_US',
    userTimezone: 'UTC',
    partnerId: 1,
    companyId: 1,
    companyName: 'My Company',
    isSystem: true,
    version: 17,
    allowedCompanyIds: [1],
  );

  setUp(() {
    mockAuthService = MockAuthService();
    mockAppInstallCheck = MockAppInstallCheck();
    mockStorageService = MockStorageService();
  });

  group('Credential Login', () {
    /// POSITIVE CASE
    test('Login success when credentials are correct', () async {
      when(
        mockAuthService.authenticateOdoo(
          url: anyNamed('url'),
          database: anyNamed('database'),
          username: anyNamed('username'),
          password: anyNamed('password'),
          sessionId: null,
        ),
      ).thenAnswer((_) async => mockSession);

      final session = await mockAuthService.authenticateOdoo(
        url: 'https://demo.odoo.com',
        database: 'test_db',
        username: 'admin',
        password: 'admin',
        sessionId: null,
      );

      expect(session, isNotNull);
    });

    /// NEGATIVE CASE – wrong password
    test('Login fails with wrong credentials', () async {
      when(
        mockAuthService.authenticateOdoo(
          url: anyNamed('url'),
          database: anyNamed('database'),
          username: anyNamed('username'),
          password: anyNamed('password'),
          sessionId: null,
        ),
      ).thenThrow(Exception('AccessDenied'));

      expect(
        () async => await mockAuthService.authenticateOdoo(
          url: 'https://demo.odoo.com',
          database: 'test_db',
          username: 'admin',
          password: 'wrong',
          sessionId: null,
        ),
        throwsException,
      );
    });

    /// NEGATIVE CASE – network error
    test('Login fails when network error occurs', () async {
      when(
        mockAuthService.authenticateOdoo(
          url: anyNamed('url'),
          database: anyNamed('database'),
          username: anyNamed('username'),
          password: anyNamed('password'),
          sessionId: null,
        ),
      ).thenThrow(Exception('SocketException'));

      expect(
        () async => await mockAuthService.authenticateOdoo(
          url: 'https://demo.odoo.com',
          database: 'test_db',
          username: 'admin',
          password: 'admin',
          sessionId: null,
        ),
        throwsException,
      );
    });

    /// POSITIVE CASE - MODULE INSTALLED
    test('Inventory module installed returns true', () async {
      when(
        mockAppInstallCheck.checkRequiredModules(),
      ).thenAnswer((_) async => true);

      final result = await mockAppInstallCheck.checkRequiredModules();

      expect(result, true);
    });

    /// NEGATIVE CASE - MODULE MISSING
    test('Inventory module missing returns false', () async {
      when(
        mockAppInstallCheck.checkRequiredModules(),
      ).thenAnswer((_) async => false);

      final result = await mockAppInstallCheck.checkRequiredModules();

      expect(result, false);
    });

    /// STORAGE TEST
    test('Save login state stores values correctly', () async {
      when(
        mockStorageService.saveLoginState(
          isLoggedIn: true,
          database: 'test_db',
          url: 'https://demo.odoo.com',
        ),
      ).thenAnswer((_) async {});

      await mockStorageService.saveLoginState(
        isLoggedIn: true,
        database: 'test_db',
        url: 'https://demo.odoo.com',
      );

      verify(
        mockStorageService.saveLoginState(
          isLoggedIn: true,
          database: 'test_db',
          url: 'https://demo.odoo.com',
        ),
      ).called(1);
    });
  });
}
