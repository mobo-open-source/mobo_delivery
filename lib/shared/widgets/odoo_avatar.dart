import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hugeicons/hugeicons.dart';

/// A specialized avatar widget that handles Odoo user profile images, including base64 decoding and fallbacks.
class OdooAvatar extends StatelessWidget {
  final String? imageBase64;
  final Uint8List? imageBytes;
  final double size;
  final double iconSize;
  final BoxFit fit;
  final Color? placeholderColor;
  final Color? iconColor;
  final BorderRadius? borderRadius;
  final dynamic fallbackIcon;

  const OdooAvatar({
    super.key,
    this.imageBase64,
    this.imageBytes,
    this.size = 40.0,
    this.iconSize = 20.0,
    this.fit = BoxFit.cover,
    this.placeholderColor,
    this.iconColor,
    this.borderRadius,
    this.fallbackIcon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectivePlaceholderColor =
        placeholderColor ?? (isDark ? Colors.grey[700] : Colors.grey[100]);
    final effectiveIconColor =
        iconColor ?? (isDark ? Colors.grey[400] : Colors.grey[600]);

    Widget content;

    if (imageBytes != null && imageBytes!.isNotEmpty) {
      content = _buildImageFromBytes(
        imageBytes!,
        effectivePlaceholderColor!,
        effectiveIconColor!,
      );
    } else if (imageBase64 != null &&
        imageBase64!.isNotEmpty &&
        imageBase64 != 'false') {
      try {
        final cleanedBase64 = imageBase64!.replaceAll(RegExp(r'\s+'), '');
        final decodedBytes = const Base64Decoder().convert(cleanedBase64);
        content = _buildImageFromBytes(
          decodedBytes,
          effectivePlaceholderColor!,
          effectiveIconColor!,
        );
      } catch (e) {
        content = _buildPlaceholder(
          effectivePlaceholderColor!,
          effectiveIconColor!,
        );
      }
    } else {
      content = _buildPlaceholder(
        effectivePlaceholderColor!,
        effectiveIconColor!,
      );
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: content);
    }
    return content;
  }

  Widget _buildImageFromBytes(
    Uint8List bytes,
    Color placeholderColor,
    Color iconColor,
  ) {
    bool isSvg = false;
    if (bytes.length > 10) {
      try {
        final head = utf8.decode(
          bytes.sublist(0, math.min(100, bytes.length)),
          allowMalformed: true,
        );
        if (head.contains('<svg')) {
          isSvg = true;
        }
      } catch (_) {}
    }

    if (isSvg) {
      return SvgPicture.memory(
        bytes,
        width: size,
        height: size,
        fit: fit,
        placeholderBuilder: (context) =>
            _buildPlaceholder(placeholderColor, iconColor),
      );
    } else {
      return Image.memory(
        bytes,
        width: size,
        height: size,
        fit: fit,
        errorBuilder: (context, error, stackTrace) =>
            _buildPlaceholder(placeholderColor, iconColor),
      );
    }
  }

  Widget _buildPlaceholder(Color color, Color iconColor) {
    return Container(
      width: size,
      height: size,
      color: color,
      child: Center(
        child: Icon(
          fallbackIcon ?? HugeIcons.strokeRoundedUser,
          size: iconSize,
          color: iconColor,
        ),
      ),
    );
  }
}
