/// What the Detailed Operations screen needs to show and edit a picking's
/// move lines the way Odoo's own "Detailed Operations" does.
///
/// Plain read models over Odoo's wire format: a many2one arrives as
/// `[id, "Name"]` or `false`, and both are handled here so the screen never
/// sees a raw `false`.
library;

int? m2oId(dynamic value) =>
    value is List && value.isNotEmpty && value.first is int
    ? value.first as int
    : null;

String? m2oName(dynamic value) {
  if (value is! List || value.length < 2) return null;
  final name = value[1]?.toString().trim() ?? '';
  return name.isEmpty || name.toLowerCase() == 'false' ? null : name;
}

double toDouble(dynamic value) => value is num ? value.toDouble() : 0.0;

/// A `stock.move` of the picking — the product line a move line belongs to.
///
/// [showQuant], [showLotsM2o] and [hasTracking] are read from Odoo rather
/// than worked out here: Odoo computes them from different product fields
/// in each version (`detailed_type` in 17, `is_storable` in 18 and 19,
/// `tracking` in 20), so reading its answer keeps the app version-free.
class DetailedMove {
  final int id;
  final int productId;
  final String productName;
  final int? locationId;
  final double demand;
  final double done;
  final String hasTracking;
  final bool showQuant;
  final bool showLotsM2o;

  const DetailedMove({
    required this.id,
    required this.productId,
    required this.productName,
    required this.locationId,
    required this.demand,
    required this.done,
    required this.hasTracking,
    required this.showQuant,
    required this.showLotsM2o,
  });

  bool get isTracked => hasTracking == 'lot' || hasTracking == 'serial';

  /// Odoo's own rule for the Lot/Serial column: shown when "Pick From" is
  /// not, the product is tracked, and the picking type picks existing lots.
  bool get showLotPicker => !showQuant && isTracked && showLotsM2o;

  factory DetailedMove.fromJson(Map<String, dynamic> json) => DetailedMove(
    id: json['id'] as int,
    productId: m2oId(json['product_id']) ?? 0,
    productName: m2oName(json['product_id']) ?? 'Product',
    locationId: m2oId(json['location_id']),
    demand: toDouble(json['product_uom_qty']),
    done: toDouble(json['quantity']),
    hasTracking: json['has_tracking'] is String
        ? json['has_tracking'] as String
        : 'none',
    showQuant: json['show_quant'] == true,
    showLotsM2o: json['show_lots_m2o'] == true,
  );
}

/// A `stock.move.line` — one row of Odoo's Detailed Operations.
class DetailedLine {
  final int id;
  final int? moveId;
  final String productName;
  final int? locationId;
  final String? locationName;
  final int? lotId;
  final String? lotName;
  final int? packageId;
  final int? ownerId;
  final double quantity;

  const DetailedLine({
    required this.id,
    required this.moveId,
    required this.productName,
    required this.locationId,
    required this.locationName,
    required this.lotId,
    required this.lotName,
    required this.packageId,
    required this.ownerId,
    required this.quantity,
  });

  factory DetailedLine.fromJson(Map<String, dynamic> json) => DetailedLine(
    id: json['id'] as int,
    moveId: m2oId(json['move_id']),
    productName: m2oName(json['product_id']) ?? 'Product',
    locationId: m2oId(json['location_id']),
    locationName: m2oName(json['location_id']),
    lotId: m2oId(json['lot_id']),
    lotName: m2oName(json['lot_id']),
    packageId: m2oId(json['package_id']),
    ownerId: m2oId(json['owner_id']),
    quantity: toDouble(json['quantity']),
  );
}

/// A `stock.quant` offered in "Pick From": stock of the product sitting in
/// the move's source location or one of its sub-locations.
class PickFromOption {
  final int id;
  final int? locationId;
  final String? locationName;
  final int? lotId;
  final String? lotName;
  final int? packageId;
  final String? packageName;
  final int? ownerId;
  final double available;

  const PickFromOption({
    required this.id,
    required this.locationId,
    required this.locationName,
    required this.lotId,
    required this.lotName,
    required this.packageId,
    required this.packageName,
    required this.ownerId,
    required this.available,
  });

  factory PickFromOption.fromJson(Map<String, dynamic> json) => PickFromOption(
    id: json['id'] as int,
    locationId: m2oId(json['location_id']),
    locationName: m2oName(json['location_id']),
    lotId: m2oId(json['lot_id']),
    lotName: m2oName(json['lot_id']),
    packageId: m2oId(json['package_id']),
    packageName: m2oName(json['package_id']),
    ownerId: m2oId(json['owner_id']),
    available: toDouble(json['available_quantity']),
  );

  /// Whether [line] is already picking from this stock.
  bool matches(DetailedLine line) =>
      line.locationId == locationId &&
      line.lotId == lotId &&
      line.packageId == packageId &&
      line.ownerId == ownerId;

  /// The values Odoo copies onto a move line when "Pick From" is set —
  /// `stock.move.line._copy_quant_info`, identical in Odoo 17, 18, 19 and 20.
  /// Written as plain values rather than `quant_id`: in 19 and 20 Odoo applies
  /// `quant_id` through a UI onchange, which does not run over RPC. Writing
  /// these makes Odoo's `write()` move the reservation to the new stock.
  Map<String, dynamic> get lineValues => {
    'lot_id': lotId ?? false,
    'location_id': locationId ?? false,
    'package_id': packageId ?? false,
    'owner_id': ownerId ?? false,
  };
}

/// Everything the screen loads in one go.
class DetailedOperations {
  final String pickingState;
  final int? companyId;
  final List<DetailedMove> moves;
  final List<DetailedLine> lines;

  const DetailedOperations({
    required this.pickingState,
    required this.companyId,
    required this.moves,
    required this.lines,
  });

  /// Odoo locks the lines once a transfer is done or cancelled.
  bool get isEditable => pickingState != 'done' && pickingState != 'cancel';

  DetailedMove? moveOf(DetailedLine line) {
    for (final m in moves) {
      if (m.id == line.moveId) return m;
    }
    return null;
  }
}

/// The quantity Odoo puts on a new line when "Pick From" is chosen
/// (`stock.move.line._compute_quantity`): what is still missing from the
/// move, capped by the stock available there; or, when the move is already
/// fully done, the stock available.
double defaultLineQuantity({
  required double demand,
  required double done,
  required double available,
}) {
  final quantity = demand > done
      ? (available < demand - done ? available : demand - done)
      : available;
  return quantity < 0 ? 0 : quantity;
}
