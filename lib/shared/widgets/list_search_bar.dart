import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hugeicons/hugeicons.dart' show HugeIcons;

/// Search + filter row used across every list-view page (Pickings, Returns,
/// Documents).
///
/// Matches the Mobo design: two separate boxes side by side — an expanded
/// search field on the left (magnifying-glass prefix, optional clear suffix)
/// and a fixed 40×40 filter button on the right (`new_filter.svg`). Both
/// share the same 12-radius corners, white surface, and the exact drop-shadow
/// values from the design (X 3, Y 11, blur 8.5, spread -3, black @ 4%). Dark
/// mode swaps to `Colors.grey[850]` to match the app's other card surfaces.
class ListSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onFilterTap;
  final bool hasActiveFilters;

  /// If provided, a row of chips for active filters is shown below the row.
  final Widget? activeFiltersRow;

  const ListSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.onFilterTap,
    this.hasActiveFilters = false,
    this.activeFiltersRow,
  });

  @override
  State<ListSearchBar> createState() => _ListSearchBarState();
}

class _ListSearchBarState extends State<ListSearchBar> {
  /// Design drop-shadow (Figma): X 3, Y 11, blur 8.5, spread -3, black @ 4%.
  static final List<BoxShadow> _designShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      offset: const Offset(3, 11),
      blurRadius: 8.5,
      spreadRadius: -3,
    ),
  ];

  static const double _height = 48;
  static const double _radius = 12;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? Colors.grey[850]! : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xff1E1E1E);
    // Figma spec: hint text is #99A1AF. Dark mode lifts it to white-@-55%
    // so it stays visible on the grey[850] surface.
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : const Color(0xFF99A1AF);
    // Search icon + hint text share the muted #99A1AF tone in light mode
    // (Figma spec); dark mode lifts to a translucent white for visibility.
    final iconColor = isDark
        ? Colors.white.withValues(alpha: 0.70)
        : const Color(0xFF99A1AF);
    // Filter icon renders in its Figma stroke color (#1A1A1A) so the glyph
    // reads as designed; dark mode flips to plain white.
    final filterIconColor = isDark ? Colors.white : const Color(0xFF1A1A1A);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSearchField(
                  surface,
                  textColor,
                  hintColor,
                  iconColor,
                ),
              ),
              const SizedBox(width: 10),
              _buildFilterButton(surface, filterIconColor),
            ],
          ),
          if (widget.activeFiltersRow != null) ...[
            const SizedBox(height: 6),
            widget.activeFiltersRow!,
          ],
        ],
      ),
    );
  }

  Widget _buildSearchField(
    Color surface,
    Color textColor,
    Color hintColor,
    Color iconColor,
  ) {
    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: _designShadow,
      ),
      child: TextField(
        controller: widget.controller,
        onChanged: (v) {
          widget.onChanged(v);
          setState(() {});
        },
        style: TextStyle(fontSize: 14, color: textColor),
        decoration: InputDecoration(
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 14,
          ),
          hintText: widget.hintText,
          hintStyle: TextStyle(
            color: hintColor,
            fontWeight: FontWeight.w400,
            fontSize: 14,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 14, right: 8),
            child: SvgPicture.asset(
              'assets/icons/search.svg',
              width: 20,
              height: 20,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
          suffixIcon: widget.controller.text.isNotEmpty
              ? IconButton(
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    HugeIcons.strokeRoundedCancel01,
                    size: 18,
                    color: iconColor,
                  ),
                  onPressed: () {
                    widget.controller.clear();
                    widget.onChanged('');
                    setState(() {});
                  },
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 40,
            minHeight: 40,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        ),
      ),
    );
  }

  Widget _buildFilterButton(Color surface, Color iconColor) {
    // Same height and shadow as the search field so both boxes align
    // top-and-bottom on a single horizontal line, per the Figma design.
    return Container(
      width: _height,
      height: _height,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: _designShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_radius),
          onTap: widget.onFilterTap,
          child: Center(
            child: SvgPicture.asset(
              'assets/icons/new_filter.svg',
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            ),
          ),
        ),
      ),
    );
  }
}
