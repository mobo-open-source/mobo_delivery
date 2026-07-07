import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../shared/utils/globals.dart';

/// Route overview card shown before navigation starts.
///
/// Displays travel mode selector (chips), duration + distance summary,
/// scrollable leg list, and Start / Add Stop action buttons.
/// Uses a standard white/surface card style (no solid brand-color fill).
class RouteInfoCard extends StatefulWidget {
  final String routeDuration;
  final String routeDistance;

  /// Each entry: 'start_address', 'end_address', 'distance', 'duration'.
  final List<Map<String, String>> legInfo;

  final VoidCallback? onStartPressed;
  final VoidCallback onAddStopPressed;

  /// Optional error message shown when the routing engine failed to
  /// compute a route (e.g. NO_ROUTE_FOUND). When non-null the card
  /// replaces the duration/legs area with a friendly error block.
  final String? routeError;

  const RouteInfoCard({
    super.key,
    required this.routeDuration,
    required this.routeDistance,
    required this.legInfo,
    this.onStartPressed,
    required this.onAddStopPressed,
    this.routeError,
  });

  @override
  State<RouteInfoCard> createState() => _RouteInfoCardState();
}

class _RouteInfoCardState extends State<RouteInfoCard> {
  bool _collapsed = false;

  void _toggle() => setState(() => _collapsed = !_collapsed);

  void _handleDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v > 200 && !_collapsed) {
      setState(() => _collapsed = true);
    } else if (v < -200 && _collapsed) {
      setState(() => _collapsed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1C1C2E) : Colors.white;
    final primary = isDark ? Colors.white : const Color(0xFF202124);
    final secondary = isDark ? const Color(0xFFAAAAAA) : const Color(0xFF70757A);
    final accent = AppStyle.primaryColor;
    final dividerColor = isDark ? Colors.white12 : const Color(0xFFE8E8E8);
    final routeDuration = widget.routeDuration;
    final routeDistance = widget.routeDistance;
    final legInfo = widget.legInfo;
    final routeError = widget.routeError;
    final onStartPressed = widget.onStartPressed;
    final onAddStopPressed = widget.onAddStopPressed;

    return Container(
      constraints: const BoxConstraints(maxHeight: 430),
      clipBehavior: Clip.antiAlias,
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

          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggle,
            onVerticalDragEnd: _handleDragEnd,
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 14),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),

          AnimatedCrossFade(
            crossFadeState: _collapsed
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
            reverseDuration: const Duration(milliseconds: 300),
            sizeCurve: Curves.easeInOutCubic,
            firstCurve: Curves.easeInOut,
            secondCurve: Curves.easeInOut,
            secondChild: const SizedBox(width: double.infinity),
            firstChild: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (routeError != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      HugeIcons.strokeRoundedAlert02,
                      size: 22,
                      color: Colors.orange[700],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Route unavailable',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          routeError,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  routeDuration,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: primary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  routeDistance,
                  style: TextStyle(
                    fontSize: 13,
                    color: secondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: dividerColor, indent: 20, endIndent: 20),

          if (legInfo.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
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
                                fontWeight: FontWeight.w600,
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
                                  fontWeight: FontWeight.w400,
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
                        Icon(HugeIcons.strokeRoundedArrowRight01,
                            color: isDark ? Colors.white24 : Colors.grey[350],
                            size: 18),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
              ],
            ),
          ),

          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: onAddStopPressed,
                    icon: const Icon(HugeIcons.strokeRoundedLocation01, size: 16),
                    label: const Text(
                      'Add Stop',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
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
                    icon: const Icon(HugeIcons.strokeRoundedNavigation03, size: 18),
                    label: const Text(
                      'Start',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
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
