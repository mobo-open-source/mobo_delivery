import 'package:flutter/material.dart';

import '../../../core/company/session/company_session_manager.dart';
import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/dialogs/common_dialog.dart';
import '../../../shared/utils/odoo_error_classifier.dart';

/// Inline card shown in place of a single failing section's content.
class SectionErrorState extends StatelessWidget {
  final String sectionTitle;
  final String message;
  final IconData icon;

  /// Offers a way out when retrying cannot help. Some server-side failures
  /// leave the app holding a session it can no longer use, and no amount of
  /// retrying recovers it — signing in again is the only remedy, so the card
  /// has to offer it rather than only advising a connection check.
  final bool showLogout;

  const SectionErrorState({
    super.key,
    required this.sectionTitle,
    required this.message,
    required this.icon,
    this.showLogout = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 24, color: Colors.orange.shade400),
          ),
          const SizedBox(height: 16),
          Text(
            'Unable to load $sectionTitle',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          if (showLogout) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => _confirmLogout(context),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppStyle.primaryColor),
                foregroundColor: AppStyle.primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Log out',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Confirms first, using the same dialog as the Configuration screen's
  /// logout so signing out reads identically wherever it is offered.
  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await CommonDialog.confirm(
      context,
      title: 'Confirm Logout',
      message: 'Are you sure you want to log out? Your session will be ended.',
      confirmText: 'Log Out',
      cancelText: 'Cancel',
      centered: false,
    );

    if (confirmed == true && context.mounted) {
      CompanySessionManager.logout(context);
    }
  }
}

/// Turns a raw exception into cause-specific copy for a Home section.
String homeSectionErrorMessage({
  required bool online,
  required String? error,
  required String offlineDetail,
  required String genericDetail,
}) {
  if (!online) {
    return 'No internet connection. $offlineDetail';
  }
  if (OdooErrorClassifier.isSessionExpired(error)) {
    return 'Session expired. Please log out and sign in again to continue.';
  }
  if (OdooErrorClassifier.isServerUnreachable(error)) {
    return 'Unable to connect to your Odoo server. Please check your server '
        'connection and try again.';
  }
  return genericDetail;
}

/// Whether this failure is one the user cannot retry their way out of, so the
/// section should offer to sign them in again.
///
/// Deliberately not limited to failures that *say* the session expired. A
/// session the server has stopped honouring surfaces under several different
/// messages, and in each of them retrying changes nothing while re-authenticating
/// fixes it — so the offer is made whenever a section fails with the device
/// online. It is withheld when the device is offline, where the answer really
/// is to wait for a connection, and signing out would only destroy the cached
/// data being relied on in the meantime.
bool homeSectionNeedsReLogin({required bool online, required String? error}) {
  if (!online) return false;
  return error != null && error.isNotEmpty;
}
