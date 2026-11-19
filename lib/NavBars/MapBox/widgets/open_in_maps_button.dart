import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../shared/utils/globals.dart';

/// Compact pill that hands the route over to a map app on the phone.
///
/// Kept small and secondary on purpose: the card's two main buttons stay
/// "Add Stop" and "Start", and this sits beside the route summary it acts on.
/// The external-link glyph says the tap leaves the app.
class OpenInMapsButton extends StatelessWidget {
  const OpenInMapsButton({
    super.key,
    required this.onPressed,
    this.isBusy = false,
  });

  final VoidCallback? onPressed;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppStyle.primaryColor;
    final fg = isDark ? Colors.white : accent;
    return Semantics(
      button: true,
      label: 'Open route in Maps',
      excludeSemantics: true,
      child: Material(
        color: accent.withValues(alpha: isDark ? 0.22 : 0.08),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: isBusy ? null : onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isBusy)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fg,
                      ),
                    )
                  else
                    Icon(HugeIcons.strokeRoundedLinkSquare02, size: 16, color: fg),
                  const SizedBox(width: 6),
                  Text(
                    'Open in Maps',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
