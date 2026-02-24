import 'package:flutter/material.dart';

import '../../../../shared/utils/globals.dart';

/// Bottom sheet dialog for filtering pickings by:
/// • Scheduled date
/// • State (status)
/// • Type (incoming/outgoing — only shown when data is online)
///
/// Used from `PickingsGroupedPage` to apply filters to the picking list.
/// Communicates selected values back via `onApply` callback.
///
/// Features:
/// • Date picker for scheduled date
/// • Dropdown for picking state
/// • Choice chips for type (incoming/outgoing)
/// • Clear button when filters are active
/// • Dark/light theme support
class FilterBottomSheet extends StatelessWidget {
  final String? initialStateLabel;
  final DateTime? initialScheduleDate;
  final DateTime? initialDeadlineDate;
  final String initialType;
  final bool isDataFromHive;
  final bool isFilterApplied;
  final bool isDark;
  final Map<String, String> stateMap;
  final Function(DateTime?, DateTime?, String?, String?, String) onApply;
  final VoidCallback onClear;

  const FilterBottomSheet({
    super.key,
    required this.initialStateLabel,
    required this.initialScheduleDate,
    required this.initialDeadlineDate,
    required this.initialType,
    required this.isDataFromHive,
    required this.isFilterApplied,
    required this.isDark,
    required this.stateMap,
    required this.onApply,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    // Local mutable state for modal (won't affect parent until Apply)
    DateTime? modalScheduledDate = initialScheduleDate;
    DateTime? modalDeadlineDate = initialDeadlineDate;
    String? modalStateLabel = initialStateLabel;
    String? modalStateValue = stateMap.entries
        .firstWhere(
          (entry) => entry.value == initialStateLabel,
      orElse: () => const MapEntry('', ''),
    )
        .key;
    String modalType = initialType;

    return StatefulBuilder(
      builder: (context, setModalState) {
        return Padding(
          padding: MediaQuery.of(context).viewInsets,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(
                        bottom: 20,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),

                  // Header + Clear button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filter Options',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppStyle.primaryColor,
                        ),
                      ),
                      if (isFilterApplied)
                        TextButton(
                          onPressed: onClear,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Clear',
                                style: TextStyle(
                                  color: isDark ? Colors.white: AppStyle.primaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Scheduled Date Picker
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      modalScheduledDate == null
                          ? 'Select Date'
                          : '${modalScheduledDate}'.split(' ')[0],
                      style: const TextStyle(
                        fontSize: 16,
                      ),
                    ),
                    trailing: Icon(
                      Icons.calendar_today,
                      color: AppStyle.primaryColor,
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setModalState(() {
                          modalScheduledDate = picked;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // State Dropdown
                  DropdownButtonFormField<String>(
                    value: modalStateLabel,
                    decoration: const InputDecoration(
                      labelText: 'Select State',
                      border: OutlineInputBorder(),
                    ),
                    items: stateMap.values
                        .map(
                          (label) => DropdownMenuItem(
                        value: label,
                        child: Text(label),
                      ),
                    )
                        .toList(),
                    onChanged: (label) {
                      setModalState(() {
                        modalStateLabel = label;
                        modalStateValue = stateMap.entries
                            .firstWhere(
                              (entry) => entry.value == label,
                          orElse: () => const MapEntry('', ''),
                        )
                            .key;
                      });
                    },
                  ),

                  // Type filter (only visible when online)
                  if (!isDataFromHive) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Select Type',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      children: [
                        ChoiceChip(
                          label: const Text('Outgoing'),
                          selected: modalType == 'outgoing',
                          onSelected: (val) {
                            setModalState(() {
                              modalType = 'outgoing';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: const Text('Incoming'),
                          selected: modalType == 'incoming',
                          onSelected: (val) {
                            setModalState(() {
                              modalType = 'incoming';
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Apply Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check),
                      label: const Text('Apply Filter'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppStyle.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        onApply(
                          modalScheduledDate,
                          modalDeadlineDate,
                          modalStateLabel,
                          modalStateValue,
                          modalType,
                        );
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}