import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// A shimmering placeholder widget that mimics a list of picking/transfer cards
/// during loading states (e.g. initial fetch, refresh, or pagination).
///
/// Displays 20 fake card-like items with animated shimmer effect,
/// adapting automatically to light/dark theme.
///
/// Features:
/// • Card layout with rounded corners and margin
/// • Placeholder rectangles for title, subtitle, and trailing badge
/// • Smooth shimmer animation using `Shimmer.fromColors`
/// • Safe color handling for dark/light modes
///
/// Typically used as a loading indicator in `PickingsGroupedPage` or similar list views.
class GridViewShimmer extends StatelessWidget {
  const GridViewShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      itemCount: 20,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          // Base & highlight colors optimized for both themes
          baseColor: isDark ? Color(0xFF2A2A2A) : Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              // Title placeholder (e.g. picking reference)
              title: Container(
                height: 16,
                width: 100,
                color: Colors.white,
              ),
              // Subtitle placeholder (e.g. scheduled date / partner)
              subtitle: Container(
                margin: const EdgeInsets.only(top: 8),
                height: 14,
                width: 150,
                color: Colors.white,
              ),
              // Trailing placeholder (e.g. state badge or count)
              trailing: Container(
                height: 20,
                width: 60,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }
}
