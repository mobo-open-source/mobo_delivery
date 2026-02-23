import '../../core/company/session/company_session_manager.dart';

/// Utility class used to verify whether required backend modules
/// are installed in the Odoo server.
///
/// Uses RPC calls via CompanySessionManager to check module availability.
/// Includes fallback model checks to verify general API accessibility.
class AppInstallCheck {

  /// Checks whether a specific Odoo module is installed.
  ///
  /// First attempts direct module lookup using `ir.module.module`.
  /// If it fails (e.g., permission issues or restricted access),
  /// falls back to checking a commonly available model (`account.move`)
  /// to verify backend connectivity.
  ///
  /// Returns:
  /// - true → Module installed OR backend reachable
  /// - false → Module missing OR backend not reachable
  Future<bool> isModuleInstalled(String moduleName) async {
    try {
      /// Primary check using module registry
      final count = await CompanySessionManager.callKwWithCompany({
        'model': 'ir.module.module',
        'method': 'search_count',
        'args': [
          [
            ['name', '=', moduleName],
            ['state', '=', 'installed']
          ]
        ],
        'kwargs': {}
      });
      return (count ?? 0) > 0;
    } catch (_) {
      /// Fallback check:
      /// If module lookup fails, verify general API access using account.move
      try {
        await CompanySessionManager.callKwWithCompany({
          'model': 'account.move',
          'method': 'search_count',
          'args': [[]],
          'kwargs': {'limit': 1}
        });
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  /// Checks whether Inventory module is installed.
  ///
  /// Required for:
  /// - Check-in / Check-out features
  /// - Time tracking
  /// - Presence management
  Future<bool> checkRequiredModules() async {
    return await isModuleInstalled('stock');
  }
}
