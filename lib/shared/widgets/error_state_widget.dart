import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../utils/globals.dart';

/// Defines the type of error to display the appropriate Lottie animation and colors.
enum ErrorType { network, server, general }

/// A common error display widget with support for retry and support actions.
/// Provides a consistent look and feel for error states across the application.
class ErrorStateWidget extends StatelessWidget {
  final String title;
  final String message;
  final ErrorType errorType;
  final VoidCallback? onRetry;
  final VoidCallback? onContactSupport;

  const ErrorStateWidget({
    super.key,
    required this.title,
    required this.message,
    this.errorType = ErrorType.general,
    this.onRetry,
    this.onContactSupport,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 220,
              height: 220,
              child: Lottie.asset(
                _getLottieAsset(),
                fit: BoxFit.contain,
                repeat: true,
                errorBuilder: (context, error, stackTrace) => Icon(
                  _getFallbackIcon(),
                  size: 100,
                  color: isDark ? Colors.red[700] : Colors.red[400],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: (isDark ? Colors.red[900] : Colors.red[50])?.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (isDark ? Colors.red[700] : Colors.red[200])!.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.grey[300] : Colors.black54,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                if (onRetry != null)
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 20),
                    label: const Text('Retry'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      foregroundColor: isDark ? Colors.white : AppStyle.primaryColor,
                      side: BorderSide(
                        color: isDark 
                            ? Colors.grey[600]! 
                            : AppStyle.primaryColor.withOpacity(0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                if (onContactSupport != null)
                  ElevatedButton.icon(
                    onPressed: onContactSupport,
                    icon: const Icon(Icons.support_agent, size: 20),
                    label: const Text('Contact Support'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      backgroundColor: AppStyle.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getLottieAsset() {
    switch (errorType) {
      case ErrorType.network:
        return 'assets/lotties/error_404.json'; // Placeholder for network error
      case ErrorType.server:
        return 'assets/lotties/error_404.json';
      case ErrorType.general:
        return 'assets/lotties/error_404.json';
    }
  }

  IconData _getFallbackIcon() {
    switch (errorType) {
      case ErrorType.network:
        return Icons.wifi_off_rounded;
      case ErrorType.server:
        return Icons.cloud_off_rounded;
      case ErrorType.general:
        return Icons.error_outline_rounded;
    }
  }
}
