import 'package:flutter/material.dart';
import 'package:dropdown_search/dropdown_search.dart';

import '../../../../shared/utils/globals.dart';

/// Reusable row widget for displaying and editing picking form fields.
///
/// Displays a label + value pair in view mode, and switches to:
/// - DropdownSearch (when `dropdownItems` is provided)
/// - TextFormField (text/date/note input)
///
/// Features:
/// • Dark/light theme support with consistent styling
/// • Prefix icons (e.g. calendar, location, note)
/// • Color customization for specific fields (e.g. overdue dates)
/// • Read-only mode support
/// • GestureDetector tap handling in view mode
/// • Automatic controller text sync in non-editing mode
///
/// Used extensively in `PickingDetailsPage` for partner, dates, origin, note, etc.
class InfoRow extends StatelessWidget {
  final String label;
  final dynamic value;
  final Color? color;
  final bool isEditing;
  final TextEditingController? controller;
  final VoidCallback? onTap;
  final List<Map<String, dynamic>>? dropdownItems;
  final int? selectedId;
  final Function(Map<String, dynamic>?)? onDropdownChanged;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ───────────────────────────────────────────────
    //  Display value normalization logic
    // ───────────────────────────────────────────────
    String displayValue;
    if (label == 'Note' && value is String) {
      // Strip HTML tags from notes (Odoo often sends formatted text)
      displayValue = value.replaceAll(RegExp(r'<[^>]*>'), '');
    } else if (value is List && value.length > 1) {
      // Many2one fields → take display name (index 1)
      displayValue = value[1].toString();
    } else if (value == null ||
        value == false ||
        value == 'false' ||
        (value is String && value.trim().isEmpty)) {
      displayValue = "None";
    } else {
      displayValue = value.toString();
    }

    // Sync controller text when not editing (prevents stale values)
    if (!isEditing && controller != null && controller!.text != displayValue) {
      controller!.text = displayValue;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: isEditing && !readOnly
          /// Builds the dropdown widget when `dropdownItems` are provided
          ? (dropdownItems != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w400,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xff7F7F7F),
                        ),
                      ),

                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: isDark
                              ? const Color(0xFF2A2A2A)
                              : const Color(0xFFF2F4F6),
                          border: Border.all(
                            color: Colors.transparent,
                            width: 1,
                          ),
                        ),
                        child: DropdownSearch<Map<String, dynamic>>(
                          popupProps: PopupProps.menu(
                            showSearchBox: true,
                            searchFieldProps: TextFieldProps(
                              decoration: InputDecoration(
                                labelText: "Search",
                                labelStyle: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black87,
                                ),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          items: dropdownItems!,
                          itemAsString: (item) => item?['name'] ?? '',
                          selectedItem: dropdownItems!.firstWhere(
                            (element) => element['id'] == selectedId,
                            orElse: () => {'id': null, 'name': 'None'},
                          ),
                          onChanged: onDropdownChanged,
                          dropdownDecoratorProps: DropDownDecoratorProps(
                            dropdownSearchDecoration: InputDecoration(
                              hintText: "Select $label",
                              hintStyle: TextStyle(
                                fontWeight: FontWeight.w400,
                                color: isDark
                                    ? Colors.white54
                                    : Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
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
                      ),
                    ],
                  )
                /// Builds the text input field (for dates, origin, note, etc.)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontWeight: FontWeight.w400,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xff7F7F7F),
                        ),
                      ),

                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: isDark
                              ? const Color(0xFF2A2A2A)
                              : const Color(0xFFF2F4F6),
                          border: Border.all(
                            color: Colors.transparent,
                            width: 1,
                          ),
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
                            hintStyle: TextStyle(
                              fontWeight: FontWeight.w400,
                              color: isDark ? Colors.white54 : Colors.grey[600],
                              fontStyle: FontStyle.italic,
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
                          onChanged: (value) {
                            if (label == 'Note') {}
                          },
                        ),
                      ),
                    ],
                  ))
          /// Builds the read-only view mode (label + tappable value)
          : GestureDetector(
              onTap: onTap,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      displayValue,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontWeight: FontWeight.normal,
                        color: isDark
                            ? Colors.white60
                            : color ?? Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
