import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Result of an app-store version check.
class VersionCheckResult {
  /// The version currently installed on the device (e.g. "1.0.2").
  final String currentVersion;

  /// The latest version published on the store (e.g. "1.0.4"), or null if the
  /// lookup failed.
  final String? storeVersion;

  /// True when [storeVersion] is strictly newer than [currentVersion].
  final bool updateAvailable;

  const VersionCheckResult({
    required this.currentVersion,
    required this.storeVersion,
    required this.updateAvailable,
  });
}

/// Checks whether a newer build of the app is available on the platform store.
///
/// - iOS: uses the public iTunes Lookup API (by bundle id).
/// - Android: scrapes the public Play Store listing (by package id).
///
/// Store lookups only reveal the *latest published* version — there is no
/// "minimum required" signal — so callers decide whether to present the update
/// as optional or mandatory.
///
/// All failures (offline, parsing, store throttling) resolve to
/// `updateAvailable == false` so the check never blocks app start.
class VersionCheckService {
  /// Android package id (Play Store `id=` parameter).
  static const String _androidPackageId = 'com.cybrosys.mobo_delivery';

  /// iOS bundle id used by the iTunes lookup API.
  static const String _iosBundleId = 'com.cybrosys.mobo-delivery';

  /// Optional iTunes storefront country code (lowercase, e.g. "us", "in").
  /// The app may not be visible in every storefront's lookup.
  final String _iosCountry;

  final http.Client _client;

  /// Direct App Store URL discovered during the iOS lookup (`trackViewUrl`).
  /// Used by [openStore] so we link to the exact listing rather than guessing.
  String? _iosStoreUrl;

  VersionCheckService({http.Client? client, String iosCountry = 'us'})
      : _client = client ?? http.Client(),
        _iosCountry = iosCountry;

  /// Performs the version check for the current platform.
  Future<VersionCheckResult> check() async {
    final info = await PackageInfo.fromPlatform();
    final current = info.version;

    String? store;
    try {
      if (Platform.isIOS) {
        store = await _fetchIosVersion();
      } else if (Platform.isAndroid) {
        store = await _fetchAndroidVersion();
      }
    } catch (_) {
      store = null;
    }

    final available = store != null && _isNewer(store, current);
    return VersionCheckResult(
      currentVersion: current,
      storeVersion: store,
      updateAvailable: available,
    );
  }

  /// Opens the platform store listing for this app so the user can update.
  ///
  /// On iOS this prefers the exact `trackViewUrl` captured by [check]; if that
  /// isn't available it falls back to a bundle-id search on the App Store.
  Future<void> openStore() async {
    final Uri uri = Platform.isIOS
        ? Uri.parse(
            _iosStoreUrl ??
                'https://apps.apple.com/search?term=$_iosBundleId',
          )
        : Uri.parse(
            'https://play.google.com/store/apps/details?id=$_androidPackageId',
          );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<String?> _fetchIosVersion() async {
    final uri = Uri.parse(
      'https://itunes.apple.com/lookup'
      '?bundleId=$_iosBundleId&country=$_iosCountry',
    );
    final res = await _client
        .get(uri)
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;

    final body = json.decode(res.body) as Map<String, dynamic>;
    final results = body['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;
    final first = results.first as Map<String, dynamic>;
    _iosStoreUrl = first['trackViewUrl'] as String?;
    return first['version'] as String?;
  }

  Future<String?> _fetchAndroidVersion() async {
    final uri = Uri.parse(
      'https://play.google.com/store/apps/details'
      '?id=$_androidPackageId&hl=en&gl=US',
    );
    final res = await _client
        .get(uri)
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;

    final body = res.body;
    final patterns = <RegExp>[
      RegExp(r'\[\[\["([0-9]+\.[0-9]+(?:\.[0-9]+)?)"\]\]'),
      RegExp(r'Current Version.*?>([0-9]+\.[0-9]+(?:\.[0-9]+)?)<'),
    ];
    for (final re in patterns) {
      final match = re.firstMatch(body);
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// Returns true when [candidate] is a strictly higher version than [current].
  ///
  /// Compares dotted numeric segments (e.g. "1.0.10" > "1.0.9"). Non-numeric or
  /// missing segments are treated as 0.
  bool _isNewer(String candidate, String current) {
    final a = _segments(candidate);
    final b = _segments(current);
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final ai = i < a.length ? a[i] : 0;
      final bi = i < b.length ? b[i] : 0;
      if (ai != bi) return ai > bi;
    }
    return false;
  }

  List<int> _segments(String version) {

    final core = version.split('+').first.split('-').first;
    return core
        .split('.')
        .map((s) => int.tryParse(s.trim()) ?? 0)
        .toList();
  }
}
