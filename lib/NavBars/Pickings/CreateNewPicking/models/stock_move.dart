import 'package:equatable/equatable.dart';

/// Represents a single line/item (stock move) in an Odoo stock picking/transfer.
///
/// Corresponds to a record in the `stock.move` model.
/// Used to:
/// - display planned or done quantities in the UI
/// - prepare data when creating new moves
/// - show move details after creation or during editing
///
/// This is a **simplified/view-model** version — not all `stock.move` fields are included.
class StockMoveModel extends Equatable {
  final int productId;
  final String productName;
  final double productUomQty;
  final int productUomId;
  final double quantity;
  final String? imageBase64;

  const StockMoveModel({
    required this.productId,
    required this.productName,
    required this.productUomQty,
    required this.productUomId,
    required this.quantity,
    this.imageBase64,
  });

  @override
  List<Object?> get props => [
    productId,
    productName,
    productUomQty,
    productUomId,
    quantity,
  ];
}
