import 'package:hive/hive.dart';

part 'partner.g.dart';

/// Minimal representation of an Odoo **Partner** / Contact record (`res.partner`),
/// cached in Hive for offline usage in picking creation, selection, and display flows.
///
/// This model only stores the two most essential fields:
/// - `id` (database identifier)
/// - `name` (display name — usually company name or person name)
///
/// Used mainly for:
/// • Populating customer/supplier dropdowns when creating pickings
/// • Showing partner name in picking details
/// • Offline partner selection and display
@HiveType(typeId: 3)
class Partner {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final String name;

  Partner({required this.id, required this.name});

  /// Creates a `Partner` instance from JSON data returned by Odoo `search_read`
  ///
  /// Safely handles missing fields with fallbacks:
  /// - `id`: defaults to 0
  /// - `name`: defaults to empty string
  ///
  /// Expected minimal JSON shape:
  /// ```json
  /// {
  ///   "id": 457,
  ///   "name": "Tech Solutions Pvt Ltd"
  /// }
  /// ```
  factory Partner.fromJson(Map<String, dynamic> json) {
    return Partner(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
    );
  }

  /// Converts this partner to a simple JSON map
  ///
  /// Mainly used when:
  /// - serializing for UI dropdowns
  /// - saving back to Hive or preparing data for other operations
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }
}