import 'package:flutter/material.dart';
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
    final primary = Theme.of(context).primaryColor;

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
                  color: isDark ? Colors.white : Color(0xff1E1E1E),
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                ),
                // Filter icon as prefix — tappable
                prefixIcon: GestureDetector(
                  onTap: widget.onFilterTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedFilterHorizontal,
                      size: 20,
                      color: widget.hasActiveFilters
                          ? primary
                          : (isDark ? Colors.white : const Color(0xff1E1E1E)),
                    ),
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 48,
                  minHeight: 48,
                ),
                // Clear button when text is present
                suffixIcon: widget.controller.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.close,
                          size: 18,
                          color: isDark ? Colors.grey[400] : Colors.grey[500],
                        ),
                        onPressed: () {
                          widget.controller.clear();
                          widget.onChanged('');
                          setState(() {});
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: primary, width: 1.5),
                ),
                filled: true,
                fillColor: Colors.transparent,
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
