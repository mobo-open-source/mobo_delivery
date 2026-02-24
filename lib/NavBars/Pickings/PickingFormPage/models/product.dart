import 'package:hive/hive.dart';

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

  /// Creates a `Product` instance from Odoo JSON response (search_read result)
  ///
  /// Handles safe parsing with fallbacks:
  /// - `id`: defaults to 0
  /// - `name`: defaults to empty string
  /// - `uom_id`: extracts ID from many2one list `[id, name]` or defaults to 0
  ///
  /// Expected minimal JSON shape:
  /// ```json
  /// {
  ///   "id": 8923,
  ///   "name": "USB-C Cable 2m",
  ///   "uom_id": [1, "Units"]
  /// }
  /// ```
  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
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