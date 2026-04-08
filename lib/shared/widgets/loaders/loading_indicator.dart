import 'package:flutter/material.dart';
import 'loading_widget.dart';

/// A centered loading indicator with an optional status message.
class LoadingIndicator extends StatelessWidget {
  final String? message;
  final Color? color;
  final double size;

  const LoadingIndicator({super.key, this.message, this.color, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LoadingWidget(
            color: color ?? theme.primaryColor,
            size: size,
            variant: LoadingVariant.staggeredDots,
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: TextStyle(
                color: isDark ? Colors.grey[300] : Colors.black87,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// A compact version of the loading indicator for use within buttons or small containers.
class SmallLoadingIndicator extends StatelessWidget {
  final Color? color;

  const SmallLoadingIndicator({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return LoadingWidget(
      color: color ?? Theme.of(context).primaryColor,
      size: 20,
      variant: LoadingVariant.staggeredDots,
    );
  }
}
