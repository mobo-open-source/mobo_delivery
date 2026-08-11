import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../shared/utils/globals.dart';

/// A flexible, reusable row component for displaying or editing a single form field/value pair.
///
/// Supports two primary modes:
///   1. **Display mode** (`isEditing = false`): Shows label and value as simple text
///   2. **Edit mode** (`isEditing = true`):
///      - Text input (via `TextFormField`) when no `dropdownItems` are provided
///      - Dropdown selection (via `DropdownSearch`) when `dropdownItems` are supplied
///
/// Features:
///   - Dark/light theme adaptation
///   - Optional prefix icon
///   - Read-only text fields with tap callback (e.g. for date picker)
///   - Basic validation (required field message when using dropdown)
///   - Generic type `<T>` for dropdown items (expected to have `id` and `name` fields)
class InfoRow<T> extends StatefulWidget {
  final String label;
  final dynamic value;
  final Color? color;
  final bool isEditing;
  final TextEditingController? controller;
  final VoidCallback? onTap;
  final List<T>? dropdownItems;
  final int? selectedId;
  final Function(T?)? onDropdownChanged;
  final bool readOnly;
  final VoidCallback? onTapEditing;
  final IconData? prefixIcon;
  final String Function(T)? itemAsString;

  const InfoRow({
    Key? key,
    required this.label,
    required this.value,
    this.color,
    required this.isEditing,
    this.controller,
    this.onTap,
    this.dropdownItems,
    this.selectedId,
    this.onDropdownChanged,
    this.readOnly = false,
    this.onTapEditing,
    this.prefixIcon,
    this.itemAsString,
  }) : super(key: key);

  @override
  State<InfoRow<T>> createState() => _InfoRowState<T>();
}

class _InfoRowState<T> extends State<InfoRow<T>> {
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    String displayValue;
    final value = widget.value;
    if (value == null ||
        value == false ||
        (value is String && (value == 'false' || value.trim().isEmpty))) {
      displayValue = "None";
    } else if (value is List && value.length > 1) {
      displayValue = value[1].toString();
    } else {
      displayValue = value.toString();
    }

    final controller = widget.controller;
    if (controller != null) {
      if (controller.text.isEmpty) {
        if (displayValue != "None" && displayValue != "false") {
          controller.text = displayValue;
        }
      } else if (controller.text == "None" || controller.text == "false") {
        controller.text = "";
      }
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: widget.isEditing && !widget.readOnly
          ? (widget.dropdownItems != null
                ? Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: isDark
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFFF2F4F6),
                      border: Border.all(
                        color: _isOpen
                            ? AppStyle.primaryColor
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: DropdownSearch<T>(
                      onBeforePopupOpening: (_) async {
                        setState(() => _isOpen = true);
                        return true;
                      },
                      popupProps: PopupProps.menu(
                        onDismissed: () => setState(() => _isOpen = false),
                        menuProps: MenuProps(
                          backgroundColor: isDark
                              ? Colors.grey[900]
                              : Colors.white,
                          elevation: 8,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        showSearchBox: true,
                        searchFieldProps: TextFieldProps(
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search...',
                            hintStyle: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: isDark ? Colors.white54 : Colors.grey[500],
                              fontStyle: FontStyle.italic,
                            ),
                            prefixIcon: Icon(
                              HugeIcons.strokeRoundedSearch01,
                              size: 20,
                              color: isDark ? Colors.white54 : Colors.grey[500],
                            ),
                            filled: true,
                            fillColor: isDark
                                ? Colors.grey[850]
                                : Colors.grey[100],
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
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
                              borderSide: BorderSide(
                                color: AppStyle.primaryColor,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      items: widget.dropdownItems!,
                      itemAsString:
                          widget.itemAsString ??
                          (item) => (item as dynamic).name ?? '',
                      selectedItem: widget.selectedId != null
                          ? widget.dropdownItems!.firstWhere(
                              (element) =>
                                  (element as dynamic).id == widget.selectedId,
                              orElse: () => null as T,
                            )
                          : null,
                      onChanged: widget.onDropdownChanged,
                      dropdownDecoratorProps: DropDownDecoratorProps(
                        dropdownSearchDecoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          hintText: "Select ${widget.label}",
                          hintStyle: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: isDark ? Colors.white60 : Colors.grey[500],
                          ),
                          prefixIcon: widget.prefixIcon != null
                              ? Icon(
                                  widget.prefixIcon,
                                  size: 20,
                                  color: isDark
                                      ? Colors.white70
                                      : const Color(0xff7F7F7F),
                                )
                              : null,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                      validator: (value) => value == null
                          ? 'Please select ${widget.label}'
                          : null,
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: isDark
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFFF2F4F6),
                      border: Border.all(color: Colors.transparent, width: 1),
                    ),
                    child: TextFormField(
                      controller: controller,
                      readOnly: widget.onTapEditing != null,
                      onTap: widget.onTapEditing,
                      maxLines: widget.label == 'Note' ? 5 : 1,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        hintText: widget.label,
                        hintStyle: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: isDark ? Colors.white38 : Colors.grey[500],
                          fontStyle: FontStyle.italic,
                        ),
                        prefixIcon: widget.prefixIcon != null
                            ? Icon(
                                widget.prefixIcon,
                                color: isDark
                                    ? Colors.white70
                                    : const Color(0xff7F7F7F),
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: isDark
                                ? Colors.white
                                : AppStyle.primaryColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ))
          : Row(
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white60 : const Color(0xff7F7F7F),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    displayValue,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color:
                          widget.color ??
                          (isDark ? Colors.white : Colors.black87),
                    ),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
    );
  }
}
