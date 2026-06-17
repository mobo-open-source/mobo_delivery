import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Primary login-flow button — identical to the mobo sales app's login button
/// (solid black, white text). Used for Next / Sign In / Send / Authenticate so
/// the login screens stay consistent with the rest of the mobo suite.
class LoginButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  /// Optional widget shown while [isLoading] is true (e.g. a label + loader).
  final Widget? loadingWidget;

  const LoginButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.loadingWidget,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.black.withValues(alpha: .2),
          disabledForegroundColor: Colors.white,
          overlayColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading && loadingWidget != null
            ? loadingWidget!
            : Text(
                text,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
