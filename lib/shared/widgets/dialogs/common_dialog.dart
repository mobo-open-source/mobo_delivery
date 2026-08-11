import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../buttons/mobo_button.dart';

/// A highly customizable dialog component used throughout the app for alerts, confirmations, and simple inputs.
class CommonDialog extends StatelessWidget {
  final String title;
  final String? message;
  final dynamic icon;
  final bool showInput;
  final String? inputHint;
  final TextEditingController? controller;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool topIconCentered;
  final Widget? body;

  const CommonDialog({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.showInput = false,
    this.inputHint,
    this.controller,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.topIconCentered = false,
    this.body,
  });

  Widget _buildIcon(dynamic icon, Color color, double size) {
    if (icon is IconData) {
      return Icon(icon, color: color, size: size);
    }
    return HugeIcon(icon: icon, color: color, size: size);
  }

  Widget _buildActions() {
    final primary = MoboButton.primary(
      label: primaryLabel,
      onPressed: onPrimary,
    );
    if (secondaryLabel == null || onSecondary == null) {
      return primary;
    }
    final secondary = MoboButton.secondary(
      label: secondaryLabel!,
      onPressed: onSecondary,
    );

    final stack = primaryLabel.length > 12 || secondaryLabel!.length > 12;
    if (stack) {
      return Column(children: [secondary, const SizedBox(height: 10), primary]);
    }
    return Row(
      children: [
        Expanded(child: secondary),
        const SizedBox(width: 12),
        Expanded(child: primary),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.primaryColor;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (topIconCentered) ...[
              if (icon != null) ...[
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: _buildIcon(icon, primary, 28),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              if (message != null && message!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _buildIcon(icon, primary, 22),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              if (message != null && message!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  message!,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ],
            if (body != null) ...[const SizedBox(height: 16), body!],
            if (showInput) ...[
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: inputHint ?? 'Enter text...',
                  filled: true,
                  fillColor: isDark ? Colors.grey[850] : Colors.grey[50],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: primary, width: 2),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    String? message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    dynamic icon,
    bool centered = true,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => CommonDialog(
        title: title,
        message: message,
        icon: icon,
        primaryLabel: confirmText,
        onPrimary: () => Navigator.of(ctx).pop(true),
        secondaryLabel: cancelText,
        onSecondary: () => Navigator.of(ctx).pop(false),
        topIconCentered: centered,
      ),
    );
  }
}
