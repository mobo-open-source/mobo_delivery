import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../utils/globals.dart';

/// The single source of truth for text inputs across the app.
///
/// Mirrors the mobo "filled, borderless" field design: an optional label above
/// the field, a soft filled background with a subtle shadow and rounded
/// corners, and **no visible border** by default. The brand color is only used
/// for the focus ring, so the resting state stays clean and neutral.
///
/// Set [showBorder] to draw a thin border in the resting/enabled state when a
/// form needs more definition (e.g. dense layouts). In dark mode the fill and
/// text colors flip to preserve contrast, matching the app convention.
///
/// Example:
/// ```dart
/// MoboTextField(
///   controller: _emailController,
///   label: 'Email',
///   hintText: 'you@example.com',
///   keyboardType: TextInputType.emailAddress,
///   validator: (v) => (v == null || v.isEmpty) ? 'Email is required' : null,
/// )
/// ```
class MoboTextField extends StatelessWidget {
  /// Controls the text being edited.
  final TextEditingController controller;

  /// Optional caption shown above the field. When null no label row is drawn.
  final String? label;

  /// Placeholder shown when the field is empty.
  final String? hintText;

  /// Optional validator used inside a [Form].
  final String? Function(String?)? validator;

  /// Keyboard type. Defaults to [TextInputType.text].
  final TextInputType? keyboardType;

  /// Maximum lines. Defaults to 1.
  final int? maxLines;

  /// When true the entered text is obscured (passwords). Forces a single line.
  final bool obscureText;

  /// Leading widget inside the field (e.g. an icon).
  final Widget? prefixIcon;

  /// Trailing widget inside the field (e.g. a visibility toggle).
  final Widget? suffixIcon;

  /// Focus node for managing focus order.
  final FocusNode? focusNode;

  /// Called whenever the text changes.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits the field (keyboard action).
  final ValueChanged<String>? onFieldSubmitted;

  /// Keyboard action button (e.g. next / done).
  final TextInputAction? textInputAction;

  /// Autofill hints (e.g. `[AutofillHints.email]`).
  final List<String>? autofillHints;

  /// When false the field is non-editable and dimmed.
  final bool enabled;

  /// Draws a thin border in the resting state. Defaults to false (borderless).
  final bool showBorder;

  /// When true a red `*` is appended to the [label] to mark the field as
  /// mandatory. Has no effect when [label] is null.
  final bool isRequired;

  /// Draws the soft drop shadow behind the field. Defaults to true. Set false
  /// for flat contexts (e.g. inside a dialog) where the shadow looks heavy.
  final bool showShadow;

  const MoboTextField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.focusNode,
    this.onChanged,
    this.onFieldSubmitted,
    this.textInputAction,
    this.autofillHints,
    this.enabled = true,
    this.showBorder = false,
    this.isRequired = false,
    this.showShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppStyle.primaryColor;

    final Color fillColor =
        isDark ? const Color(0xFF2A2A2A) : const Color(0xffF8FAFB);
    final Color textColor = isDark ? Colors.white70 : const Color(0xff000000);
    final Color labelColor = isDark ? Colors.white70 : const Color(0xff7F7F7F);
    final Color hintColor = isDark ? Colors.white38 : Colors.grey[500]!;
    final Color restingBorder = showBorder
        ? (isDark ? Colors.grey[700]! : Colors.grey[400]!)
        : Colors.transparent;

    OutlineInputBorder borderOf(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );

    final field = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  spreadRadius: 1,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        keyboardType: keyboardType ?? TextInputType.text,
        maxLines: obscureText ? 1 : maxLines,
        obscureText: obscureText,
        onChanged: onChanged,
        onFieldSubmitted: onFieldSubmitted,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        validator: validator,
        style: TextStyle(
          fontFamily: GoogleFonts.manrope(fontWeight: FontWeight.w600).fontFamily,
          color: textColor,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            fontFamily:
                GoogleFonts.manrope(fontWeight: FontWeight.w400).fontFamily,
            color: hintColor,
            fontStyle: FontStyle.italic,
            fontSize: 14,
          ),
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          filled: true,
          fillColor: fillColor,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: borderOf(restingBorder, 2),
          enabledBorder: borderOf(restingBorder, 1),
          focusedBorder: borderOf(primary, 1),
        ),
      ),
    );

    if (label == null) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RequiredLabel(
          label!,
          isRequired: isRequired,
          color: labelColor,
        ),
        const SizedBox(height: 8),
        field,
      ],
    );
  }
}

/// A field label that optionally appends a red `*` to mark a mandatory field.
///
/// Use this anywhere a field caption is built manually (outside [MoboTextField])
/// so the mandatory-star treatment stays consistent across the app.
class RequiredLabel extends StatelessWidget {
  final String label;
  final bool isRequired;
  final Color? color;
  final double fontSize;
  final FontWeight fontWeight;

  const RequiredLabel(
    this.label, {
    super.key,
    this.isRequired = false,
    this.color,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w400,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = color ?? (isDark ? Colors.white70 : const Color(0xff7F7F7F));
    return RichText(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily:
              GoogleFonts.manrope(fontWeight: fontWeight).fontFamily,
          color: baseColor,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
        children: isRequired
            ? const [
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: Color(0xFFD32F2F)),
                ),
              ]
            : null,
      ),
    );
  }
}
