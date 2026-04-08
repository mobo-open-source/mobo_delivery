import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

/// A settings list tile with an Odoo-backed dropdown.
///
/// Shows a loading spinner while options are being fetched,
/// and displays a "last updated" timestamp below the subtitle.
class OdooDropdownTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final dynamic icon;
  final String? selectedValue;
  final List<Map<String, dynamic>> options;
  final bool isLoading;
  final Function(String?) onChanged;
  final String displayKey;
  final String valueKey;
  final DateTime? lastUpdated;

  const OdooDropdownTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selectedValue,
    required this.options,
    required this.isLoading,
    required this.onChanged,
    required this.displayKey,
    required this.valueKey,
    this.lastUpdated,
  });

  String _formatLastUpdated(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bool hasCurrent = options.any(
      (option) => option[valueKey] == selectedValue,
    );
    final List<Map<String, dynamic>> effectiveOptions = hasCurrent
        ? options
        : [
            {valueKey: selectedValue, displayKey: selectedValue},
            ...options,
          ];

    return ListTile(
      leading: icon is IconData
          ? Icon(
              icon,
              color: isDark ? Colors.grey[400] : Colors.black,
              size: 22,
            )
          : HugeIcon(
              icon: icon,
              color: isDark ? Colors.grey[400]! : Colors.black,
              size: 22,
            ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : Colors.black87,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          if (lastUpdated != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Last updated • ${_formatLastUpdated(lastUpdated)}',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey[500] : Colors.grey[500],
                ),
              ),
            ),
        ],
      ),
      trailing: (isLoading && options.isEmpty)
          ? const SizedBox(
              width: 140,
              height: 32,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : SizedBox(
              width: MediaQuery.of(context).size.width * .35,
              child: DropdownButton<String>(
                isExpanded: true,
                value: effectiveOptions.any(
                  (option) => option[valueKey] == selectedValue,
                )
                    ? selectedValue
                    : null,
                onChanged: onChanged,
                underline: const SizedBox(),
                selectedItemBuilder: (context) {
                  return effectiveOptions.map((option) {
                    final String displayText =
                        (option[displayKey] ?? option[valueKey] ?? '')
                            .toString();
                    return Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        displayText,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    );
                  }).toList();
                },
                items: effectiveOptions.map((Map<String, dynamic> option) {
                  final String displayText =
                      (option[displayKey] ?? option[valueKey] ?? '').toString();

                  return DropdownMenuItem<String>(
                    value: option[valueKey]?.toString(),
                    child: Text(
                      displayText,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
