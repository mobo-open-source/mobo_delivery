import 'package:flutter/material.dart';
import 'loaders/loading_widget.dart';

/// A standard loading overlay that can be used to block user interaction during
/// long-running operations. Now uses the ported LoadingWidget from mobo_inv_app.
class LoadingOverlay extends StatelessWidget {
  final String? message;
  final bool isFullPage;

  const LoadingOverlay({
    super.key,
    this.message,
    this.isFullPage = true,
  });

  @override
  Widget build(BuildContext context) {
    return LoadingWidget(
      message: message,
      overlay: isFullPage,
      barrierDismissible: false,
    );
  }
}
