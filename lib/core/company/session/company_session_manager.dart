import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../LoginPage/models/session_model.dart';
import '../../../LoginPage/services/auth_service.dart';
import '../../../LoginPage/services/storage_service.dart';
import '../../security/secure_storage_service.dart';
import '../services/connectivity_service.dart';
import '../../../shared/utils/server_url_utils.dart';
import '../../../shared/widgets/loaders/loading_widget.dart';
import '../../../NavBars/Pickings/PickingFormPage/services/hive_service.dart';

/// The session could not be recovered: re-authentication failed, or the call
/// still failed as an auth error after a successful one.
///
/// This is the *only* condition that should sign a user out. A single request
/// seeing a session error is not evidence of anything — the first request to
/// hit one triggers a re-login, and re-logging in rotates the Odoo session id,
/// so every other request already in flight fails exactly the same way. Acting
/// on that directly is what logged people out mid-use.
class SessionUnrecoverableException implements Exception {
  final String message;

  const SessionUnrecoverableException([
    this.message = 'Your session has expired. Please sign in again.',
  ]);

  @override
  String toString() => message;
}

/// Central manager for Odoo session lifecycle and RPC safety handling.
///
/// Handles:
/// - Login & session persistence
/// - Session caching & refresh
/// - Odoo client lifecycle
/// - Company context injection
/// - Safe RPC calls with auto re-authentication
class CompanySessionManager {
  static OdooClient? _client;
  static SessionModel? _cachedSession;

  /// Holds the in-flight refresh future so concurrent callers can await the
  /// actual result instead of falling back to the stale `isLoggedIn` flag.
  static Future<bool>? _refreshFuture;

  /// Last successful authentication time.
  static DateTime? _lastAuthTime;

  /// Bumped every time the session is successfully re-authenticated.
  ///
  /// Re-authenticating rotates the Odoo session id, so every request already
  /// in flight fails as session-expired. Without a way to tell "the session
  /// died" from "somebody just replaced it", each of those failures would
  /// start a re-authentication of its own, rotating the session again and
  /// stranding the next batch — a loop that ends in a spurious logout.
  /// Comparing this counter tells a caller its failure was already answered,
  /// so it retries on the new session instead of rotating it again.
  static int _sessionGeneration = 0;

  /// Duration for which cached client/session is considered valid.
  static const Duration _sessionCacheValidDuration = Duration(minutes: 5);

  /// Whether the current company selection has been checked against the
  /// companies this user actually has, during this run.
  ///
  /// The persisted selection cannot be trusted on its own: `companyId` falls
  /// back to a hardcoded `1` when nothing was stored, and
  /// `allowed_company_ids` is only ever written when non-empty, so a list
  /// belonging to a previously signed-in account survives indefinitely.
  /// Sending an unvalidated selection makes Odoo reject *every* request with
  /// "Access to unauthorized or invalid companies."
  ///
  /// So nothing is sent until [updateCompanySelection] reports a selection
  /// that `CompanyProvider` has confirmed against the server. Odoo then
  /// falls back to the user's own companies, which are valid by definition.
  static bool _companyContextValidated = false;

  /// Optional listener for session updates (UI refresh / state sync).
  static Function(SessionModel)? _onSessionUpdated;

  /// Register listener to be notified when session changes.
  static void registerSessionListener(Function(SessionModel) callback) {
    _onSessionUpdated = callback;
  }

  /// Detects whether an error is authentication/session related.
  static bool _isAuthError(Object e) {
    final errorStr = e.toString().toLowerCase();

    if (_isInvalidCompanyContext(e)) return false;

    return e is OdooSessionExpiredException ||
        errorStr.contains('401') ||
        errorStr.contains('unauthorized') ||
        errorStr.contains('access denied') ||
        errorStr.contains('invalid session') ||
        errorStr.contains('session expired') ||
        errorStr.contains('authentication') ||
        errorStr.contains('forbidden') ||
        errorStr.contains('403') ||
        e is FormatException ||
        errorStr.contains('formatexception') ||
        errorStr.contains('unexpected character') ||
        errorStr.contains('<html') ||
        errorStr.contains('<!doctype html');
  }

  /// Forces reload of session from SharedPreferences.
  static Future<void> forceRefreshFromPrefs() async {
    _cachedSession = null;
    await getCurrentSession();
  }

  /// Returns cached session or loads from local storage.
  static Future<SessionModel?> getCurrentSession() async {
    if (_cachedSession != null) return _cachedSession;

    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    if (!isLoggedIn) return null;

    final String? sessionId = prefs.getString('sessionId');
    final int? userId = prefs.getInt('userId');
    final String? url = prefs.getString('url');

    if (sessionId == null ||
        sessionId.isEmpty ||
        userId == null ||
        url == null ||
        url.isEmpty) {
      return null;
    }

    /// Convert stored allowed company ids (string list) to int list.
    final List<String> allowedRaw =
        prefs.getStringList('allowed_company_ids') ?? [];
    final List<int> allowedCompanyIds = allowedRaw
        .map((e) => int.tryParse(e) ?? 0)
        .where((e) => e > 0)
        .toList();

    final session = SessionModel(
      sessionId: sessionId,
      userName: prefs.getString('userName'),
      userLogin: prefs.getString('userLogin'),
      userId: userId,
      serverVersion: prefs.getString('serverVersion'),
      userLang: prefs.getString('userLang'),
      partnerId: prefs.getInt('partnerId'),
      userTimezone: prefs.getString('userTimezone'),
      companyId: prefs.getInt('companyId'),
      companyName: prefs.getString('company_name'),
      isSystem: prefs.getBool('isSystem') ?? false,
      isPortal: prefs.getBool('isPortal') ?? false,
      version: prefs.getInt('version'),
      allowedCompanyIds: allowedCompanyIds,
    );

    _cachedSession = session;

    /// Update connectivity monitoring with current server.
    ConnectivityService.instance.setCurrentServerUrl(url);
    return session;
  }

  /// Returns whether login state exists locally.
  static Future<bool> isSessionValid() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }

  /// Notifies listeners after session creation/update.
  static Future<void> notifySessionCreated() async {
    await forceRefreshFromPrefs();
    final session = await getCurrentSession();
    if (session != null) {
      _onSessionUpdated?.call(session);
    }
  }

  /// Initializes session from browser session cookie.
  static Future<void> loginFromBrowserSession({
    required String sessionId,
    required String url,
    required String database,
    required Map<String, dynamic> sessionInfo,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    /// Persist session basics.
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('url', url);
    await prefs.setString('selectedDatabase', database);
    await prefs.setString('database', database);
    await prefs.setString('sessionId', sessionId);

    /// Persist user/session metadata.
    await prefs.setInt('userId', sessionInfo['uid']);
    await prefs.setString('userName', sessionInfo['name']);
    await prefs.setString('userLogin', sessionInfo['login']);
    await prefs.setString(
      'serverVersion',
      sessionInfo['server_version'].toString(),
    );
    await prefs.setString(
      'userLang',
      sessionInfo['user_context']['lang'] ?? 'en_US',
    );
    await prefs.setString(
      'userTimezone',
      sessionInfo['user_context']['tz'] ?? 'UTC',
    );
    await prefs.setInt('partnerId', sessionInfo['partner_id']);
    await prefs.setInt('companyId', sessionInfo['company_id']);
    await prefs.setString('company_name', sessionInfo['company_name']);
    await prefs.setBool('isSystem', sessionInfo['is_system'] ?? false);

    /// Build Odoo session object.
    final odooSession = OdooSession(
      id: sessionId,
      dbName: database,
      userId: sessionInfo['uid'],
      partnerId: sessionInfo['partner_id'],
      userLogin: sessionInfo['login'],
      userName: sessionInfo['name'],
      userLang: sessionInfo['user_context']['lang'] ?? 'en_US',
      userTz: sessionInfo['user_context']['tz'] ?? 'UTC',
      isSystem: sessionInfo['is_system'] ?? false,
      serverVersion: sessionInfo['server_version'].toString(),
      companyId: sessionInfo['company_id'],
      allowedCompanies: [],
    );

    /// Reset old client before creating new one.
    _client?.close();
    _client = OdooClient(url, sessionId: odooSession);

    /// Cache session locally.
    _cachedSession = SessionModel(
      sessionId: sessionId,
      userId: sessionInfo['uid'],
      userName: sessionInfo['name'],
      userLogin: sessionInfo['login'],
      serverVersion: odooSession.serverVersion,
      userLang: odooSession.userLang,
      partnerId: odooSession.partnerId,
      userTimezone: odooSession.userTz,
      companyId: odooSession.companyId,
      companyName: sessionInfo['company_name'],
      isSystem: odooSession.isSystem,
    );

    _lastAuthTime = DateTime.now();
    _onSessionUpdated?.call(_cachedSession!);
  }

  /// Authenticates user and creates new session.
  static Future<bool> loginAndSaveSession({
    required String serverUrl,
    required String database,
    required String userLogin,
    required String password,
    session_Id,
    bool autoLoadCompanies = true,
  }) async {
    final normalizedUrl = normalizeServerUrl(serverUrl);

    final authService = AuthService();
    final SessionModel? sessionModel = await authService.authenticateOdoo(
      url: normalizedUrl,
      database: database,
      username: userLogin,
      password: password,
      sessionId: session_Id,
    );

    if (sessionModel == null) return false;

    /// Persist password securely for auto-refresh
    await SecureStorageService().savePassword(
      url: normalizedUrl,
      database: database,
      username: userLogin,
      password: password,
    );

    /// Persist session & login state.
    final storage = StorageService();
    await storage.saveSession(sessionModel);
    await storage.saveLoginState(
      isLoggedIn: true,
      database: database,
      url: normalizedUrl,
    );

    /// Recreate Odoo client using stored values.
    final prefs = await SharedPreferences.getInstance();
    final db =
        prefs.getString('selectedDatabase') ??
        prefs.getString('database') ??
        '';
    final sessionId = prefs.getString('sessionId') ?? '';
    final serverVersion = prefs.getString('serverVersion') ?? '';
    final userLang = prefs.getString('userLang') ?? '';
    final allowedCompaniesStringList =
        prefs.getStringList('allowedCompanies') ?? [];

    final allowedCompanies = allowedCompaniesStringList
        .map((jsonString) => Company.fromJson(jsonDecode(jsonString)))
        .toList();
    final session = OdooSession(
      id: sessionId,
      userId: prefs.getInt('userId') ?? 0,
      partnerId: prefs.getInt('partnerId') ?? 0,
      userLogin: prefs.getString('userLogin') ?? '',
      userName: prefs.getString('userName') ?? '',
      userLang: userLang,
      userTz: '',
      isSystem: prefs.getBool('isSystem') ?? false,
      dbName: db,
      serverVersion: serverVersion,
      companyId: prefs.getInt('companyId') ?? 1,
      allowedCompanies: allowedCompanies,
    );
    _client?.close();
    _client = null;

    _client = OdooClient(normalizedUrl, sessionId: session);
    _cachedSession = sessionModel;
    _lastAuthTime = DateTime.now();

    ConnectivityService.instance.setCurrentServerUrl(normalizedUrl);
    _onSessionUpdated?.call(sessionModel);

    return true;
  }

  /// Clears cached session and client instance.
  static Future<void> clearSessionCache() async {
    _cachedSession = null;
    _client?.close();
    _client = null;
    _lastAuthTime = null;
    _refreshFuture = null;

    _companyContextValidated = false;
  }

  /// Restores session for selected company context.
  static Future<bool> restoreSession({required int companyId}) async {
    if (companyId <= 0) return false;

    final session = await getCurrentSession();
    if (session == null) return false;

    final url = (await SharedPreferences.getInstance()).getString('url') ?? '';
    if (url.isEmpty) return false;

    try {
      await ConnectivityService.instance.ensureInternetOrThrow();
      await ConnectivityService.instance.ensureServerReachable(url);

      /// Update session with new company selection.
      final updatedSession = SessionModel(
        sessionId: session.sessionId,
        userName: session.userName,
        userLogin: session.userLogin,
        userId: session.userId,
        serverVersion: session.serverVersion,
        userLang: session.userLang,
        partnerId: session.partnerId,
        userTimezone: session.userTimezone,
        companyId: companyId,
        companyName: session.companyName,
        isSystem: session.isSystem,
        version: session.version,
      );

      final prefs = await SharedPreferences.getInstance();
      final db =
          prefs.getString('selectedDatabase') ??
          prefs.getString('database') ??
          '';
      final sessionId = prefs.getString('sessionId') ?? '';
      final serverVersion = prefs.getString('serverVersion') ?? '';
      final userLang = prefs.getString('userLang') ?? '';
      final allowedCompaniesStringList =
          prefs.getStringList('allowedCompanies') ?? [];

      final allowedCompanies = allowedCompaniesStringList
          .map((jsonString) => Company.fromJson(jsonDecode(jsonString)))
          .toList();
      final odooSession = OdooSession(
        id: sessionId,
        userId: prefs.getInt('userId') ?? 0,
        partnerId: prefs.getInt('partnerId') ?? 0,
        userLogin: prefs.getString('userLogin') ?? '',
        userName: prefs.getString('userName') ?? '',
        userLang: userLang,
        userTz: '',
        isSystem: prefs.getBool('isSystem') ?? false,
        dbName: db,
        serverVersion: serverVersion,
        companyId: prefs.getInt('companyId') ?? 1,
        allowedCompanies: allowedCompanies,
      );

      final OdooClient client = OdooClient(url, sessionId: odooSession);
      await StorageService().saveSession(updatedSession);

      _client = client;
      _cachedSession = updatedSession;
      _lastAuthTime = DateTime.now();
      ConnectivityService.instance.setCurrentServerUrl(url);
      _onSessionUpdated?.call(updatedSession);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Updates the current session with the selected company and allowed company IDs.
  /// Saves the updated session locally and refreshes cached session data.
  /// Triggers session update listeners after successful save.
  static Future<void> updateCompanySelection({
    required int companyId,
    required List<int> allowedCompanyIds,
  }) async {
    final session = await getCurrentSession();
    if (session == null) return;

    final updated = SessionModel(
      sessionId: session.sessionId,
      userName: session.userName,
      userLogin: session.userLogin,
      userId: session.userId,
      serverVersion: session.serverVersion,
      userLang: session.userLang,
      partnerId: session.partnerId,
      userTimezone: session.userTimezone,
      companyId: companyId,
      companyName: session.companyName,
      isSystem: session.isSystem,
      version: session.version,
    );

    await StorageService().saveSession(updated);
    _cachedSession = updated;

    _companyContextValidated = true;

    _onSessionUpdated?.call(updated);
  }

  /// Fetches the list of companies the current user is allowed to access.
  /// Retrieves company IDs from user data and returns company details.
  /// Returns an empty list if session is invalid or API call fails.
  static Future<List<Map<String, dynamic>>> getAllowedCompaniesList() async {
    final client = await getClientEnsured();
    final session = await getCurrentSession();
    if (session == null || session.userId == null) return [];

    try {
      final result = await client.callKw({
        'model': 'res.users',
        'method': 'read',
        'args': [
          [session.userId],
          ['company_ids'],
        ],
        'kwargs': {},
      });

      if (result is List && result.isNotEmpty) {
        final companyIds =
            (result[0]['company_ids'] as List?)?.cast<int>() ?? [];
        if (companyIds.isEmpty) return [];

        final companies = await client.callKw({
          'model': 'res.company',
          'method': 'search_read',
          'args': [
            [
              ['id', 'in', companyIds],
            ],
          ],
          'kwargs': {
            'fields': ['id', 'name'],
          },
        });

        if (companies is List) {
          return companies.cast<Map<String, dynamic>>();
        }
      }
    } catch (_) {}

    return [];
  }

  /// Retrieves the currently selected company ID from session or local storage.
  /// Falls back to SharedPreferences if session value is unavailable.
  /// Returns null if no company selection is found.
  static Future<int?> getSelectedCompanyId() async {
    final session = await getCurrentSession();
    if (session?.companyId != null) {
      return session!.companyId;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('selected_company_id');
    } catch (_) {
      return null;
    }
  }

  /// Retrieves allowed company IDs from session or local storage.
  /// Converts stored string values to integer IDs safely.
  /// Returns an empty list if no allowed companies are found.
  static Future<List<int>> getSelectedAllowedCompanyIds() async {
    final session = await getCurrentSession();
    if (session != null && session.allowedCompanyIds.isNotEmpty) {
      return session.allowedCompanyIds;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('selected_allowed_company_ids') ?? [];
      return raw.map((e) => int.tryParse(e) ?? -1).where((e) => e > 0).toList();
    } catch (_) {
      return [];
    }
  }

  /// Executes an RPC call while injecting company context into the request.
  /// Ensures selected and allowed company IDs are included in the payload.
  /// Uses session or stored values if company data is not explicitly provided.
  static Future<dynamic> callKwWithCompany(
    Map<String, dynamic> payload, {
    int? companyId,
    List<int>? allowedCompanyIds,
  }) async {
    final map = Map<String, dynamic>.from(payload);

    Map<String, dynamic> kwargs = {};
    final rawKwargs = map['kwargs'];
    if (rawKwargs is Map) {
      kwargs = rawKwargs.map((key, value) => MapEntry(key.toString(), value));
    }

    Map<String, dynamic> ctx = {};
    final rawCtx = kwargs['context'];
    if (rawCtx is Map) {
      ctx = rawCtx.map((key, value) => MapEntry(key.toString(), value));
    }
    int? selectedCompany = companyId;
    List<int>? allowed = allowedCompanyIds;

    if (selectedCompany == null || allowed == null) {
      final session = await getCurrentSession();
      selectedCompany ??= session?.companyId ?? await getSelectedCompanyId();
      allowed ??= session?.allowedCompanyIds.isNotEmpty == true
          ? session!.allowedCompanyIds
          : await getSelectedAllowedCompanyIds();
    }

    if (selectedCompany != null && _companyContextValidated) {
      ctx['company_id'] = selectedCompany;

      final rest = {...allowed}..remove(selectedCompany);
      ctx['allowed_company_ids'] = <int>[selectedCompany, ...rest];
    }

    kwargs['context'] = ctx;
    map['kwargs'] = kwargs;

    try {
      return await callWithSession((client) => client.callKw(map));
    } catch (e) {
      if (!_isInvalidCompanyContext(e)) rethrow;

      _companyContextValidated = false;
      _cachedSession = null;
      final retryCtx = Map<String, dynamic>.from(ctx)
        ..remove('company_id')
        ..remove('allowed_company_ids');
      final retryKwargs = Map<String, dynamic>.from(kwargs)
        ..['context'] = retryCtx;
      final retryMap = Map<String, dynamic>.from(map)..['kwargs'] = retryKwargs;

      return await callWithSession((client) => client.callKw(retryMap));
    }
  }

  /// Whether Odoo rejected the request's company context rather than the
  /// request itself — raised by `env.companies` when `allowed_company_ids`
  /// names a company this user cannot access.
  static bool _isInvalidCompanyContext(Object e) {
    return e.toString().toLowerCase().contains(
      'unauthorized or invalid companies',
    );
  }

  /// Refreshes session using stored credentials from secure storage.
  ///
  /// Concurrent callers share the same in-flight refresh future so they all
  /// receive the actual outcome (not the stale `isLoggedIn` flag). This
  /// prevents a race where one caller would win the refresh while others
  /// returned `true` prematurely and then retried with a stale client.
  static Future<bool> refreshSession() async {
    if (_refreshFuture != null) {
      return _refreshFuture!;
    }
    _refreshFuture = _performRefresh();
    try {
      final refreshed = await _refreshFuture!;
      if (refreshed) _sessionGeneration++;
      return refreshed;
    } finally {
      _refreshFuture = null;
    }
  }

  /// Internal refresh implementation. Always returns a definitive result.
  static Future<bool> _performRefresh() async {
    try {
      final current = await getCurrentSession();
      if (current == null) return false;

      final prefs = await SharedPreferences.getInstance();
      final database =
          prefs.getString('selectedDatabase') ??
          prefs.getString('database') ??
          '';
      final url = prefs.getString('url') ?? '';
      final userLogin = current.userLogin ?? '';

      final secureStorage = SecureStorageService();
      final password = await secureStorage.getPassword(
        url: url,
        database: database,
        username: userLogin,
      );

      if (password == null || password.isEmpty) {
        return false;
      }

      return await loginAndSaveSession(
        serverUrl: url,
        database: database,
        userLogin: userLogin,
        password: password,
      );
    } catch (_) {
      return false;
    }
  }

  /// Initializes app session using browser-stored Odoo session details.
  /// Reads session data from local storage, cleans session ID, and creates Odoo client.
  /// Restores cached session and notifies listeners if initialization succeeds.
  static Future<void> initializeFromBrowserSession() async {
    final prefs = await SharedPreferences.getInstance();

    final String? rawSessionId = prefs.getString('odoo_session_id_raw');
    final String? url = prefs.getString('url');
    final String? database =
        prefs.getString('selectedDatabase') ?? prefs.getString('database');

    if (rawSessionId == null || rawSessionId.isEmpty) {
      return;
    }
    if (url == null || url.isEmpty) {
      return;
    }
    if (database == null || database.isEmpty) {
      return;
    }

    String cleanSessionId = rawSessionId.trim();
    if (cleanSessionId.contains(';')) {
      cleanSessionId = cleanSessionId.split(';').first.trim();
    }
    if (cleanSessionId.contains('=')) {
      cleanSessionId = cleanSessionId.split('=').last.trim();
    }

    final odooSession = OdooSession(
      id: cleanSessionId,
      dbName: database,
      userId: prefs.getInt('userId') ?? 0,
      partnerId: prefs.getInt('partnerId') ?? 0,
      userLogin: prefs.getString('userLogin') ?? '',
      userName: prefs.getString('userName') ?? '',
      userLang: prefs.getString('userLang') ?? 'en_US',
      userTz: prefs.getString('userTimezone') ?? 'UTC',
      isSystem: prefs.getBool('isSystem') ?? false,
      serverVersion: prefs.getString('serverVersion') ?? '',
      companyId: prefs.getInt('companyId') ?? 1,
      allowedCompanies: [],
    );

    _client?.close();
    _client = null;

    try {
      _client = OdooClient(url, sessionId: odooSession);

      _cachedSession = SessionModel(
        sessionId: cleanSessionId,
        userId: odooSession.userId,
        userName: odooSession.userName,
        userLogin: odooSession.userLogin,
        serverVersion: odooSession.serverVersion,
        userLang: odooSession.userLang,
        partnerId: odooSession.partnerId,
        userTimezone: odooSession.userTz,
        companyId: odooSession.companyId,
        companyName: prefs.getString('company_name') ?? 'Company',
        isSystem: odooSession.isSystem,
      );

      _lastAuthTime = DateTime.now();

      ConnectivityService.instance.setCurrentServerUrl(url);
      _onSessionUpdated?.call(_cachedSession!);
    } catch (e) {
      _client = null;
      _cachedSession = null;
    }
  }

  /// Ensures valid Odoo client instance exists.
  static Future<OdooClient> getClientEnsured() async {
    final session = await getCurrentSession();
    if (session == null) throw StateError('No session. Login required.');

    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString('url') ?? '';
    if (prefs.containsKey('odoo_session_id_raw')) {
      await initializeFromBrowserSession();
      if (_client != null) return _client!;
    }

    /// Reuse cached client if still valid.
    if (_client != null &&
        _cachedSession != null &&
        _lastAuthTime != null &&
        DateTime.now().difference(_lastAuthTime!) <
            _sessionCacheValidDuration) {
      return _client!;
    }

    final db =
        prefs.getString('selectedDatabase') ??
        prefs.getString('database') ??
        '';
    final sessionId = prefs.getString('sessionId') ?? '';
    final serverVersion = prefs.getString('serverVersion') ?? '';
    final userLang = prefs.getString('userLang') ?? '';
    final allowedCompaniesStringList =
        prefs.getStringList('allowedCompanies') ?? [];

    final allowedCompanies = allowedCompaniesStringList
        .map((jsonString) => Company.fromJson(jsonDecode(jsonString)))
        .toList();
    final odooSession = OdooSession(
      id: sessionId,
      userId: prefs.getInt('userId') ?? 0,
      partnerId: prefs.getInt('partnerId') ?? 0,
      userLogin: prefs.getString('userLogin') ?? '',
      userName: prefs.getString('userName') ?? '',
      userLang: userLang,
      userTz: '',
      isSystem: prefs.getBool('isSystem') ?? false,
      dbName: db,
      serverVersion: serverVersion,
      companyId: prefs.getInt('companyId') ?? 1,
      allowedCompanies: allowedCompanies,
    );

    final client = OdooClient(url, sessionId: odooSession);

    _client = client;
    _lastAuthTime = DateTime.now();
    return client;
  }

  /// Detects an exception that looks like it came from a dead/reset
  /// connection rather than a genuinely unreachable server — the kind
  /// `_client`'s cached, pooled keep-alive socket produces once it's gone
  /// stale (e.g. after the app sits backgrounded, or during a dev hot
  /// reload's edit-save gap) while still inside its 5-minute cache window.
  static bool _looksLikeStaleConnection(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('clientexception') ||
        s.contains('connection closed') ||
        s.contains('connection reset') ||
        s.contains('connection refused') ||
        s.contains('failed to connect') ||
        s.contains('connection failed') ||
        s.contains('broken pipe');
  }

  /// Executes RPC call with automatic session recovery.
  static Future<T> callWithSession<T>(
    Future<T> Function(OdooClient client) action,
  ) async {
    final generation = _sessionGeneration;
    final client = await getClientEnsured();

    Future<T> retryOnCurrentSession() async {
      final newClient = await getClientEnsured();
      try {
        return await action(newClient);
      } catch (retryError) {
        if (_isAuthError(retryError)) {
          throw const SessionUnrecoverableException();
        }
        rethrow;
      }
    }

    try {
      return await action(client);
    } catch (e) {
      if (e is NoInternetException || e is ServerUnreachableException) rethrow;

      if (_isAuthError(e)) {
        if (_sessionGeneration != generation) {
          return await retryOnCurrentSession();
        }

        final refreshed = await refreshSession();
        if (!refreshed) {
          throw const SessionUnrecoverableException();
        }
        return await retryOnCurrentSession();
      }
      if (_looksLikeStaleConnection(e)) {
        _client = null;
        final freshClient = await getClientEnsured();
        return await action(freshClient);
      }
      rethrow;
    }
  }

  /// Safe wrapper for callKw with company context injection.
  static Future<dynamic> safeCallKw(Map<String, dynamic> payload) {
    return callKwWithCompany(payload);
  }

  /// Safe wrapper for callKw without company context.
  static Future<dynamic> safeCallKwWithoutCompany(
    Map<String, dynamic> payload,
  ) {
    return callWithSession((client) => client.callKw(payload));
  }

  /// Clears session data and navigates to the login screen.
  static Future<void> logout(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: isDark ? Colors.grey[900] : Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(16),
                    child: LoadingWidget(
                      color: isDark
                          ? Colors.white
                          : Theme.of(context).colorScheme.primary,
                      size: 50,
                      variant: LoadingVariant.fourRotatingDots,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Logging out...',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please wait while we process your request.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    await Future.delayed(const Duration(milliseconds: 500));

    await clearSessionCache();
    try {
      final hiveService = HiveService();
      await hiveService.initialize();
      await hiveService.clearAllData();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();

    List<String> urlHistory = prefs.getStringList('urlHistory') ?? [];
    bool isGetStarted = prefs.getBool('hasSeenGetStarted') ?? false;
    bool biometricEnabled = prefs.getBool('biometricEnabled') ?? false;

    await prefs.clear();

    await prefs.setStringList('urlHistory', urlHistory);
    await prefs.setBool('hasSeenGetStarted', isGetStarted);
    await prefs.setBool('biometricEnabled', biometricEnabled);
    await prefs.setBool('isLoggedIn', false);

    await Future.delayed(const Duration(milliseconds: 100));

    if (context.mounted) {
      Navigator.of(context).pop();
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }
}
