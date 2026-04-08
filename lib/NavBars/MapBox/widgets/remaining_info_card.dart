import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../shared/utils/globals.dart';

/// Slide-up card shown during active navigation with remaining route info.
///
/// Displays remaining time + distance prominently, then a timeline-style
/// list of upcoming stops with focus buttons.
/// Uses a white/surface card style, no solid brand-color fill.
class RemainingInfoCard extends StatelessWidget {
  final String remainingDistance;
  final String remainingDuration;

  /// Each entry: 'name', 'distance', 'duration', 'latlng' (LatLng?), 'type'.
  final List<Map<String, dynamic>> remainingLegInfo;

  final Function(LatLng?) onFocusPressed;
  final VoidCallback onAddRoutePressed;

  const RemainingInfoCard({
    super.key,
    required this.remainingDistance,
    required this.remainingDuration,
    required this.remainingLegInfo,
    required this.onFocusPressed,
    required this.onAddRoutePressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1C1C2E) : Colors.white;
    final primary = isDark ? Colors.white : const Color(0xFF202124);
    final secondary = isDark ? const Color(0xFFAAAAAA) : const Color(0xFF70757A);
    final accent = AppStyle.primaryColor;
    final dividerColor = isDark ? Colors.white12 : const Color(0xFFE8E8E8);

    return Container(
      constraints: const BoxConstraints(maxHeight: 320),
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

          // ── Remaining summary ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        remainingDuration,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: primary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        remainingDistance,
                        style: TextStyle(
                          fontSize: 14,
                          color: secondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Remaining',
                  style: TextStyle(
                    fontSize: 11,
                    color: secondary,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: dividerColor, indent: 20, endIndent: 20),

          // ── Stop list (timeline style) ────────────────────────────────────
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: remainingLegInfo.length,
              itemBuilder: (context, index) {
                final leg = remainingLegInfo[index];
                final type = leg['type'] as String? ?? 'stop';
                final isLast = index == remainingLegInfo.length - 1;

                Color dotColor;
                IconData dotIcon;
                switch (type) {
                  case 'start':
                    dotColor = const Color(0xFF4285F4);
                    dotIcon = Icons.my_location;
                    break;
                  case 'visited_stop':
                    dotColor = Colors.green[600]!;
                    dotIcon = Icons.check_circle_outline;
                    break;
                  case 'destination':
                    dotColor = accent;
                    dotIcon = Icons.flag_outlined;
                    break;
                  default:
                    dotColor = accent;
                    dotIcon = Icons.radio_button_unchecked;
                }

                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Timeline indicator
                      SizedBox(
                        width: 32,
                        child: Column(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: dotColor.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(dotIcon,
                                  color: dotColor, size: 13),
                            ),
                            if (!isLast)
                              Expanded(
                                child: Container(
                                  width: 1.5,
                                  color: dividerColor,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Content
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12, top: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      leg['name'] as String? ?? '',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: primary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
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
                              IconButton(
                                icon: Icon(Icons.center_focus_strong_outlined,
                                    color: secondary, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 32, minHeight: 32),
                                onPressed: () =>
                                    onFocusPressed(leg['latlng'] as LatLng?),
                                tooltip: 'Focus on ${leg['name']}',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // ── Add Stop button ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: accent, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: onAddRoutePressed,
                icon: const Icon(Icons.add_location_alt_outlined, size: 16),
                label: const Text(
                  'Add Stop',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
