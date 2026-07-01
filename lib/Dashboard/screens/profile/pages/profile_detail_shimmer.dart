import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Shimmer placeholder that mirrors the Profile Details form layout:
///   • Centered 120px circular avatar with a name line below
///   • "Personal Information" section header
///   • 10 form-field rows — each: a label (varying width) above a filled
///     rounded container that holds a leading icon + value line
///
/// Widths, paddings, and radii match the loaded UI so the transition is
/// visually stable. Adapts to dark theme.
class ProfileDetailShimmer extends StatelessWidget {
  const ProfileDetailShimmer({super.key});

  // Label widths approximating each real field's label:
  // Full Name, Email, Phone, Mobile, Website, Job Title, Company,
  // Related Company, Google Maps API Key, Address.
  static const List<double> _labelWidths = [
    80, 50, 50, 55, 65, 65, 75, 130, 155, 65,
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    final placeholderColor = isDark ? Colors.grey[900]! : Colors.white;
    final fieldBg = isDark ? const Color(0xFF2A2A2A) : const Color(0xffF8FAFB);

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      child: Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile image section (matches _buildProfileImageSection)
            Center(
              child: Column(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                        width: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Name placeholder under avatar
                  Container(
                    height: 15,
                    width: 130,
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // "Personal Information" section header
            Container(
              height: 16,
              width: 170,
              decoration: BoxDecoration(
                color: placeholderColor,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 20),
            // 10 field rows, each with its real label width
            for (int i = 0; i < _labelWidths.length; i++)
              _fieldRow(i, _labelWidths[i], placeholderColor, fieldBg),
          ],
        ),
      ),
    );
  }

  Widget _fieldRow(int index, double labelWidth, Color placeholderColor, Color fieldBg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label (fontSize 14, w500 — approximated by a 12h box)
          Container(
            height: 12,
            width: labelWidth,
            decoration: BoxDecoration(
              color: placeholderColor,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 8),
          // Field container — same radius/padding/bg as _buildDisplayField
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: fieldBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // Leading icon slot (20×20 to match real icon size)
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: placeholderColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
