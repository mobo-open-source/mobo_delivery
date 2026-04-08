import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../../shared/widgets/toggles/mobo_toggle.dart';

/// A settings list tile with an animated toggle switch.
class SwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final dynamic icon;
  final bool value;
  final Function(bool)? onChanged;

  const SwitchTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      leading: icon is IconData
          ? Icon(icon, color: isDark ? Colors.grey[400] : Colors.grey[600])
          : HugeIcon(
              icon: icon,
              color: isDark ? Colors.grey[400]! : Colors.grey[600]!,
            ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 13,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
      trailing: MoboToggle(value: value, onChanged: onChanged),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
