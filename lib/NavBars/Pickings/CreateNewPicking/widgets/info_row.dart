import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';

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
class InfoRow<T> extends StatelessWidget {
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
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    String displayValue = value?.toString() ?? "None";

    // Auto-populate controller with current display value if empty
    if (controller != null && controller!.text.isEmpty) {
      controller!.text = displayValue;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: isEditing && !readOnly
          ? (dropdownItems != null
                ? Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: isDark
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFFF2F4F6),
                      border: Border.all(color: Colors.transparent, width: 1),
                    ),
                    child: DropdownSearch<T>(
                      popupProps: PopupProps.menu(
                        showSearchBox: true,
                        searchFieldProps: TextFieldProps(
                          decoration: InputDecoration(
                            labelText: "Search",
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white60 : Colors.black87,
                            ),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      items: dropdownItems!,
                      itemAsString: (item) => (item as dynamic).name ?? '',
                      selectedItem: selectedId != null
                          ? dropdownItems!.firstWhere(
                              (element) =>
                                  (element as dynamic).id == selectedId,
                              orElse: () => null as T,
                            )
                          : null,
                      onChanged: onDropdownChanged,
                      dropdownDecoratorProps: DropDownDecoratorProps(
                        dropdownSearchDecoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          hintText: "Select $label",
                          hintStyle: TextStyle(
                            fontWeight: FontWeight.w400,
                            color: isDark ? Colors.white60 : Colors.black87,
                          ),
                          prefixIcon: prefixIcon != null
                              ? Icon(
                            prefixIcon,
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
                      validator: (value) =>
                          value == null ? 'Please select $label' : null,
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
                      readOnly: onTapEditing != null,
                      onTap: onTapEditing,
                      maxLines: label == 'Note' ? 5 : 1,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        hintText: label,
                        hintStyle: label == 'Note'
                            ? TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 20,
                                color: isDark ? Colors.white60 : Colors.black54,
                              )
                            : TextStyle(
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white60 : Colors.black87,
                              ),
                        prefixIcon: prefixIcon != null
                            ? Icon(
                          prefixIcon,
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
          : Text(
              "$label: $displayValue",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color ?? Colors.black87,
                fontSize: 17,
              ),
            ),
    );
  }
}
