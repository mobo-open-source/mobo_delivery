import 'package:hive_ce/hive.dart';

part 'product.g.dart';

/// Minimal representation of an Odoo product (`product.product`) record,
/// cached in Hive for offline usage in picking creation, move line editing,
/// and product selection flows.
///
/// This model stores only the three most essential fields needed in most cases:
/// - `id` (database identifier)
/// - `name` (display name, often includes internal reference)
/// - `uom_id` (default unit of measure ID — used when creating stock moves)
///
/// Used primarily for:
/// • Populating product dropdowns when adding/editing move lines
/// • Displaying product names in picking details and operations
/// • Offline product selection and quantity entry
@HiveType(typeId: 2)
class Product {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final int uom_id;

  Product({required this.id, required this.name, required this.uom_id});

  /// Creates a `Product` instance from Odoo JSON. Prefers `display_name`
  /// over `name` so variants render with their attribute suffix.
  factory Product.fromJson(Map<String, dynamic> json) {
    String pickName(dynamic v) =>
        (v is String && v.isNotEmpty && v.toLowerCase() != 'false') ? v : '';
    final displayName = pickName(json['display_name']);
    final rawName = pickName(json['name']);
    return Product(
      id: json['id'] ?? 0,
      name: displayName.isNotEmpty ? displayName : rawName,
      uom_id: (json['uom_id'] != null && json['uom_id'] is List && json['uom_id'].isNotEmpty)
          ? json['uom_id'][0] as int
          : 0,
    );
  }

  /// Converts this product to a simple JSON map
  ///
  /// Used when:
  /// • Saving back to Hive (Hive handles it automatically)
  /// • Preparing data for dropdowns or other serialization
  /// • Debugging or logging
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'uom_id': uom_id,
    };
  }
}