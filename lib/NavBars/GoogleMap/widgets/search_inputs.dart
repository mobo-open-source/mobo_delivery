import 'package:flutter/material.dart';

import '../../../shared/utils/globals.dart';

/// A card-based input section for entering source location and multiple stop locations.
///
/// Displays:
///   - One source location TextField (with "My Location" icon)
///   - Dynamic list of stop TextFields (only shows non-empty ones)
///   - Adjusts card height based on number of visible stops
///
/// Used in route planning screens (usually positioned at the top of the map).
/// Adapts colors and contrast for light/dark theme.
class SearchInputs extends StatelessWidget {
  final TextEditingController sourceController;
  final List<TextEditingController> stopControllers;
  final bool showStopFields;

  const SearchInputs({
    super.key,
    required this.sourceController,
    required this.stopControllers,
    required this.showStopFields,
  });

  @override
  Widget build(BuildContext context) {
    // Count only non-empty stop fields to calculate dynamic height
    final nonEmptyStops = stopControllers
        .where((controller) => controller.text.trim().isNotEmpty)
        .length;

    // Adjust card height based on content (more stops → taller card)
    final cardHeight = (showStopFields && nonEmptyStops > 1) ? 250.0 : 150.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 4,
      color: isDark ? Colors.black : AppStyle.primaryColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: cardHeight,
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Source location input
                  TextField(
                    controller: sourceController,
                    decoration: InputDecoration(
                      hintText: 'Enter source location',
                      hintStyle: TextStyle(color: Colors.black54),
                      prefixIcon: Icon(
                        Icons.my_location,
                        color: Colors.black54,
                      ),
                      border: OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    style: TextStyle(color: Colors.black),
                  ),

                  // Stop location inputs (only shown if enabled)
                  if (showStopFields) ...[
                    ...List.generate(stopControllers.length, (index) {
                      final controller = stopControllers[index];

                      // Skip rendering empty stop fields
                      if (controller.text.trim().isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        children: [
                          const SizedBox(height: 10),
                          TextField(
                            controller: stopControllers[index],
                            decoration: InputDecoration(
                              hintText: 'Enter stop ${index + 1} location',
                              hintStyle: TextStyle(color: Colors.black54),
                              prefixIcon: const Icon(
                                Icons.stop_circle,
                                color: Colors.black54,
                              ),
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            style: TextStyle(color: Colors.black),
                          ),
                        ],
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
