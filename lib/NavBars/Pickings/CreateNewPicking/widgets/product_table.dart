import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../../shared/utils/globals.dart';
import '../models/stock_move.dart';

/// Product (stock move) section of the create-picking form.
///
/// Each added product is shown as a card — product thumbnail + name on top,
/// then a Demand / Quantity metric row — matching the sale-order line design
/// used in the mobo sales app. A styled "Add a line" button sits at the
/// bottom to open the product selection dialog.
class ProductTable extends StatelessWidget {
  /// List of stock move lines (products) currently added to the picking
  final List<StockMoveModel> moveProducts;

  /// Callback invoked when user taps "Add a line" to select and add a product
  final VoidCallback onAddLine;

  const ProductTable({
    Key? key,
    required this.moveProducts,
    required this.onAddLine,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (moveProducts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  'No products added yet',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : Colors.grey[500],
                  ),
                ),
              ),
            )
          else
            ...moveProducts.map((product) => _buildProductCard(product, isDark)),
          const SizedBox(height: 4),
          _buildAddLineButton(isDark),
        ],
      ),
    );
  }

  /// A single product line rendered as a card (sale-order line style from the
  /// mobo sales app: white surface, soft shadow, brand-colored product name,
  /// bordered thumbnail).
  Widget _buildProductCard(StockMoveModel product, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[850]! : Colors.grey[200]!,
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, 6),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppStyle.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                  ),
                ),
                child: const Icon(
                  HugeIcons.strokeRoundedPackage,
                  color: AppStyle.primaryColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    product.productName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppStyle.primaryColor,
                      letterSpacing: -0.1,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _metric('DEMAND', _fmtQty(product.productUomQty), isDark),
              ),
              Expanded(
                child: _metric('QUANTITY', _fmtQty(product.quantity), isDark),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.grey[500] : Colors.grey[600],
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.grey[900],
          ),
        ),
      ],
    );
  }

  /// Formats a quantity without a trailing ".0" for whole numbers.
  String _fmtQty(double value) =>
      value.truncateToDouble() == value ? value.toStringAsFixed(0) : '$value';

  Widget _buildAddLineButton(bool isDark) {
    return GestureDetector(
      onTap: onAddLine,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white24
                : AppStyle.primaryColor.withValues(alpha: 0.5),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add,
              size: 18,
              color: isDark ? Colors.white : AppStyle.primaryColor,
            ),
            const SizedBox(width: 6),
            Text(
              'Add a line',
              style: TextStyle(
                color: isDark ? Colors.white : AppStyle.primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
