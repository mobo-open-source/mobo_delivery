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
  final String? imageBase64;

  const ProductModel({
    required this.id,
    required this.name,
    required this.uom_id,
    this.imageBase64,
  });

  /// Returns the product name with any leading [SKU] reference stripped.
  String get cleanName => name.replaceAll(RegExp(r'^\[.*?\]\s*'), '');

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    String pickName(dynamic v) =>
        (v is String && v.isNotEmpty && v.toLowerCase() != 'false') ? v : '';
    final displayName = pickName(json['display_name']);
    final rawName = pickName(json['name']);
    final image = json['image_128'];
    return ProductModel(
      id: json['id'] as int,
      name: displayName.isNotEmpty ? displayName : rawName,
      uom_id: json['uom_id'][0] as int,
      imageBase64: (image is String && image.isNotEmpty && image != 'false')
          ? image
          : null,
    );
  }

  @override
  List<Object?> get props => [id, name, uom_id];
}