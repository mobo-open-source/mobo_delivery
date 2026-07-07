import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../shared/utils/date_picker_utils.dart';
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

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filter Options',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
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

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      modalScheduledDate == null
                          ? 'Select Date'
                          : '${modalScheduledDate}'.split(' ')[0],
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: Icon(
                      HugeIcons.strokeRoundedCalendar03,
                      color: AppStyle.primaryColor,
                    ),
                    onTap: () async {
                      final picked =
                          await DatePickerUtils.showStandardDatePicker(
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

                  if (!isDataFromHive) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Select Type',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      children: [
                        ChoiceChip(
                          label: Text(
                            'Outgoing',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: modalType == 'outgoing'
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: modalType == 'outgoing'
                                  ? Colors.white
                                  : (Theme.of(context).brightness == Brightness.dark
                                        ? Colors.white
                                        : Colors.black87),
                            ),
                          ),
                          selected: modalType == 'outgoing',
                          selectedColor: AppStyle.primaryColor,
                          backgroundColor:
                              Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white.withOpacity(0.08)
                                  : AppStyle.primaryColor.withOpacity(0.08),
                          surfaceTintColor: Colors.transparent,
                          showCheckmark: false,
                          elevation: 0,
                          pressElevation: 0,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.grey[600]!
                                  : Colors.grey[300]!,
                            ),
                          ),
                          onSelected: (val) {
                            setModalState(() {
                              modalType = 'outgoing';
                            });
                          },
                        ),
                        ChoiceChip(
                          label: Text(
                            'Incoming',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: modalType == 'incoming'
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: modalType == 'incoming'
                                  ? Colors.white
                                  : (Theme.of(context).brightness == Brightness.dark
                                        ? Colors.white
                                        : Colors.black87),
                            ),
                          ),
                          selected: modalType == 'incoming',
                          selectedColor: AppStyle.primaryColor,
                          backgroundColor:
                              Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white.withOpacity(0.08)
                                  : AppStyle.primaryColor.withOpacity(0.08),
                          surfaceTintColor: Colors.transparent,
                          showCheckmark: false,
                          elevation: 0,
                          pressElevation: 0,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.grey[600]!
                                  : Colors.grey[300]!,
                            ),
                          ),
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

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(HugeIcons.strokeRoundedTick03),
                      label: const Text('Apply Filter'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppStyle.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
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
