import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../shared/utils/globals.dart';

/// Displays the detailed list of stock move lines (individual product movements)
/// for a given stock picking / transfer.
///
/// This page shows a horizontal-scrollable DataTable with the following columns:
/// - Product
/// - Pick From (source location)
/// - Lot/Serial Number (if tracked)
/// - Quantity (in product's UoM)
///
/// Features:
/// • Dark/light theme support
/// • Empty state with icon and message
/// • Tapping is not enabled (view-only page)
/// • Data is passed pre-loaded from `PickingDetailsPage` (online fetch or Hive cache)
///
/// Data format: List of raw maps from Odoo's `stock.move.line` model
class StockMoveLineListPage extends StatelessWidget {
  /// List of stock move line data maps
  /// Expected keys (typical Odoo fields):
  ///   - 'product_id'     → [id, name]
  ///   - 'location_id'    → [id, name] (source location)
  ///   - 'lot_id'         → [id, name] or false
  ///   - 'quantity_product_uom' → double (done quantity in product's UoM)
  final List<Map<String, dynamic>> pickingStockLine;

  const StockMoveLineListPage({Key? key, required this.pickingStockLine})
    : super(key: key);

  /// Extracts display name from Odoo many2one field format [id, name]
  ///
  /// Returns the second element (display name) if value is a non-empty list,
  /// otherwise returns 'N/A'.
  /// Used for product, location, and lot/serial fields.
  String getName(dynamic value) {
    if (value is List && value.length > 1) {
      return value[1].toString();
    }
    return 'N/A';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],

      appBar: AppBar(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        title: Text(
          'Stock Move Lines',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
            fontSize: 22,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            HugeIcons.strokeRoundedArrowLeft01,
            color: isDark ? Colors.white : Colors.black,
            size: 28,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: pickingStockLine.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    HugeIcons.strokeRoundedDeliveryBox02,
                    color: isDark ? Colors.white : AppStyle.primaryColor,
                    size: 80,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Stock Move Lines Found',
                    style: TextStyle(
                      fontSize: 18,
                      color: isDark ? Colors.white : AppStyle.primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(12.0),
              child: Container(
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[850] : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withOpacity(0.18)
                          : Colors.black.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: DataTable(
                      headingRowColor: MaterialStateProperty.all(
                        isDark ? Color(0x66757575) : Colors.grey.shade200,
                      ),
                      columnSpacing: 28,
                      dataRowHeight: 56,
                      headingTextStyle: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppStyle.primaryColor,
                      ),
                      columns: const [
                        DataColumn(label: Text('Product')),
                        DataColumn(label: Text('Pick From')),
                        DataColumn(label: Text('Lot/Serial Number')),
                        DataColumn(label: Text('Quantity')),
                      ],
                      rows: pickingStockLine.map((item) {
                        return DataRow(
                          cells: [
                            DataCell(
                              Text(
                                getName(item['product_id']),
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                getName(item['location_id']),
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                getName(item['lot_id']),
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                item['quantity_product_uom']
                                        ?.toString()
                                        .toUpperCase() ??
                                    'N/A',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
