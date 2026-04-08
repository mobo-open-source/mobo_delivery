import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

enum ShimmerType { standard, simple, product, search, settings, profile, form }

/// A utility class for building complex shimmer loading effects for lists and grids.
class ListShimmer {
  static Widget buildListItemShimmer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    final cardBg = isDark ? Colors.grey[850]! : Colors.white;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withOpacity(0.3)
                  : Colors.black.withOpacity(0.05),
              blurRadius: 4,
              spreadRadius: 1,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 18,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 220,
                    height: 16,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 140,
                    height: 14,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),

            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 70,
                  height: 24,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 90,
                  height: 18,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget buildSimpleListItemShimmer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    final cardBg = isDark ? Colors.grey[850]! : Colors.white;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 180,
                    height: 14,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget buildProductListItemShimmer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    final cardBg = isDark ? Colors.grey[850]! : Colors.white;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 18,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 140,
                    height: 16,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 100,
                    height: 14,
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 80,
                  height: 18,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 60,
                  height: 16,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget buildListShimmer(
    BuildContext context, {
    int itemCount = 8,
    ShimmerType type = ShimmerType.standard,
  }) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        switch (type) {
          case ShimmerType.product:
            return buildProductListItemShimmer(context);
          case ShimmerType.simple:
            return buildSimpleListItemShimmer(context);
          case ShimmerType.standard:
          default:
            return buildListItemShimmer(context);
        }
      },
    );
  }

  static Widget buildGroupedListShimmer(
    BuildContext context, {
    int groupCount = 3,
    int itemsPerGroup = 3,
    ShimmerType type = ShimmerType.standard,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return Column(
      children: List.generate(groupCount, (groupIndex) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Shimmer.fromColors(
                baseColor: base,
                highlightColor: highlight,
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: base,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 150,
                      height: 18,
                      decoration: BoxDecoration(
                        color: base,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 30,
                      height: 16,
                      decoration: BoxDecoration(
                        color: base,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            ...List.generate(itemsPerGroup, (itemIndex) {
              switch (type) {
                case ShimmerType.product:
                  return buildProductListItemShimmer(context);
                case ShimmerType.simple:
                  return buildSimpleListItemShimmer(context);
                case ShimmerType.standard:
                default:
                  return buildListItemShimmer(context);
              }
            }),
            const SizedBox(height: 16),
          ],
        );
      }),
    );
  }
}
