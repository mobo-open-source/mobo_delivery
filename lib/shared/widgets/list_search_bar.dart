import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hugeicons/hugeicons.dart';

/// A reusable search bar widget matching the mobo_sales quotation list style.
///
/// Features:
/// • Filter icon on the left (opens filter sheet when tapped)
/// • Subtle shadow, no visible border
/// • Active filter/group indicator on the filter button
/// • Optional active filter chips row below the field
class ListSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onFilterTap;
  final bool hasActiveFilters;

  /// If provided, a row of chips for active filters is shown below the field.
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
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  spreadRadius: 1,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GestureDetector(
                      onTap: widget.onFilterTap,
                      child: Container(
                        width: 52,
                        alignment: Alignment.center,
                        // Keep the filter button black (white in dark mode)
                        // regardless of active filters — it must not switch to
                        // the primary color when a filter/search is applied.
                        color: isDark ? Colors.white : Colors.black,
                        child: SvgPicture.asset(
                          'assets/icons/filter.svg',
                          width: 18,
                          height: 15,
                          colorFilter: ColorFilter.mode(
                            isDark ? Colors.black : Colors.white,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
                        onChanged: (v) {
                          widget.onChanged(v);
                          setState(() {});
                        },
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white : const Color(0xff1E1E1E),
                        ),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          hintText: widget.hintText,
                          hintStyle: TextStyle(
                            color: isDark
                                ? Colors.white
                                : const Color(0xff1E1E1E),
                            fontWeight: FontWeight.w400,
                            fontSize: 14,
                          ),
                          suffixIcon: widget.controller.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    HugeIcons.strokeRoundedCancel01,
                                    size: 18,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[500],
                                  ),
                                  onPressed: () {
                                    widget.controller.clear();
                                    widget.onChanged('');
                                    setState(() {});
                                  },
                                )
                              : null,
                          border: const OutlineInputBorder(
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: const OutlineInputBorder(
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.transparent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.activeFiltersRow != null) ...[
            const SizedBox(height: 6),
            widget.activeFiltersRow!,
          ],
        ],
      ),
    );
  }
}
