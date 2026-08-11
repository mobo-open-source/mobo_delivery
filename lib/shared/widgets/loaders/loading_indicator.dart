import 'package:flutter/material.dart';
import 'loading_widget.dart';

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
          LoadingWidget(color: color ?? theme.primaryColor, size: size),
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

class SmallLoadingIndicator extends StatelessWidget {
  final Color? color;

  const SmallLoadingIndicator({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? Theme.of(context).primaryColor;
    return SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(color: resolvedColor, strokeWidth: 2.5),
    );
  }
}
