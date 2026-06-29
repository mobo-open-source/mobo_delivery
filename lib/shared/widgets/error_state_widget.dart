import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:lottie/lottie.dart';
import 'buttons/mobo_button.dart';

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

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
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
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.red[900] : Colors.red[50])?.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: (isDark ? Colors.red[700] : Colors.red[200])!.withValues(alpha: 0.3),
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
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        if (onRetry != null || onContactSupport != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                if (onRetry != null)
                  MoboButton.secondary(
                    label: 'Retry',
                    icon: HugeIcons.strokeRoundedRefresh,
                    fullWidth: false,
                    borderRadius: 10,
                    onPressed: onRetry,
                  ),
                if (onContactSupport != null)
                  MoboButton.primary(
                    label: 'Contact Support',
                    icon: HugeIcons.strokeRoundedCustomerSupport,
                    fullWidth: false,
                    borderRadius: 10,
                    onPressed: onContactSupport,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _getLottieAsset() {
    switch (errorType) {
      case ErrorType.network:
        return 'assets/lotties/error_404.json';
      case ErrorType.server:
        return 'assets/lotties/error_404.json';
      case ErrorType.general:
        return 'assets/lotties/error_404.json';
    }
  }

  IconData _getFallbackIcon() {
    switch (errorType) {
      case ErrorType.network:
        return HugeIcons.strokeRoundedLocationOffline01;
      case ErrorType.server:
        return HugeIcons.strokeRoundedLocationOffline01;
      case ErrorType.general:
        return HugeIcons.strokeRoundedAlert02;
    }
  }
}
