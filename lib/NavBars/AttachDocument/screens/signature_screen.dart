import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:signature/signature.dart';
import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/snackbar.dart';
import '../constants/constants.dart';

/// Full-screen signature capture interface for users to draw signatures by hand.
///
/// Allows drawing, clearing, previewing, and saving the signature as a base64-encoded PNG.
/// Returns a map with file name, mime type, and base64 data when the user presses "Done".
/// Used in flows where a digital signature needs to be attached (e.g. delivery receipts, documents).
class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

/// Manages the signature drawing canvas, preview mode, clear/save actions,
/// and proper disposal of the signature controller.
///
/// Features:
///   - Real-time drawing with black pen (width 5)
///   - Clear button while drawing
///   - Preview of saved signature image (with proper aspect-fit scaling)
///   - "Done" button that encodes signature to base64 and returns result
///   - Dark/light theme support
class _SignatureScreenState extends State<SignatureScreen> {
  late final SignatureController _controller;
  ui.Image? _signatureImage;
  bool _isResigning = false;

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

  /// Converts the drawn signature to PNG bytes, encodes it to base64,
  /// generates a timestamp-based filename, and returns the data to the previous screen.
  ///
  /// Shows a warning snackbar if the canvas is empty.
  /// Only called when user presses the "Done" button.
  Future<void> _saveSignature() async {
    if (_controller.isEmpty) {
      CustomSnackbar.showWarning(context, 'Please sign before saving.');
      return;
    }

    final signatureBytes = await _controller.toPngBytes();
    if (signatureBytes != null) {
      final base64Signature = base64Encode(signatureBytes);
      final fileName = 'signature_${DateTime.now().millisecondsSinceEpoch}.png';
      Navigator.pop(context, {
        'fileName': fileName,
        'mimeType': 'image/png',
        'base64': base64Signature,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        leading: IconButton(
          icon: Icon(
            HugeIcons.strokeRoundedArrowLeft01,
            color: isDark ? Colors.white : Colors.black,
            size: 28,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Signature',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black,
            fontSize: 22,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  height: screenSize.height * 0.6,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.grey[800]!
                        : Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: AppStyle.primaryColor.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: _signatureImage != null && !_isResigning
                      ? CustomPaint(
                          painter: _SignaturePainter(_signatureImage!),
                          child: Container(),
                        )
                      : Signature(
                          controller: _controller,
                          backgroundColor: isDark
                              ? Colors.grey[800]!
                              : Colors.white,
                        ),
                ),
                if (_signatureImage == null || _isResigning)
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: () => _controller.clear(),
                      child: Text(
                        'Clear',
                        style: TextStyle(
                          color: isDark
                              ? Colors.white
                              : AppConstants.appBarColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _saveSignature,
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.white : AppStyle.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Done',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.black : Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter that draws a ui.Image (signature) with proper aspect-ratio scaling
/// and centering inside the available container size.
class _SignaturePainter extends CustomPainter {
  final ui.Image image;

  _SignaturePainter(this.image);

  /// Scales and centers the signature image to fit the canvas while preserving aspect ratio.
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();
    final imageAspectRatio = imageWidth / imageHeight;
    final containerAspectRatio = size.width / size.height;

    double scaleFactor;
    Offset offset;

    if (containerAspectRatio > imageAspectRatio) {
      scaleFactor = size.height / imageHeight;
      final scaledImageWidth = imageWidth * scaleFactor;
      final horizontalMargin = (size.width - scaledImageWidth) / 2;
      offset = Offset(horizontalMargin, 0);
    } else {
      scaleFactor = size.width / imageWidth;
      final scaledImageHeight = imageHeight * scaleFactor;
      final verticalMargin = (size.height - scaledImageHeight) / 2;
      offset = Offset(0, verticalMargin);
    }

    canvas.scale(scaleFactor);
    canvas.drawImage(image, offset / scaleFactor, paint);
  }

  /// No repaint needed since the image is static after creation.
  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
