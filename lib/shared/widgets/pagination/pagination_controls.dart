import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

/// A standard UI component for navigating through paginated data sets.
class PaginationControls extends StatelessWidget {
  final bool canGoToPreviousPage;
  final bool canGoToNextPage;
  final VoidCallback onPreviousPage;
  final VoidCallback onNextPage;
  final String paginationText;
  final bool isDark;
  final ThemeData theme;

  const PaginationControls({
    super.key,
    required this.canGoToPreviousPage,
    required this.canGoToNextPage,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.paginationText,
    required this.isDark,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final Color disabled = isDark
        ? Colors.white.withOpacity(0.28)
        : Colors.black.withOpacity(0.28);
    final Color iconActive = theme.primaryColor;
    final Color iconInactive = disabled;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 7),
          decoration: BoxDecoration(),
          child: Text(
            paginationText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: isDark
                  ? Colors.white.withOpacity(0.9)
                  : const Color(0xFF4B5563),
            ),
          ),
        ),

        if (canGoToNextPage) ...[
          const SizedBox(width: 12),

          InkWell(
            onTap: canGoToPreviousPage ? onPreviousPage : null,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                HugeIcons.strokeRoundedArrowLeft01,
                size: 20,
                color: canGoToPreviousPage ? iconActive : iconInactive,
              ),
            ),
          ),

          const SizedBox(width: 6),

          InkWell(
            onTap: onNextPage,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                HugeIcons.strokeRoundedArrowRight01,
                size: 20,
                color: iconActive,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
