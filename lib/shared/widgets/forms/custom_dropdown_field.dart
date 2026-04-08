import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A specialized dropdown field specifically for string values, featuring a label and optional border.
class CustomDropdownField extends StatelessWidget {
  final String? value;
  final String labelText;
  final String? hintText;
  final ValueChanged<String?>? onChanged;
  final String? Function(String?)? validator;
  final bool isDark;
  final List<DropdownMenuItem<String>> items;
  final bool showBorder;

  const CustomDropdownField({
    required this.value,
    required this.labelText,
    required this.onChanged,
    this.validator,
    required this.items,
    this.hintText,
    this.isDark = false,
    this.showBorder = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w500,
            fontSize: 13,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          hint: hintText != null
              ? Text(
                  hintText!,
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w400,
                    color: isDark ? Colors.white38 : Colors.grey[400],
                    fontStyle: FontStyle.italic,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: showBorder ? _getBorderColor() : Colors.transparent,
                width: showBorder ? 1.5 : 0,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).primaryColor,
                width: showBorder ? 1.5 : 0,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: showBorder ? _getBorderColor() : Colors.transparent,
                width: showBorder ? 1 : 0,
              ),
            ),
            filled: true,
            fillColor: isDark
                ? const Color(0xFF1E1E1E)
                : const Color(0xffF8FAFB),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: isDark ? Colors.white : Colors.black,
          ),
          dropdownColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          items: items,
          onChanged: onChanged,
          validator: validator,
        ),
      ],
    );
  }

  Color _getBorderColor() {
    return isDark ? Colors.grey[700]! : Colors.grey[300]!;
  }
}
