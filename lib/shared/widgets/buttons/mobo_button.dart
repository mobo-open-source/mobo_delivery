import 'package:flutter/material.dart';

import '../../utils/globals.dart';
import '../loaders/loading_widget.dart';

/// Visual style of a [MoboButton].
///
/// • [primary]   — filled with the mobo brand color (white text). The main
///                 call-to-action on a screen/dialog.
/// • [secondary] — transparent fill with a mobo-color border and text. Used
///                 for the lower-emphasis option beside a primary action
///                 (e.g. Cancel / Discard).
/// • [danger]    — filled with the error/red color. Reserved for destructive
///                 actions such as Logout / Delete.
enum MoboButtonVariant { primary, secondary, danger }

/// The single source of truth for buttons across the app.
///
/// Centralizes the mobo button design so every call site stays consistent:
///   • primary  → mobo fill (`AppStyle.primaryColor`) with white label
///   • secondary→ mobo border + label
///   • disabled → grey (when [onPressed] is null or [isLoading] is true)
///
/// The brand color holds in dark mode rather than flipping to white.
///
/// Example:
/// ```dart
/// MoboButton.primary(
///   label: 'Sign In',
///   isLoading: _isLoading,
///   loadingLabel: 'Signing',
///   onPressed: _login,
/// )
/// ```
class MoboButton extends StatelessWidget {
  /// Text shown on the button.
  final String label;

  /// Tapped callback. When null the button renders in its disabled (grey)
  /// state — this is how "inactivate the button before data is ready" is
  /// expressed: pass `null` until the action is available.
  final VoidCallback? onPressed;

  /// Visual style. Defaults to [MoboButtonVariant.primary].
  final MoboButtonVariant variant;

  /// Optional leading icon shown before the label.
  final IconData? icon;

  /// When true the button shows a loader and ignores taps.
  final bool isLoading;

  /// Optional text shown next to the loader while [isLoading] is true
  /// (e.g. "Signing", "Checking"). When null only the loader is shown.
  final String? loadingLabel;

  /// Stretches the button to the full available width. Defaults to true,
  /// which matches the common full-width action button.
  final bool fullWidth;

  /// Fixed button height. Defaults to 48.
  final double height;

  /// Corner radius. Defaults to 12.
  final double borderRadius;

  const MoboButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = MoboButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.loadingLabel,
    this.fullWidth = true,
    this.height = 48,
    this.borderRadius = 12,
  });

  /// Convenience constructor for the primary (filled) variant.
  const MoboButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.loadingLabel,
    this.fullWidth = true,
    this.height = 48,
    this.borderRadius = 12,
  }) : variant = MoboButtonVariant.primary;

  /// Convenience constructor for the secondary (outlined) variant.
  const MoboButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.loadingLabel,
    this.fullWidth = true,
    this.height = 48,
    this.borderRadius = 12,
  }) : variant = MoboButtonVariant.secondary;

  /// Convenience constructor for the destructive (red) variant.
  const MoboButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.loadingLabel,
    this.fullWidth = true,
    this.height = 48,
    this.borderRadius = 12,
  }) : variant = MoboButtonVariant.danger;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool enabled = onPressed != null && !isLoading;

    final Color disabledBg = isDark ? Colors.grey[700]! : Colors.grey[300]!;
    final Color disabledFg = isDark ? Colors.white54 : Colors.grey[600]!;

    late final Color enabledBg;
    late final Color enabledFg;
    late final Color enabledBorder;
    switch (variant) {
      case MoboButtonVariant.primary:

        enabledBg = AppStyle.primaryColor;
        enabledFg = Colors.white;
        enabledBorder = Colors.transparent;
        break;
      case MoboButtonVariant.secondary:
        enabledBg = Colors.transparent;

        enabledFg = AppStyle.accentOn(
          isDark ? Brightness.dark : Brightness.light,
        );
        enabledBorder = enabledFg;
        break;
      case MoboButtonVariant.danger:
        enabledBg =
            isDark ? Colors.red[700]! : Theme.of(context).colorScheme.error;
        enabledFg = Colors.white;
        enabledBorder = Colors.transparent;
        break;
    }

    final bool isSecondary = variant == MoboButtonVariant.secondary;

    final Color bg = enabled
        ? enabledBg
        : (isSecondary ? Colors.transparent : disabledBg);
    final Color fg = enabled ? enabledFg : disabledFg;
    final Color border = enabled
        ? enabledBorder
        : (isSecondary ? disabledFg : Colors.transparent);

    final Widget child = _buildChild(fg);

    final button = ElevatedButton(
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg,
        disabledForegroundColor: fg,

        elevation: 0,
        shadowColor: Colors.transparent,
        minimumSize: Size(0, height),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        side: border == Colors.transparent
            ? BorderSide.none
            : BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
      child: child,
    );

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: height,
      child: button,
    );
  }

  Widget _buildChild(Color fg) {
    if (isLoading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loadingLabel != null) ...[
            Flexible(
              child: Text(
                loadingLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          LoadingWidget(
            color: fg,
            size: 26,
            variant: LoadingVariant.staggeredDots,
          ),
        ],
      );
    }

    final labelWidget = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.bold, color: fg),
      ),
    );

    if (icon == null) return labelWidget;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: fg),
        const SizedBox(width: 8),
        Flexible(child: labelWidget),
      ],
    );
  }
}
