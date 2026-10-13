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
  final int? companyId;
  final String? companyName;

  /// The operation type's Shipping Policy. A picking computes its own
  /// `move_type` from this (`_compute_move_type`), so the create form follows
  /// it instead of assuming 'direct'. Null when the record came from the
  /// offline cache, which does not carry it.
  final String? moveType;

  const OperationTypeModel({
    required this.id,
    required this.name,
    this.defaultLocationSrcId,
    this.defaultLocationDestId,
    this.companyId,
    this.companyName,
    this.moveType,
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
    final displayName = json['display_name'];
    final name = json['name'];
    final resolvedName = (displayName is String && displayName.isNotEmpty)
        ? displayName
        : (name is String && name.isNotEmpty)
        ? name
        : 'Unknown';
    return OperationTypeModel(
      id: json['id'],
      name: resolvedName,
      defaultLocationSrcId:
          (json['default_location_src_id'] != null &&
              json['default_location_src_id'] is List &&
              json['default_location_src_id'].isNotEmpty)
          ? json['default_location_src_id'][0]
          : null,
      defaultLocationDestId:
          (json['default_location_dest_id'] != null &&
              json['default_location_dest_id'] is List &&
              json['default_location_dest_id'].isNotEmpty)
          ? json['default_location_dest_id'][0]
          : null,
      companyId:
          (json['company_id'] != null &&
              json['company_id'] is List &&
              json['company_id'].isNotEmpty)
          ? json['company_id'][0]
          : null,
      companyName:
          (json['company_id'] != null &&
              json['company_id'] is List &&
              json['company_id'].isNotEmpty)
          ? json['company_id'][1]
          : null,
      moveType:
          json['move_type'] is String &&
              (json['move_type'] as String).isNotEmpty
          ? json['move_type'] as String
          : null,
    );
  }

  /// The properties that determine equality between two `OperationTypeModel` instances.
  ///
  /// Thanks to `Equatable`, objects are compared by value instead of reference.
  @override
  List<Object?> get props => [
    id,
    name,
    defaultLocationSrcId,
    defaultLocationDestId,
    companyId,
    companyName,
    moveType,
  ];
}
