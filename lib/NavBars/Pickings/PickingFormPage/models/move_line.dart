import 'package:hive/hive.dart';

part 'move_line.g.dart';

/// Represents a single **stock move line** (`stock.move.line`) record from Odoo,
/// stored locally in Hive for offline access and caching in the picking details flow.
///
/// This model is used to:
/// • Display detailed operations (product, source location, lot/serial, done quantity)
/// • Cache move lines when offline or to reduce repeated RPC calls
/// • Quickly show lines in `StockMoveLineListPage` without needing full online fetch every time
///
/// Stores the raw Odoo data map + essential keys (`id`, `pickingId`) for filtering and lookup.
@HiveType(typeId: 13)
class MoveLine extends HiveObject {
  @HiveField(0)
  final int id;
  @HiveField(1)
  final int pickingId;

  /// Raw data map coming from Odoo's `search_read` on `stock.move.line`
  ///
  /// Typically contains keys like:
  ///   - `product_id`       → [id, name]
  ///   - `location_id`      → [id, name] (source location)
  ///   - `lot_id`           → [id, name] or false
  ///   - `quantity_product_uom` → double (done quantity)
  ///   - and possibly others depending on requested fields
  ///
  /// Stored as-is so the UI can access any field without extra parsing.
  @HiveField(2)
  final Map<String, dynamic> data;

  MoveLine({
    required this.id,
    required this.pickingId,
    required this.data,
  });

  /// Converts this move line to a JSON-compatible map for serialization
  ///
  /// Merges `id` and `picking_id` with the raw `data` map.
  /// Useful when sending pending updates back to Odoo or saving to other storage.
  Map<String, dynamic> toJson() => {
    'id': id,
    'picking_id': pickingId,
    ...data,
  };

  /// Creates a `MoveLine` instance from a JSON map (usually from cache or API)
  ///
  /// Expects at minimum `id` and `picking_id`.
  /// Falls back to `id: 0` if missing (safe default).
  /// The entire JSON is stored in `data` for maximum flexibility.
  factory MoveLine.fromJson(Map<String, dynamic> json) {
    return MoveLine(
      id: json['id'] ?? 0,
      pickingId: json['picking_id'],
      data: json,
    );
  }
}
