import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A standard, themed text input field used consistently across the application's forms.
class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final String? Function(String?)? validator;
  final bool isDark;
  final bool showBorder;
  final TextInputType? keyboardType;
  final int? maxLines;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final bool readOnly;

  const CustomTextField({
    required this.controller,
    required this.labelText,
    this.hintText,
    this.validator,
    this.isDark = false,
    this.showBorder = false,
    this.keyboardType,
    this.maxLines = 1,
    this.suffixIcon,
    this.onChanged,
    this.readOnly = false,
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
        TextFormField(
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: isDark ? Colors.white : Colors.black,
          ),
          controller: controller,
          onChanged: onChanged,
          readOnly: readOnly,
          keyboardType: keyboardType ?? TextInputType.text,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: GoogleFonts.manrope(
              fontWeight: FontWeight.w400,
              color: isDark ? Colors.white38 : Colors.grey[400],
              fontStyle: FontStyle.italic,
              fontSize: 14,
            ),
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: showBorder ? _getBorderColor() : Colors.transparent,
                width: 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: showBorder
                    ? (isDark ? Colors.grey[700]! : Colors.grey[300]!)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).primaryColor,
                width: 1.5,
              ),
            ),
            filled: true,
            fillColor: isDark
                ? const Color(0xFF1E1E1E)
                : const Color(0xffF8FAFB),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          validator: validator,
        ),
      ],
    );
  }

  Color _getBorderColor() {
    return isDark ? Colors.grey[700]! : Colors.grey[300]!;
  }
}
