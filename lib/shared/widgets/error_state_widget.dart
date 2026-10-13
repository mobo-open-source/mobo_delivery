import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../core/company/services/connectivity_service.dart';
import '../utils/globals.dart';
import '../utils/odoo_error_classifier.dart';

/// Defines the type of error, used to pick the fallback icon if the Lottie
/// asset fails to load.
enum ErrorType { network, server, general }

/// The app's single full-page error state. Derives its title and message
/// from [errorMessage] and the current connectivity.
class ErrorStateWidget extends StatefulWidget {
  /// Raw exception text.
  final String? errorMessage;

  final VoidCallback? onRetry;
  final ErrorType errorType;

  const ErrorStateWidget({
    super.key,
    this.errorMessage,
    this.onRetry,
    this.errorType = ErrorType.general,
  });

  @override
  State<ErrorStateWidget> createState() => _ErrorStateWidgetState();
}

class _ErrorStateWidgetState extends State<ErrorStateWidget> {
  late bool _noInternet =
      !ConnectivityService.instance.lastKnownInternetReachable;
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();
    _refreshConnectivity();
  }

  Future<void> _refreshConnectivity() async {
    final online = await ConnectivityService.instance.hasInternetAccess();
    if (mounted && online == _noInternet) {
      setState(() => _noInternet = !online);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.grey[900]! : Colors.grey[50]!;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    final info = _noInternet
        ? const {
            'title': 'No Internet Connection',
            'message': 'Please check your internet connection and try again.',
          }
        : _errorInfo(widget.errorMessage);

    final title = info['title']!;
    final subtitle = info['message']!;

    final isSessionError =
        title.toLowerCase().contains('session expired') ||
        subtitle.toLowerCase().contains('session has expired') ||
        subtitle.toLowerCase().contains('log in again');

    final buttonText = isSessionError ? 'Log In' : 'Retry';
    final onAction = isSessionError
        ? () {
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil('/login', (route) => false);
          }
        : widget.onRetry;

    return Container(
      color: backgroundColor,
      width: double.infinity,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Lottie.asset(
                'assets/lotties/error_404.json',
                width: MediaQuery.of(context).size.width * 0.6,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Icon(
                  _fallbackIcon(),
                  size: 100,
                  color: isDark ? Colors.red[700] : Colors.red[400],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 15,
                  color: subtitleColor,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              if (widget.errorMessage != null &&
                  widget.errorMessage!.trim().isNotEmpty &&
                  widget.errorMessage != subtitle) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => setState(() => _showDetails = !_showDetails),
                  child: Text(
                    _showDetails ? 'Hide details' : 'Show details',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: subtitleColor,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                if (_showDetails) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    widget.errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: subtitleColor,
                    ),
                  ),
                ],
              ],
              if (onAction != null) ...[
                const SizedBox(height: 32),
                SizedBox(
                  width: 140,
                  child: OutlinedButton(
                    onPressed: onAction,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: AppStyle.primaryColor,
                        width: 1.2,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      foregroundColor: AppStyle.primaryColor,
                    ),
                    child: Text(
                      buttonText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Maps a raw exception to the title and message shown on this screen.
  ///
  /// Delegates to [OdooErrorClassifier] so every screen in the app agrees on
  /// what "unreachable" means. This used to keep its own marker list, which
  /// had drifted into reporting a reachable server as an unreachable one:
  ///
  /// * `Odoo Server Error` was treated as a transport failure. Odoo returns
  ///   that phrase for *every* server-side Python exception — access rights,
  ///   validation, a missing field — so an ordinary application error told
  ///   the user to go and check their network.
  /// * `TimeoutException` was treated the same way, when a slow query on a
  ///   healthy server is a different problem with a different answer.
  /// * A null or empty error defaulted to "Can't Reach Server", asserting a
  ///   network fault on no evidence whatsoever.
  Map<String, String> _errorInfo(String? error) {
    if (error == null || error.trim().isEmpty) {
      return {
        'title': 'Something Went Wrong',
        'message': 'We couldn\'t load this page. Please try again.',
      };
    }

    final errorLower = error.toLowerCase();

    if (OdooErrorClassifier.isSessionExpired(error)) {
      return {
        'title': 'Session Expired',
        'message': 'Your session has expired. Please log in again to continue.',
      };
    }

    if (OdooErrorClassifier.isServerUnreachable(error)) {
      return {
        'title': 'Can\'t Reach Server',
        'message':
            'Unable to connect to your Odoo server. Please check your network '
            'connection and try again.',
      };
    }

    if (errorLower.contains('timeoutexception') ||
        errorLower.contains('504 gateway timeout')) {
      return {
        'title': 'Server Took Too Long',
        'message':
            'The server is reachable but did not respond in time. It may be '
            'busy — please try again.',
      };
    }

    if (errorLower.contains('formatexception') ||
        errorLower.contains('unexpected character')) {
      return {
        'title': 'Unexpected Response',
        'message':
            'The server returned a response the app could not read. Please '
            'try again later.',
      };
    }

    if (errorLower.contains('500 internal server error')) {
      return {
        'title': 'Server Error (500)',
        'message': 'The server encountered an error. Please try again later.',
      };
    }
    if (errorLower.contains('502 bad gateway')) {
      return {
        'title': 'Server Error (502)',
        'message': 'Bad gateway. The server is temporarily unavailable.',
      };
    }
    if (errorLower.contains('503 service unavailable')) {
      return {
        'title': 'Server Unavailable (503)',
        'message':
            'The server is temporarily unavailable. Please try again later.',
      };
    }

    // Anything else is an application-level failure the server reported. Say
    // so plainly rather than blaming the connection; the raw text stays
    // available behind "Show details".
    if (errorLower.contains('odoo server error') ||
        errorLower.contains('odooexception')) {
      return {
        'title': 'Request Failed',
        'message':
            'The server rejected this request. Please try again, or contact '
            'your administrator if it keeps happening.',
      };
    }

    return {'title': 'Error', 'message': error};
  }

  IconData _fallbackIcon() {
    switch (widget.errorType) {
      case ErrorType.network:
        return Icons.wifi_off_rounded;
      case ErrorType.server:
        return Icons.cloud_off_rounded;
      case ErrorType.general:
        return Icons.error_outline_rounded;
    }
  }
}
