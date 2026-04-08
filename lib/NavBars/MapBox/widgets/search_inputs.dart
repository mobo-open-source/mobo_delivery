import 'package:flutter/material.dart';

/// Compact route input card shown over the map while planning a route.
///
/// Uses a white/surface card with a timeline-style indicator column on the left
/// (blue dot → vertical line → orange pin) connecting source and stop fields.
/// Adapts for light/dark theme.
class SearchInputs extends StatelessWidget {
  final TextEditingController sourceController;
  final List<TextEditingController> stopControllers;
  final bool showStopFields;

  const SearchInputs({
    super.key,
    required this.sourceController,
    required this.stopControllers,
    required this.showStopFields,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1C1C2E) : Colors.white;
    final primary = isDark ? Colors.white : const Color(0xFF202124);
    final hint = isDark ? const Color(0xFF888888) : const Color(0xFF9AA0A6);
    final divider = isDark ? Colors.white12 : const Color(0xFFEEEEEE);

    // Only non-empty stops get rendered rows
    final activeStops = showStopFields
        ? stopControllers
            .asMap()
            .entries
            .where((e) => e.value.text.trim().isNotEmpty)
            .toList()
        : <MapEntry<int, TextEditingController>>[];

    final rowCount = 1 + activeStops.length; // source + active stops

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Timeline indicator column ──────────────────────────────────
            SizedBox(
              width: 22,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(rowCount * 2 - 1, (i) {
                  if (i.isEven) {
                    // Dot
                    final dotIndex = i ~/ 2;
                    final isSource = dotIndex == 0;
                    final isLast = dotIndex == rowCount - 1;
                    return Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isLast
                            ? const Color(0xFFE74C3C)
                            : isSource
                                ? const Color(0xFF4285F4)
                                : const Color(0xFFF39C12),
                        shape: isSource ? BoxShape.circle : BoxShape.rectangle,
                        borderRadius:
                            isSource ? null : BorderRadius.circular(3),
                        border: Border.all(color: Colors.white, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    );
                  } else {
                    // Connector line
                    return Expanded(
                      child: Center(
                        child: Container(
                          width: 2,
                          color: divider,
                        ),
                      ),
                    );
                  }
                }),
              ),
            ),
            const SizedBox(width: 10),

            // ── Input fields ───────────────────────────────────────────────
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Source field
                  _buildField(
                    controller: sourceController,
                    hint: 'My location',
                    primary: primary,
                    hint2: hint,
                  ),

                  // Stop fields
                  ...activeStops.map((entry) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Divider(height: 1, color: divider),
                        _buildField(
                          controller: entry.value,
                          hint: 'Stop ${entry.key + 1}',
                          primary: primary,
                          hint2: hint,
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required Color primary,
    required Color hint2,
  }) {
    return TextField(
      controller: controller,
      readOnly: true,
      style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: hint2),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }
}
