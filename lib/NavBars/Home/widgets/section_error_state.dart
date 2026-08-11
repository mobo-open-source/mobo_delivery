import 'package:flutter/material.dart';

/// Inline card shown in place of a single failing section's content.
class SectionErrorState extends StatelessWidget {
  final String sectionTitle;
  final String message;
  final IconData icon;

  const SectionErrorState({
    super.key,
    required this.sectionTitle,
    required this.message,
    required this.icon,
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
        ],
      ),
    );
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
  if (_isServerUnreachableError(error)) {
    return 'Unable to connect to your Odoo server. Please check your server '
        'connection and try again.';
  }
  return genericDetail;
}

bool _isServerUnreachableError(String? error) {
  if (error == null || error.isEmpty) return false;
  final e = error.toLowerCase();
  return e.contains('socketexception') ||
      e.contains('clientexception') ||
      e.contains('failed host lookup') ||
      e.contains('connection refused') ||
      e.contains('connection timeout') ||
      e.contains('host unreachable') ||
      e.contains('no route to host') ||
      e.contains('network is unreachable') ||
      e.contains('failed to connect') ||
      e.contains('connection failed') ||
      e.contains('odoo server error') ||
      e.contains('unexpected response') ||
      e.contains('500') ||
      e.contains('502') ||
      e.contains('503') ||
      e.contains('504');
}
