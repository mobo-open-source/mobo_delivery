import '../../core/company/session/company_session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AccessCheckStatus { ok, moduleMissing, noInventoryAccess, unverified }

class AppInstallCheck {
  /// The Inventory menu's external id, present on Odoo 17 through 20.
  static const _moduleProbe = <dynamic>['stock', 'menu_stock_root'];

  static const _stockUserGroups = <String>[
    'stock.group_stock_manager',
    'stock.group_stock_user',
  ];

  /// Whether Inventory is installed, or null when the server gave no usable
  /// answer.
  ///
  /// `ir.model.data.check_object_reference` resolves the external id in raw
  /// SQL, so it answers for any signed-in user. The earlier probe counted
  /// `ir.module.module` rows, which Odoo 17-20 grant to `base.group_system`
  /// alone: every user without Settings rights raised an access error there
  /// and was then waved through by the catch. mobo_sales asks this same way.
  Future<bool?> _isStockModuleInstalled() async {
    try {
      await CompanySessionManager.callKwWithCompany({
        'model': 'ir.model.data',
        'method': 'check_object_reference',
        'args': List<dynamic>.of(_moduleProbe),
        'kwargs': {},
      });
      return true;
    } catch (e) {
      if (_isMissingExternalId(e)) return false;
      return null;
    }
  }

  /// Whether [error] is Odoo's "External ID not found in the system", the
  /// answer it gives for an id no installed module created.
  static bool _isMissingExternalId(Object error) =>
      error.toString().toLowerCase().contains('external id not found');

  Future<bool?> _hasStockAccess() async {
    final prefs = await SharedPreferences.getInstance();
    final int? userId = prefs.getInt('userId');
    final int majorVersion = prefs.getInt('version') ?? 0;

    bool sawDefiniteFalse = false;

    for (final group in _stockUserGroups) {
      try {
        final payload = majorVersion >= 18
            ? {
                'model': 'res.users',
                'method': 'has_group',
                'args': [userId, group],
                'kwargs': {},
              }
            : {
                'model': 'res.users',
                'method': 'has_group',
                'args': [group],
                'kwargs': {},
              };
        final result = await CompanySessionManager.callKwWithCompany(payload);
        if (result == true) return true;
        if (result == false) sawDefiniteFalse = true;
      } catch (_) {}
    }
    return sawDefiniteFalse ? false : null;
  }

  /// What the module and the group add up to, for a sign-in.
  ///
  /// An answer short of a clear yes is [AccessCheckStatus.unverified] and
  /// keeps the account out: a sign-in talks to the server by definition, so
  /// there is no offline case to let through, and a guess here would admit
  /// exactly the accounts the check exists to stop.
  Future<AccessCheckStatus> evaluateAccess() async {
    final installed = await _isStockModuleInstalled();
    if (installed == false) return AccessCheckStatus.moduleMissing;

    final hasAccess = await _hasStockAccess();
    if (hasAccess == false) return AccessCheckStatus.noInventoryAccess;

    if (installed == null || hasAccess == null) {
      return AccessCheckStatus.unverified;
    }
    return AccessCheckStatus.ok;
  }

  /// Why the session stored on this device may no longer use the app, or null
  /// when it may.
  ///
  /// For the app start, where Inventory may have been uninstalled or the
  /// user's access taken away since the last sign-in. Unlike [evaluateAccess]
  /// only a definite "no" counts: no network or a server that will not answer
  /// leaves the user where they were, as the app does offline elsewhere.
  Future<AccessCheckStatus?> storedSessionProblem({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final status = await evaluateAccess().timeout(timeout);
      if (status == AccessCheckStatus.ok ||
          status == AccessCheckStatus.unverified) {
        return null;
      }
      return status;
    } catch (_) {
      return null;
    }
  }

  Future<bool> checkRequiredModules() async =>
      await evaluateAccess() == AccessCheckStatus.ok;
}
