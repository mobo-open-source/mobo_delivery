import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../shared/utils/globals.dart';
import '../../../../shared/widgets/empty_state.dart';

/// Displays the detailed list of stock move lines (individual product movements)
/// for a given stock picking / transfer.
///
/// Each move line is shown as an order-line-style card (matching the mobo
/// sales quotation order lines): product thumbnail + name on top, then a
/// metric row of Pick From / Lot-Serial / Quantity.
///
/// Features:
/// • Dark/light theme support
/// • Empty state with icon and message
/// • View-only (no tap actions)
/// • Data is passed pre-loaded from `PickingDetailsPage` (online or Hive cache)
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

  const StockMoveLineListPage({super.key, required this.pickingStockLine});

  /// Extracts display name from Odoo many2one field format [id, name].
  ///
  /// Returns the second element (display name) if value is a non-empty list,
  /// otherwise returns 'N/A'.
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
        forceMaterialTransparency: true,
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
          ? const EmptyState(
              title: 'No Stock Move Lines Found',
              subtitle: 'There are no stock move lines available.',
            )
          : _buildTable(context, isDark),
    );
  }

  Widget _buildTable(BuildContext context, bool isDark) {
    final verticalController = ScrollController();
    final horizontalController = ScrollController();
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey[300]!;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Scrollbar(
        controller: verticalController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: verticalController,
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            controller: horizontalController,
            scrollDirection: Axis.horizontal,
            child: Material(
              color: Colors.transparent,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: borderColor, width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Table(
                border: TableBorder(
                  horizontalInside: BorderSide(color: borderColor, width: 1),
                ),
                columnWidths: const {
                  0: FixedColumnWidth(200),
                  1: FixedColumnWidth(150),
                  2: FixedColumnWidth(160),
                  3: FixedColumnWidth(120),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF3A3A3A)
                          : const Color(0xFFF8F9FA),
                    ),
                    children: [
                      _headerCell('Product', isDark),
                      _headerCell('Pick From', isDark),
                      _headerCell('Lot/Serial', isDark),
                      _headerCell('Quantity', isDark),
                    ],
                  ),
                  ...pickingStockLine.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    final lot = getName(item['lot_id']);
                    final qty =
                        item['quantity_product_uom']?.toString() ?? 'N/A';
                    return TableRow(
                      children: [
                        _cell(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 22,
                                child: Text('${index + 1}.',
                                    style: _rowStyle(isDark)),
                              ),
                              Expanded(
                                child: Text(
                                  getName(item['product_id']),
                                  style: _rowStyle(isDark),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _cell(
                          child: Text(getName(item['location_id']),
                              style: _rowStyle(isDark)),
                        ),
                        _cell(
                          child: Text(lot == 'N/A' ? '—' : lot,
                              style: _rowStyle(isDark)),
                        ),
                        _cell(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppStyle.primaryColor,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                qty == 'N/A' ? '—' : qty,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  TableCell _headerCell(String text, bool isDark) {
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.grey[800],
          ),
        ),
      ),
    );
  }

  TableCell _cell({required Widget child}) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: child,
      ),
    );
  }

  TextStyle _rowStyle(bool isDark) => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: isDark ? Colors.grey[300] : Colors.grey[700],
      );
}
