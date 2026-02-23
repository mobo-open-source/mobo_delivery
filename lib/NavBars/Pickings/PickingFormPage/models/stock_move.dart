import 'package:hive/hive.dart';

part 'stock_move.g.dart';

/// Represents a **stock move** record (`stock.move`) from Odoo,
/// cached in Hive for offline display, editing, and queuing of move-line changes.
///
/// This model is the core entity for showing planned/done quantities in picking details
/// and operations screens. It stores:
/// • Product and quantity info (demand vs done)
/// • References to picking, locations, UoM, and lot/serial (if tracked)
///
/// Used in:
/// • `PickingDetailsPage` product table (demand / quantity columns)
/// • Move line editing dialogs
/// • Offline add/edit/delete queuing via `ProductUpdates`
///
/// Many2one fields are kept as `List<dynamic>` (`[id, display_name]`) to preserve
/// Odoo format and avoid extra parsing when displaying names.
@HiveType(typeId: 5)
class StockMove {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final List<dynamic>? productId;

  @HiveField(2)
  final double productUomQty;

  @HiveField(3)
  final double quantity;

  @HiveField(4)
  final List<dynamic>? pickingId;

  @HiveField(5)
  final List<dynamic>? locationId;

  @HiveField(6)
  final List<dynamic>? lotId;

  @HiveField(7)
  final String? quantityProductUom;

  @HiveField(8)
  final int? productUomId;

  StockMove({
    required this.id,
    this.productId,
    required this.productUomQty,
    this.productUomId,
    required this.quantity,
    this.pickingId,
    this.locationId,
    this.lotId,
    this.quantityProductUom,
  });

  /// Creates a `StockMove` from Odoo JSON response (search_read result)
  ///
  /// Handles safe parsing with fallbacks for missing/invalid fields.
  /// Converts numeric fields to double safely.
  factory StockMove.fromJson(Map<String, dynamic> json) {
    return StockMove(
      id: json['id'] is int ? json['id'] : 0,
      productId: json['product_id'] is List ? json['product_id'] : null,
      productUomQty: (json['product_uom_qty'] is num ? json['product_uom_qty'] : 0).toDouble(),
      productUomId: json['product_uom_id'] is int ? json['product_uom_id'] : 0,
      quantity: (json['quantity'] is num ? json['quantity'] : 0).toDouble(),
      pickingId: json['picking_id'] is List ? json['picking_id'] : null,
      locationId: json['location_id'] is List ? json['location_id'] : null,
      lotId: json['lot_id'] is List ? json['lot_id'] : null,
      quantityProductUom: json['quantity_product_uom'] is String ? json['quantity_product_uom'] : null,
    );
  }

  /// Converts this stock move to a JSON-compatible map
  ///
  /// Used when:
  /// • Saving to Hive (automatic)
  /// • Preparing data for offline update queues (`ProductUpdates`)
  /// • Debugging or logging move details
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'product_uom_qty': productUomQty,
      'product_uom_id': productUomId,
      'quantity': quantity,
      'picking_id': pickingId,
      'location_id': locationId,
      'lot_id': lotId,
      'quantity_product_uom': quantityProductUom,
    };
  }
}