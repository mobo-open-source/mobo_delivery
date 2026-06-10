import '../../core/company/session/company_session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AccessCheckStatus {
  ok,
  moduleMissing,
  noInventoryAccess,
}

class AppInstallCheck {
  static const _stockUserGroups = <String>[
    'stock.group_stock_manager',
    'stock.group_stock_user',
  ];

  Future<bool> _isStockModuleInstalled() async {
    try {
      final count = await CompanySessionManager.callKwWithCompany({
        'model': 'ir.module.module',
        'method': 'search_count',
        'args': [
          [
            ['name', '=', 'stock'],
            ['state', '=', 'installed'],
          ],
        ],
        'kwargs': {},
      });
      return (count ?? 0) > 0;
    } catch (_) {
      return true;
    }
  }

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

  Future<AccessCheckStatus> evaluateAccess() async {
    final installed = await _isStockModuleInstalled();
    if (!installed) return AccessCheckStatus.moduleMissing;
    final hasAccess = await _hasStockAccess();
    if (hasAccess == false) return AccessCheckStatus.noInventoryAccess;
    return AccessCheckStatus.ok;
  }

  Future<bool> checkRequiredModules() async =>
      await evaluateAccess() == AccessCheckStatus.ok;
}
