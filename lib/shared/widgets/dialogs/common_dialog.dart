import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

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
  final bool destructivePrimary;
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
    this.destructivePrimary = false,
    this.topIconCentered = false,
    this.body,
  });

  Widget _buildIcon(dynamic icon, Color color, double size) {
    if (icon is IconData) {
      return Icon(icon, color: color, size: size);
    }
    return HugeIcon(icon: icon, color: color, size: size);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.primaryColor;

    final primaryBg = destructivePrimary ? Colors.red[600] : primary;
    final primaryFg = Colors.white;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
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
                      color: (destructivePrimary ? Colors.red : primary).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: _buildIcon(
                      icon,
                      destructivePrimary ? Colors.red[600]! : primary,
                      28,
                    ),
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
                        color: (destructivePrimary ? Colors.red : primary).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _buildIcon(
                        icon,
                        destructivePrimary ? Colors.red[600]! : primary,
                        22,
                      ),
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: primary, width: 2),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                if (secondaryLabel != null && onSecondary != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onSecondary,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: primary,
                        side: BorderSide(color: primary, width: 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        secondaryLabel!,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: ElevatedButton(
                    onPressed: onPrimary,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryBg,
                      foregroundColor: primaryFg,
                      elevation: isDark ? 0 : 3,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    child: Text(primaryLabel),
                  ),
                ),
              ],
            ),
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
    bool destructive = false,
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
        destructivePrimary: destructive,
        topIconCentered: centered,
      ),
    );
  }
}
