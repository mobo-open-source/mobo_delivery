import 'package:flutter/material.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:hugeicons/hugeicons.dart';

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
class InfoRow extends StatefulWidget {
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
  State<InfoRow> createState() => _InfoRowState();
}

class _InfoRowState extends State<InfoRow> {
  bool _isOpen = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String displayValue;
    if (widget.label == 'Note' && widget.value is String) {
      displayValue = widget.value.replaceAll(RegExp(r'<[^>]*>'), '');
    } else if (widget.value is List && widget.value.length > 1) {
      displayValue = widget.value[1].toString();
    } else if (widget.value == null ||
        widget.value == false ||
        widget.value == 'false' ||
        (widget.value is String && widget.value.trim().isEmpty)) {
      displayValue = "None";
    } else {
      displayValue = widget.value.toString();
    }

    if (widget.isEditing && widget.controller != null) {
      if (widget.controller!.text == "None" || widget.controller!.text == "false") {
        widget.controller!.text = "";
      }
    } else if (!widget.isEditing && widget.controller != null && widget.controller!.text != displayValue) {
      widget.controller!.text = displayValue;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: widget.isEditing && !widget.readOnly
          /// Builds the dropdown widget when `dropdownItems` are provided
          ? (widget.dropdownItems != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 14,
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
                            color: _isOpen
                                ? AppStyle.primaryColor
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: DropdownSearch<Map<String, dynamic>>(
                          onBeforePopupOpening: (_) async {
                            setState(() => _isOpen = true);
                            return true;
                          },
                          popupProps: PopupProps.menu(
                            onDismissed: () => setState(() => _isOpen = false),
                            menuProps: MenuProps(
                              backgroundColor:
                                  isDark ? Colors.grey[900] : Colors.white,
                              elevation: 8,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            showSearchBox: true,
                            searchFieldProps: TextFieldProps(
                              decoration: InputDecoration(
                                hintText: 'Search...',
                                hintStyle: TextStyle(
                                  fontWeight: FontWeight.w400,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.grey[500],
                                  fontStyle: FontStyle.italic,
                                ),
                                prefixIcon: Icon(
                                  HugeIcons.strokeRoundedSearch01,
                                  size: 20,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.grey[500],
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
                          itemAsString: (item) => item?['name'] ?? '',
                          selectedItem: widget.dropdownItems!.firstWhere(
                            (element) => element['id'] == widget.selectedId,
                            orElse: () => {'id': null, 'name': 'None'},
                          ),
                          onChanged: widget.onDropdownChanged,
                          dropdownDecoratorProps: DropDownDecoratorProps(
                            dropdownSearchDecoration: InputDecoration(
                              hintText: "Select ${widget.label}",
                              hintStyle: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: isDark
                                    ? Colors.white54
                                    : Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
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
                          validator: (value) =>
                              value == null ? 'Please select ${widget.label}' : null,
                        ),
                      ),
                    ],
                  )
                /// Builds the text input field (for dates, origin, note, etc.)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 14,
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
                          controller: widget.controller,
                          readOnly: widget.onTapEditing != null,
                          onTap: widget.onTapEditing,
                          maxLines: widget.label == 'Note' ? 5 : 1,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            hintText: widget.label,
                            hintStyle: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: isDark ? Colors.white54 : Colors.grey[600],
                              fontStyle: FontStyle.italic,
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
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: isDark
                                    ? Colors.white
                                    : AppStyle.primaryColor,
                                width: 2,
                              ),
                            ),
                          ),
                          onChanged: (value) {
                            if (widget.label == 'Note') {}
                          },
                        ),
                      ),
                    ],
                  ))
          /// Builds the read-only view mode (label + tappable value)
          : GestureDetector(
              onTap: widget.onTap,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.label,
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
                            : widget.color ?? Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
