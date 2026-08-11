import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/buttons/mobo_button.dart';
import '../../../shared/widgets/snackbar.dart';

/// A pop-up signature capture dialog.
///
/// Lets the user draw a signature by hand, clear it, and confirm. On "Done"
/// the drawing is encoded as a base64 PNG and returned to the caller as a map
/// with `fileName`, `mimeType` and `base64`. Returns `null` if dismissed.
///
/// Use [SignatureDialog.show] instead of pushing a full screen:
/// ```dart
/// final result = await SignatureDialog.show(context);
/// ```
class SignatureDialog extends StatefulWidget {
  const SignatureDialog({super.key});

  /// Opens the signature capture as a modal pop-up and returns the captured
  /// signature data (or `null` if the user cancels / dismisses it).
  static Future<Map<String, dynamic>?> show(BuildContext context) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const SignatureDialog(),
    );
  }

  @override
  State<SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<SignatureDialog> {
  late final SignatureController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penColor: Colors.black,
      penStrokeWidth: 5,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Converts the drawing to a base64 PNG and pops the dialog with the result.
  /// Warns if the canvas is empty.
  Future<void> _saveSignature() async {
    if (_controller.isEmpty) {
      CustomSnackbar.showWarning(context, 'Please sign before saving.');
      return;
    }

    final signatureBytes = await _controller.toPngBytes();
    if (signatureBytes != null && mounted) {
      final fileName = 'signature_${DateTime.now().millisecondsSinceEpoch}.png';
      Navigator.pop(context, {
        'fileName': fileName,
        'mimeType': 'image/png',
        'base64': base64Encode(signatureBytes),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? Colors.grey[900] : Colors.white;

    return Dialog(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Signature',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _controller.clear(),
                  child: Text(
                    'Clear',
                    style: TextStyle(
                      color: AppStyle.primaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppStyle.primaryColor.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Signature(
                  controller: _controller,
                  backgroundColor: isDark ? Colors.grey[800]! : Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: MoboButton.secondary(
                    label: 'Cancel',
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MoboButton.primary(
                    label: 'Done',
                    onPressed: _saveSignature,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
