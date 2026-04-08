import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../shared/utils/globals.dart';

/// A scrollable bottom card that displays remaining route information during navigation.
///
/// Shows:
///   - Total remaining distance and estimated time
///   - List of upcoming legs/stops with name, distance, duration, and focus button
///   - Visual indicators (icons) for current position, visited stops, upcoming stops
///   - "Add Stop" button to extend the route
///
/// Designed to appear animated from the bottom when navigation is active.
/// Adapts colors and contrast for light/dark theme.
class RemainingInfoCard extends StatelessWidget {
  final String remainingDistance;
  final String remainingDuration;

  /// List of leg/stop info maps, each containing:
  ///   - 'name': String (stop name or "Current Location")
  ///   - 'distance': String (e.g. "12.4 km")
  ///   - 'duration': String (e.g. "18 min")
  ///   - 'latlng': LatLng? (for focus button)
  ///   - 'type': String ('start', 'visited_stop', 'stop', 'destination')
  final List<Map<String, dynamic>> remainingLegInfo;

  // Callback triggered when user taps the focus icon on a leg/stop.
  /// Receives the LatLng of the selected stop (or null if unavailable).
  final Function(LatLng?) onFocusPressed;

  /// Callback triggered when user taps "Add Stop" button.
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
    return Card(
      elevation: 4,
      color: isDark ? Colors.black : AppStyle.primaryColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        height: 250,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Remaining Route',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Total: $remainingDistance, $remainingDuration',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: remainingLegInfo.asMap().entries.map((entry) {
                    final leg = entry.value;

                    /// Chooses appropriate icon and color based on leg type
                    IconData icon;
                    Color iconColor;
                    switch (leg['type']) {
                      case 'start':
                        icon = Icons.my_location;
                        iconColor = Colors.white;
                        break;
                      case 'visited_stop':
                        icon = Icons.check_circle;
                        iconColor = Colors.green;
                        break;
                      case 'stop':
                        icon = Icons.stop_circle;
                        iconColor = Colors.white;
                        break;
                      case 'destination':
                        icon = Icons.location_on;
                        iconColor = Colors.white;
                        break;
                      default:
                        icon = Icons.location_on;
                        iconColor = Colors.grey;
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, color: iconColor, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  leg['name'],
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                Text(
                                  'Distance: ${leg['distance']}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                                Text(
                                  'Duration: ${leg['duration']}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.center_focus_strong,
                              color: Colors.white70,
                              size: 20,
                            ),
                            onPressed: () => onFocusPressed(leg['latlng']),
                            tooltip: 'Focus on ${leg['name']}',
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: isDark
                      ? Colors.black
                      : AppStyle.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: onAddRoutePressed,
                icon: Icon(Icons.add),
                label: Text(
                  "Add Stop",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.black : AppStyle.primaryColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
