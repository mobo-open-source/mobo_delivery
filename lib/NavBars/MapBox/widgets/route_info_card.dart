import 'package:flutter/material.dart';

import '../../../shared/utils/globals.dart';

/// Route overview card shown before navigation starts.
///
/// Displays travel mode selector (chips), duration + distance summary,
/// scrollable leg list, and Start / Add Stop action buttons.
/// Uses a standard white/surface card style (no solid brand-color fill).
class RouteInfoCard extends StatelessWidget {
  final String selectedTravelMode;
  final String routeDuration;
  final String routeDistance;

  /// Each entry: 'start_address', 'end_address', 'distance', 'duration'.
  final List<Map<String, String>> legInfo;

  final VoidCallback? onStartPressed;
  final VoidCallback onAddStopPressed;
  final Function(String) onTravelModeChanged;

  const RouteInfoCard({
    super.key,
    required this.selectedTravelMode,
    required this.routeDuration,
    required this.routeDistance,
    required this.legInfo,
    this.onStartPressed,
    required this.onAddStopPressed,
    required this.onTravelModeChanged,
  });

  static const _modes = [
    {'mode': 'driving', 'icon': Icons.directions_car_filled, 'label': 'Drive'},
    {'mode': 'bicycling', 'icon': Icons.directions_bike, 'label': 'Bike'},
    {'mode': 'walking', 'icon': Icons.directions_walk, 'label': 'Walk'},
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1C1C2E) : Colors.white;
    final primary = isDark ? Colors.white : const Color(0xFF202124);
    final secondary = isDark ? const Color(0xFFAAAAAA) : const Color(0xFF70757A);
    final accent = AppStyle.primaryColor;
    final dividerColor = isDark ? Colors.white12 : const Color(0xFFE8E8E8);

    return Container(
      constraints: const BoxConstraints(maxHeight: 430),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ──────────────────────────────────────────────────
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),

          // ── Travel mode chips ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: _modes.map((m) {
                final selected = selectedTravelMode == m['mode'];
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onTravelModeChanged(m['mode'] as String),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: selected
                            ? accent.withValues(alpha: 0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? accent
                              : (isDark ? Colors.white24 : Colors.grey[300]!),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            m['icon'] as IconData,
                            color: selected ? accent : secondary,
                            size: 20,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            m['label'] as String,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                              color: selected ? accent : secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          // ── Duration + Distance summary ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  routeDuration,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: primary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  routeDistance,
                  style: TextStyle(
                    fontSize: 15,
                    color: secondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: dividerColor, indent: 20, endIndent: 20),

          // ── Leg list ──────────────────────────────────────────────────────
          if (legInfo.isNotEmpty)
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                itemCount: legInfo.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: dividerColor),
                itemBuilder: (context, i) {
                  final leg = legInfo[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        // Numbered circle
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: accent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                leg['end_address'] ?? '',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: primary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${leg['distance']}  ·  ${leg['duration']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            color: isDark ? Colors.white24 : Colors.grey[350],
                            size: 18),
                      ],
                    ),
                  );
                },
              ),
            ),

          // ── Action buttons ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: onStartPressed,
                    icon: const Icon(Icons.navigation_rounded, size: 18),
                    label: const Text(
                      'Start',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: onAddStopPressed,
                    icon: const Icon(Icons.add_location_alt_outlined, size: 16),
                    label: const Text(
                      'Add Stop',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
