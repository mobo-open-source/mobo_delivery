import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../models/user.dart';
import 'info_row.dart';

/// Additional information section for the picking creation form.
///
/// Contains two key editable fields:
///   1. Shipping Policy (dropdown: "As soon as possible" vs "When all products are ready")
///   2. Responsible User (dropdown populated from user list)
///
/// Both fields update their respective parent callbacks immediately on change.
/// Designed to be used inside a tab or card in the create-picking flow.
class AdditionalInfo extends StatelessWidget {
  /// Currently selected shipping policy value ('direct' or 'one')
  final String selectedShippingPolicy;

  /// Callback invoked when user changes the shipping policy
  final Function(String) onShippingPolicyChanged;

  /// Full list of available users to assign as responsible
  final List<UserModel> userList;

  /// Currently selected responsible user's ID (nullable)
  final int? selectedUserId;

  /// Callback invoked when user selects a responsible person
  final Function(UserModel?) onUserChanged;

  const AdditionalInfo({
    Key? key,
    required this.selectedShippingPolicy,
    required this.onShippingPolicyChanged,
    required this.userList,
    required this.selectedUserId,
    required this.onUserChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shipping Policy Row
          Text(
            "Shipping Policy ",
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
            child: DropdownButton2<String>(
              value: selectedShippingPolicy,
              isExpanded: true,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'direct',
                  child: Text("When all products are ready"),
                ),
                DropdownMenuItem(
                  value: 'one',
                  child: Text("As soon as possible"),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  onShippingPolicyChanged(value);
                }
              },
              dropdownStyleData: DropdownStyleData(
                maxHeight: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                offset: const Offset(0, -3),
              ),
              underline: const SizedBox(),
            ),
          ),
          const SizedBox(height: 20),

          // Responsible User Row (reuses InfoRow)

          Text(
            'Responsible',
            style: TextStyle(
              fontWeight: FontWeight.w400,
              color: isDark
                  ? Colors.white70
                  : const Color(0xff7F7F7F),
            ),
          ),
          const SizedBox(height: 10),
          InfoRow(
            label: "Responsible",
            value: null,
            isEditing: true,
            prefixIcon: FontAwesomeIcons.user,
            dropdownItems: userList,
            selectedId: selectedUserId,
            onDropdownChanged: onUserChanged,
          ),
        ],
      ),
    );
  }
}
