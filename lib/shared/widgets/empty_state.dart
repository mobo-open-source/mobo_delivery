import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'buttons/mobo_button.dart';

/// A generic placeholder widget displayed when a list or view has no data.
/// Uses Lottie animations for a premium feel.
class EmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? lottieAsset;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  const EmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.lottieAsset,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: padding,
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (lottieAsset != null)
                Lottie.asset(
                  lottieAsset!,
                  width: 220,
                  height: 220,
                  repeat: true,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => Icon(
                    Icons.inbox_outlined,
                    size: 80,
                    color: isDark ? Colors.grey[700] : Colors.grey[400],
                  ),
                )
              else
                Icon(
                  Icons.inbox_outlined,
                  size: 80,
                  color: isDark ? Colors.grey[700] : Colors.grey[400],
                ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 24),
                MoboButton.secondary(
                  label: actionLabel!,
                  fullWidth: false,
                  borderRadius: 8,
                  onPressed: onAction,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
