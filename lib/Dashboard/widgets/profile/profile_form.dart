import 'package:flutter/material.dart';

import '../../../shared/utils/globals.dart';

/// A form widget that displays and allows editing of user profile information.
///
/// Shows fields in two modes:
/// - Read-only (default): displays values or "Not set"
/// - Edit mode (`isEdited == true`): shows editable `TextFormField`s for supported fields
class ProfileForm extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final TextEditingController companyController;
  final TextEditingController mobileController;
  final TextEditingController websiteController;
  final TextEditingController jobTitleController;
  final TextEditingController mapTokenController;
  final bool isSystem;
  final bool isEdited;
  final VoidCallback onSave;
  final Function(String) onChanged;
  final bool isOnline;

  const ProfileForm({
    required this.nameController,
    required this.emailController,
    required this.phoneController,
    required this.companyController,
    required this.mobileController,
    required this.websiteController,
    required this.jobTitleController,
    required this.mapTokenController,
    required this.isSystem,
    required this.isEdited,
    required this.onSave,
    required this.onChanged,
    required this.isOnline,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    /// Main column containing all profile information sections
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          "Personal Information",
          style: TextStyle(
            fontSize: 16,
            color: isDark? Colors.white: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        _buildInfoField(context, Icons.person_outline, "Full Name", nameController),
        const SizedBox(height: 8),
        _buildInfoField(context, Icons.email_outlined, "Email", emailController),
        const SizedBox(height: 8),
        _buildInfoField(context, Icons.phone_outlined, "Phone", phoneController),
        const SizedBox(height: 8),
        _buildInfoField(context, Icons.phone_outlined, "Mobile", mobileController),
        const SizedBox(height: 8),
        _buildInfoField(
          context,
          Icons.language_outlined,
          "Website",
          websiteController,
          editable: false,
        ),
        const SizedBox(height: 8),

        _buildInfoField(
          context,
          Icons.work_outline,
          "Job Title",
          jobTitleController,
          editable: false,
        ),
        const SizedBox(height: 8),
        _buildReadOnlyTextField(context, Icons.work_outline, "Company", companyController),
        if (isSystem) ...[
          const SizedBox(height: 8),
          _buildInfoField(context, Icons.language_outlined, "Google Maps API Key", mapTokenController),
        ],
      ],
    );
  }

  /// Builds a single profile information field.
  ///
  /// Displays either:
  /// - A read-only styled container with icon + text (default)
  /// - An editable TextFormField (when isEdited == true and editable == true)
  Widget _buildInfoField(
      BuildContext context,
      IconData icon,
      String label,
      TextEditingController controller, {
        bool editable = true,
      }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayValue = controller.text.isEmpty ? "Not set" : controller.text;

    if (isEdited && editable) {
      /// Edit mode: TextFormField with input decoration
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: TextStyle(fontWeight: FontWeight.w400).fontFamily,
              color: isDark ? Colors.white70 : const Color(0xff7F7F7F),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isDark ? const Color(0xFF2A2A2A) : const Color(0xffF8FAFB),
              border: Border.all(color: Colors.transparent, width: 1),
            ),
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: TextFormField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                hintText: controller.text.isEmpty ? 'Enter $label' : null,
                hintStyle: TextStyle(
                  fontFamily: TextStyle(fontWeight: FontWeight.w600).fontFamily,
                  color: isDark ? Colors.grey[500] : Colors.grey[500],
                  fontStyle: FontStyle.italic,
                  fontSize: 14,
                  height: 1.0,
                ),
                prefixIcon: Icon(icon, color: isDark ? Colors.white70 : const Color(0xff7F7F7F)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.transparent, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppStyle.primaryColor, width: 2),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      /// Read-only mode: styled container with icon and text
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: TextStyle(fontWeight: FontWeight.w400).fontFamily,
              color: isDark ? Colors.white70 : const Color(0xff7F7F7F),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isDark ? const Color(0xFF2A2A2A) : const Color(0xffF8FAFB),
              border: Border.all(color: Colors.transparent, width: 1),
            ),
            child: Row(
              children: [
                Icon(icon, color: isDark ? Colors.white70 : const Color(0xff7F7F7F), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    displayValue,
                    style: TextStyle(
                      fontSize: 15,
                      color: displayValue == 'Not set'
                          ? (isDark ? Colors.grey[500]! : Colors.grey[500]!)
                          : (isDark ? Colors.white70 : Colors.black),
                      fontWeight: displayValue == 'Not set' ? FontWeight.w400 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
  }

  /// Convenience wrapper that creates a non-editable info field.
  ///
  /// Delegates directly to [_buildInfoField] with editable: false.
  Widget _buildReadOnlyTextField(
      BuildContext context,
      IconData icon,
      String label,
      TextEditingController controller,
      ) {
    return _buildInfoField(context, icon, label, controller, editable: false);
  }
}
