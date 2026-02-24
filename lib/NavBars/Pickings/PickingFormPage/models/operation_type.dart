import 'package:hive/hive.dart';

part 'operation_type.g.dart';

/// Represents an Odoo **Stock Picking Type** (also known as Operation Type),
/// stored in Hive for offline caching and fast access in the picking creation/selection flow.
///
/// This model stores only the minimal fields needed when creating new pickings:
/// - ID and human-readable name
/// - Default source and destination locations (used to auto-populate locations)
///
/// Typically loaded via `stock.picking.type` → `search_read` and cached so users
/// can select operation types even when offline.
@HiveType(typeId: 10)
class OperationType {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final int? defaultLocationSrcId;

  @HiveField(3)
  final int? defaultLocationDestId;

  OperationType({
    required this.id,
    required this.name,
    this.defaultLocationSrcId,
    this.defaultLocationDestId,
  });

  /// Creates an `OperationType` instance from Odoo JSON response
  ///
  /// Safely handles many2one fields returned as lists `[id, display_name]`.
  /// Sets `null` if the field is `false`, empty, or missing.
  ///
  /// Expected JSON shape (minimal):
  /// ```json
  /// {
  ///   "id": 125,
  ///   "name": "Receipts",
  ///   "default_location_src_id": [14, "WH/Stock"],
  ///   "default_location_dest_id": false
  /// }
  /// ```
  factory OperationType.fromJson(Map<String, dynamic> json) {
    return OperationType(
      id: json['id'],
      name: json['name'],
      defaultLocationSrcId: (json['default_location_src_id'] != null && json['default_location_src_id'] is List && json['default_location_src_id'].isNotEmpty)
          ? json['default_location_src_id'][0]
          : null,
      defaultLocationDestId: (json['default_location_dest_id'] != null && json['default_location_dest_id'] is List && json['default_location_dest_id'].isNotEmpty)
          ? json['default_location_dest_id'][0]
          : null,
    );
  }
}
