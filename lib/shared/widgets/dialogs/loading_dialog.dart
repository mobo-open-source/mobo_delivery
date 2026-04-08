import 'package:flutter/material.dart';
import '../loaders/loading_widget.dart';

class LoadingDialog {
  static void show(BuildContext context, {String? message}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.2),
      builder: (ctx) => PopScope(
        canPop: false,
        child: Center(
          child: IntrinsicWidth(
            child: Card(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 22,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    LoadingWidget(
                      color: theme.primaryColor,
                      size: 48,
                      variant: LoadingVariant.staggeredDots,
                    ),
                    if (message != null && message.trim().isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.grey[300] : Colors.black87,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void hide(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }
}
