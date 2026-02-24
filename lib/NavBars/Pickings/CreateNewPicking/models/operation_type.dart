import 'package:equatable/equatable.dart';

/// Represents an Odoo **Stock Picking Type** (also known as Operation Type).
///
/// Operation Types define the behavior and default locations for stock transfers
/// (receipts, deliveries, internal transfers, manufacturing, etc.) in Odoo's Inventory module.
///
/// This model only stores the minimal fields needed for creating new pickings:
/// - the operation type ID
/// - its human-readable name
/// - default source and destination locations (used to auto-fill picking locations)
class OperationTypeModel extends Equatable {
  final int id;
  final String name;
  final int? defaultLocationSrcId;
  final int? defaultLocationDestId;

  const OperationTypeModel({
    required this.id,
    required this.name,
    this.defaultLocationSrcId,
    this.defaultLocationDestId,
  });

  /// Creates an `OperationTypeModel` instance from Odoo RPC response data.
  ///
  /// Odoo `search_read` returns many2one fields as lists: `[id, display_name]`.
  /// This factory safely extracts only the ID part (first element) or sets null
  /// if the field is false/empty.
  ///
  /// Expected JSON shape example:
  /// ```json
  /// {
  ///   "id": 125,
  ///   "name": "Receipts",
  ///   "default_location_src_id": [14, "WH/Stock"],
  ///   "default_location_dest_id": false
  /// }
  /// ```
  factory OperationTypeModel.fromJson(Map<String, dynamic> json) {
    return OperationTypeModel(
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

  /// The properties that determine equality between two `OperationTypeModel` instances.
  ///
  /// Thanks to `Equatable`, objects are compared by value instead of reference.
  @override
  List<Object?> get props => [id, name, defaultLocationSrcId, defaultLocationDestId];
}