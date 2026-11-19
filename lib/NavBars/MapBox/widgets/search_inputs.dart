import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

/// Compact route input card shown over the map while planning a route.
///
/// Uses a white/surface card with a timeline-style indicator column on the left
/// (blue dot → vertical line → orange pin) connecting source and stop fields.
/// An optional [onClose] renders a dismiss button in the top-right of the card.
/// Adapts for light/dark theme.
class SearchInputs extends StatelessWidget {
  final TextEditingController sourceController;
  final List<TextEditingController> stopControllers;
  final bool showStopFields;

  /// If provided, a close button is shown inside the top-right of the card.
  final VoidCallback? onClose;

  /// If provided, an edit button sits beside the close button and reopens
  /// the route sheet with every stop editable. The rows themselves stay
  /// read-only: they don't look tappable, so they shouldn't act it.
  final VoidCallback? onEdit;

  const SearchInputs({
    super.key,
    required this.sourceController,
    required this.stopControllers,
    required this.showStopFields,
    this.onClose,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1C1C2E) : Colors.white;
    final primary = isDark ? Colors.white : const Color(0xFF202124);
    final hint = isDark ? const Color(0xFF888888) : const Color(0xFF9AA0A6);
    final divider = isDark ? Colors.white12 : const Color(0xFFEEEEEE);

    final activeStops = showStopFields
        ? stopControllers
              .asMap()
              .entries
              .where((e) => e.value.text.trim().isNotEmpty)
              .toList()
        : <MapEntry<int, TextEditingController>>[];

    final rowCount = 1 + activeStops.length;

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
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 22,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(rowCount * 2 - 1, (i) {
                  if (i.isEven) {
                    final dotIndex = i ~/ 2;
                    final isSource = dotIndex == 0;
                    final isLast = dotIndex == rowCount - 1;
                    return Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        // Source is always the blue GPS dot — it is never the
                        // destination, even when it is the only row (no stops
                        // resolved yet). Checking `isLast` first would paint a
                        // lone source dot red.
                        color: isSource
                            ? const Color(0xFF4285F4)
                            : isLast
                            ? const Color(0xFFE74C3C)
                            : const Color(0xFFF39C12),
                        shape: isSource ? BoxShape.circle : BoxShape.rectangle,
                        borderRadius: isSource
                            ? null
                            : BorderRadius.circular(3),
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
                    return Expanded(
                      child: Center(child: Container(width: 2, color: divider)),
                    );
                  }
                }),
              ),
            ),
            const SizedBox(width: 10),

            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  sourceController.text == 'Your Location'
                      ? _buildYourLocationRow()
                      : _buildField(
                          controller: sourceController,
                          hint: 'My location',
                          primary: primary,
                          hint2: hint,
                        ),

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

            if (onEdit != null || onClose != null) ...[
              const SizedBox(width: 4),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onClose != null)
                    _CardIconButton(
                      icon: HugeIcons.strokeRoundedCancel01,
                      tooltip: 'Close route',
                      onTap: onClose!,
                      isDark: isDark,
                    ),
                  if (onEdit != null)
                    _CardIconButton(
                      icon: HugeIcons.strokeRoundedPencilEdit02,
                      tooltip: 'Edit stops',
                      onTap: onEdit!,
                      isDark: isDark,
                    ),
                ],
              ),
            ],
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
      style: TextStyle(
        fontSize: 13,
        color: primary,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: hint2),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }

  /// "Your location" label for the source row.
  ///
  /// Deliberately has no dot of its own — the timeline indicator column on the
  /// left already renders the blue source dot, so drawing another here would
  /// show two dots side by side.
  Widget _buildYourLocationRow() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Your location',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF4285F4),
          ),
        ),
      ),
    );
  }
}

/// A 36×36 icon button for the card's corner actions (the guide's minimum
/// tap target), with a tooltip so the glyph is never the only label.
class _CardIconButton extends StatelessWidget {
  const _CardIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.isDark,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 18,
            color: isDark ? Colors.white54 : const Color(0xFF70757A),
          ),
        ),
      ),
    );
  }
}
