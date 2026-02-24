import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/utils/globals.dart';
import '../../../shared/widgets/snackbar.dart';

/// Circular profile image display with edit functionality.
///
/// Shows a large circular avatar with:
/// - User's profile photo (from base64 string) if available and valid
/// - Default person icon if no valid image
/// - Camera button overlay when in edit mode
///
/// Allows picking a new image from camera or gallery when edited.
class ProfileImage extends StatefulWidget {
  final String? imagePath;
  final ValueChanged<String> onImageChanged;
  final bool isEdited;

  const ProfileImage({
    super.key,
    required this.imagePath,
    required this.onImageChanged,
    required this.isEdited,
  });
  @override
  State<ProfileImage> createState() => _ProfileImageState();
}

class _ProfileImageState extends State<ProfileImage> {
  final _picker = ImagePicker();
  String? base64Image;

  /// Checks if a string is a valid base64-encoded image data
  bool _isValidBase64(String value) {
    if (value.toLowerCase() == "false" || value.isEmpty) return false;

    try {
      base64Decode(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    /// Main profile avatar with optional edit overlay
    return GestureDetector(
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          CircleAvatar(
            radius: 60,
            backgroundImage: (widget.imagePath != null && _isValidBase64(widget.imagePath!))
                ? MemoryImage(base64Decode(widget.imagePath!))
                : null,
            child: (widget.imagePath == null || !_isValidBase64(widget.imagePath!))
                ? const Icon(Icons.account_circle, size: 80, color: const Color(0xFF263238),)
                : null,
          ),
          if (widget.isEdited)
            Positioned(
              child: InkWell(
                onTap:
                _showImageSourceActionSheet,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppStyle.primaryColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark
                          ? Colors.grey[900]!
                          : Colors.white,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    HugeIcons.strokeRoundedCamera02,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Shows bottom sheet with options: Take Photo or Choose from Gallery
  void _showImageSourceActionSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[700] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _pickImageFromSource(ImageSource.camera);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      HugeIcons.strokeRoundedCamera02,
                      size: 24,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Take Photo',
                      style: GoogleFonts.manrope(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: isDark ? Colors.grey[800] : Colors.grey[200],
            ),
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _pickImageFromSource(ImageSource.gallery);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      HugeIcons.strokeRoundedImageCrop,
                      size: 24,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Choose from Gallery',
                      style: GoogleFonts.manrope(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Picks image from camera or gallery, converts to base64, and notifies parent
  Future<void> _pickImageFromSource(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 600,
      );
      if (picked == null || !mounted) return;

      final bytes = await picked.readAsBytes();
      final base64String = base64Encode(bytes);

      setState(() {
        base64Image = base64String;
      });
      widget.onImageChanged(base64String);
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Failed to update image: $e');
      }
    }
  }

  /// Displays error message using custom snackbar
  void _showErrorSnackBar(String msg) {
    CustomSnackbar.showError(context, msg);
   }
}
