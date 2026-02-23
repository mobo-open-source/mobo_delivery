import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// A shimmer loading placeholder specifically designed for the Profile screen.
///
/// Displays animated placeholder shapes that mimic:
///   • Large circular profile avatar
///   • Multiple text/input field placeholders
///   • A larger bottom button-like placeholder (e.g. for Save/Map Token section)
///
/// Automatically adapts colors to light/dark theme.
class ProfileShimmer extends StatelessWidget {
  const ProfileShimmer({super.key});

  /// Reusable shimmer rectangle factory
  Widget _shimmerBox(bool isDark, {double height = 20, double width = double.infinity, double radius = 8}) {
    return Shimmer.fromColors(
      baseColor: isDark ? Color(0xFF2A2A2A) : Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Profile picture placeholder
        Shimmer.fromColors(
          baseColor: isDark ? Color(0xFF2A2A2A) : Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: CircleAvatar(
            radius: 60,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        // fields

        _shimmerBox(isDark,height: 50),
        const SizedBox(height: 12),

        _shimmerBox(isDark,height: 50),
        const SizedBox(height: 12),

        _shimmerBox(isDark,height: 50),
        const SizedBox(height: 12),

        _shimmerBox(isDark,height: 50),
        const SizedBox(height: 12),

        _shimmerBox(isDark,height: 50),
        const SizedBox(height: 20),

        // Map Token field
        _shimmerBox(isDark, height: 45, radius: 12),
      ],
    );
  }
}
