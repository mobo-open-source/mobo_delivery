import 'package:equatable/equatable.dart';

/// Represents an Odoo **Partner** (also known as Contact, Customer, Supplier, etc.).
///
/// In Odoo, partners are central entities used across Sales, Purchases, Invoicing,
/// Inventory and CRM modules. This model stores only the minimal fields needed
/// for most picking/transfer creation flows: the partner ID and display name.
///
/// Typical use case: selecting a customer (for deliveries) or supplier (for receipts)
/// when creating a new stock picking.
class PartnerModel extends Equatable {
  final int id;
  final String name;

  const PartnerModel({
    required this.id,
    required this.name,
  });

  /// Creates a `PartnerModel` from the JSON data returned by Odoo's `search_read`
  /// on the `res.partner` model.
  ///
  /// Expected minimal fields in the JSON:
  /// ```json
  /// {
  ///   "id": 457,
  ///   "name": "Tech Solutions Pvt Ltd"
  /// }
  /// ```
  /// Throws error if `id` or `name` are missing or have wrong type.
  factory PartnerModel.fromJson(Map<String, dynamic> json) {
    return PartnerModel(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }

  /// Defines which properties are used to determine equality between two
  /// `PartnerModel` instances (thanks to the `equatable` package).
  ///
  /// Two partners are considered equal if they have the same `id` and `name`.
  @override
  List<Object?> get props => [id, name];
}