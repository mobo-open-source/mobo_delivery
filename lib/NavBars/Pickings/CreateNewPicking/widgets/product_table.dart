import 'package:flutter/material.dart';
import '../../../../shared/utils/globals.dart';
import '../models/stock_move.dart';

/// A compact table-like widget displaying the list of products (stock moves) in a picking creation form.
///
/// Shows:
///   - Header row with columns: "Product", "Demand", "Quantity"
///   - One row per added product with name, demanded quantity, and recorded quantity
///   - "+ Add a line" tappable text at the bottom to open product selection dialog
///
/// Designed to be used inside a tab or scrollable section of the create-picking screen.
/// Supports dark/light theme and dynamic rebuild when products are added/removed.
class ProductTable extends StatelessWidget {
  /// List of stock move lines (products) currently added to the picking
  final List<StockMoveModel> moveProducts;

  /// Callback invoked when user taps "+ Add a line" to select and add a new product
  final VoidCallback onAddLine;

  const ProductTable({
    Key? key,
    required this.moveProducts,
    required this.onAddLine,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Build rows dynamically for each product
    List<Widget> productRows = [];
    for (var product in moveProducts) {
      productRows.add(
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Text(
                  product.productName,
                  style: TextStyle(
                    fontWeight: FontWeight.normal,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  product.productUomQty.toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.normal,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  product.quantity.toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.normal,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      "Product",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      "Demand",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      "Quantity",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),

            // Product rows
            ...productRows,
            const SizedBox(height: 12),

            // Add line button
            GestureDetector(
              onTap: onAddLine,
              child: Text(
                "+ Add a line",
                style: TextStyle(
                  color: isDark ? Colors.white : AppStyle.primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
