import 'package:flutter/material.dart';

import '../../../shared/utils/globals.dart';

/// A detailed bottom card displayed before navigation starts, showing route overview.
///
/// Features:
///   - Tab bar to switch travel mode (Car / Bike / Train / Walk)
///   - Displays total route distance and estimated duration
///   - Lists all route segments (legs) with start/end addresses, distance, and time
///   - "Start" button to begin navigation
///   - "Add Stop" button to extend the route
///
/// Adapts colors, icons, and contrast for light/dark theme.
/// Uses `DefaultTabController` to sync mode changes with parent widget.
class RouteInfoCard extends StatelessWidget {
  final String selectedTravelMode;
  final String routeDuration;
  final String routeDistance;

  /// List of leg/segment info maps, each containing:
  ///   - 'start_address': String
  ///   - 'end_address': String
  ///   - 'distance': String (e.g. "12.4 km")
  ///   - 'duration': String (e.g. "18 min")
  final List<Map<String, String>> legInfo;

  /// Callback to start navigation (may be null if route is invalid)
  final VoidCallback? onStartPressed;

  /// Callback when user wants to add another stop
  final VoidCallback onAddStopPressed;

  /// Callback triggered when user changes travel mode via tabs
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

  @override
  Widget build(BuildContext context) {
    /// Maps internal travel mode strings to user-friendly display titles.
    ///
    /// Used as the main header title above the tabs.
    /// Falls back to "Route Options" if mode is unrecognized.
    String getTitle() {
      switch (selectedTravelMode) {
        case 'driving':
          return 'Drive';
        case 'two_wheeler':
          return 'Bike';
        case 'transit':
          return 'Train';
        case 'walking':
          return 'Walk';
        default:
          return 'Route Options';
      }
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 4,
      color: isDark ? Colors.black : AppStyle.primaryColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        height: 400,
        padding: const EdgeInsets.all(12),
        child: DefaultTabController(
          length: 4,
          child: Builder(
            builder: (context) {
              final TabController tabController = DefaultTabController.of(
                context,
              )!;

              // Sync tab changes → travel mode callback
              tabController.addListener(() {
                if (!tabController.indexIsChanging) {
                  String newMode;
                  switch (tabController.index) {
                    case 0:
                      newMode = 'driving';
                      break;
                    case 1:
                      newMode = 'two_wheeler';
                      break;
                    case 2:
                      newMode = 'transit';
                      break;
                    case 3:
                      newMode = 'walking';
                      break;
                    default:
                      newMode = 'driving';
                  }
                  onTravelModeChanged(newMode);
                }
              });

              return Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            getTitle(),
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TabBar(
                            indicatorColor: Colors.white,
                            labelColor: Colors.white,
                            unselectedLabelColor: Colors.white70,
                            tabs: [
                              Tab(
                                icon: Icon(Icons.directions_car),
                                text: 'Car',
                              ),
                              Tab(icon: Icon(Icons.pedal_bike), text: 'Bike'),
                              Tab(icon: Icon(Icons.train), text: 'Train'),
                              Tab(
                                icon: Icon(Icons.directions_walk),
                                text: 'Walk',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Total Duration: $routeDuration',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Total Distance: $routeDistance',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (legInfo.isNotEmpty) ...[
                            Text(
                              'Route Segments:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...legInfo.asMap().entries.map((entry) {
                              final index = entry.key;
                              final leg = entry.value;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Stop ${index + 1}: ${leg['start_address']} to ${leg['end_address']}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Distance: ${leg['distance']}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Duration: ${leg['duration']}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      Container(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: isDark
                                ? Colors.black
                                : AppStyle.primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: onStartPressed,
                          icon: Icon(
                            Icons.play_arrow,
                            size: 20,
                            color: isDark
                                ? Colors.black
                                : AppStyle.primaryColor,
                          ),
                          label: Text(
                            "Start",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.black
                                  : AppStyle.primaryColor,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: isDark
                                ? Colors.black
                                : AppStyle.primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: onAddStopPressed,
                          icon: const Icon(Icons.add_location_alt, size: 20),
                          label: Text(
                            "Add Stop",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? Colors.black
                                  : AppStyle.primaryColor,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
