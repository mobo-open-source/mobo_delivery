import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
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
/// No signer name is collected: `stock.picking` has no `signed_by` field —
/// that belongs to `sale.order` — and Odoo names the signer from the
/// picking's `partner_id`.
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
  /// CSS `DarkBlue`, the colour Odoo's own signature widget draws in.
  static const Color _inkColor = Color(0xFF00008B);

  late final SignatureController _controller;

  /// A signature picked from a file instead of drawn, matching the "Load"
  /// tab Odoo offers beside "Draw".
  Uint8List? _loadedSignature;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(penColor: _inkColor, penStrokeWidth: 2);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Loads a signature from an image file, Odoo's "Load" tab.
  Future<void> _loadSignature() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg'],
        withData: true,
      );
      final bytes = result?.files.single.bytes;
      if (bytes == null || !mounted) return;
      setState(() {
        _loadedSignature = bytes;
        _controller.clear();
      });
    } catch (_) {
      if (mounted) {
        CustomSnackbar.showError(context, 'Could not read that image.');
      }
    }
  }

  /// Converts the signature to a base64 PNG and pops the dialog with it.
  /// Warns if nothing has been drawn or loaded.
  Future<void> _saveSignature() async {
    if (_loadedSignature != null) {
      Navigator.pop(context, {
        'fileName': 'signature_${DateTime.now().millisecondsSinceEpoch}.png',
        'mimeType': 'image/png',
        'base64': base64Encode(_loadedSignature!),
      });
      return;
    }

    if (_controller.isEmpty) {
      CustomSnackbar.showWarning(context, 'Please sign before saving.');
      return;
    }

    const margin = 32;
    final width = _controller.defaultWidth;
    final height = _controller.defaultHeight;
    final signatureBytes = await _controller.toPngBytes(
      width: width == null ? null : width + margin * 2,
      height: height == null ? null : height + margin * 2,
    );
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
                  onTap: () => setState(() {
                    _controller.clear();
                    _loadedSignature = null;
                  }),
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
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _loadSignature,
                icon: Icon(
                  HugeIcons.strokeRoundedUploadSquare02,
                  size: 18,
                  color: AppStyle.primaryColor,
                ),
                label: Text(
                  _loadedSignature == null
                      ? 'Load from image'
                      : 'Choose another',
                  style: TextStyle(
                    color: AppStyle.primaryColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppStyle.primaryColor.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _loadedSignature != null
                    ? Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(8),
                        child: Image.memory(
                          _loadedSignature!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Text('That file is not a readable image'),
                          ),
                        ),
                      )
                    : Signature(
                        controller: _controller,
                        backgroundColor: Colors.white,
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
