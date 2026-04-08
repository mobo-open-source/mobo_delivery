import 'package:equatable/equatable.dart';

/// Minimal representation of an Odoo product (from `product.product` model).
///
/// This model is used mainly in inventory/picking flows to:
/// - display product names in lists or dropdowns
/// - associate products with stock moves
/// - reference the product's default Unit of Measure (UoM)
///
/// Only the most essential fields are included to keep the model lightweight.
class ProductModel extends Equatable {
  final int id;
  final String name;
  final int uom_id;

  const ProductModel({
    required this.id,
    required this.name,
    required this.uom_id,
  });

  /// Creates a `ProductModel` from Odoo `search_read` result.
  ///
  /// Expected JSON shape (minimal fields):
  /// ```json
  /// {
  ///   "id": 8923,
  ///   "name": "USB-C Cable 2m",
  ///   "uom_id": [1, "Units"]
  /// }
  /// ```
  /// Assumes `uom_id` is returned as a list `[id, display_name]`.
  /// Throws if any required field is missing or has incorrect type.
  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] as int,
      name: json['name'] as String,
      uom_id: json['uom_id'][0] as int,
    );
  }

  /// Properties used for value-based equality comparison (via `equatable`).
  ///
  /// Two products are equal if they share the same `id`, `name` and `uom_id`.
  /// Helps when comparing items in lists, state management, or deduplication.
  @override
  List<Object?> get props => [id, name, uom_id];
}