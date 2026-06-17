import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../shared/utils/globals.dart';

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

  const StockMoveLineListPage({Key? key, required this.pickingStockLine})
    : super(key: key);

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
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: pickingStockLine.length,
              itemBuilder: (context, index) =>
                  _buildMoveLineCard(pickingStockLine[index], isDark),
            ),
    );
  }

  /// A single move line rendered as an order-line-style card.
  Widget _buildMoveLineCard(Map<String, dynamic> item, bool isDark) {
    final product = getName(item['product_id']);
    final location = getName(item['location_id']);
    final lot = getName(item['lot_id']);
    final qty = item['quantity_product_uom']?.toString() ?? 'N/A';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppStyle.primaryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  HugeIcons.strokeRoundedPackage,
                  color: AppStyle.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    product,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.grey[900],
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: _metric('PICK FROM', location, isDark),
              ),
              Expanded(
                flex: 3,
                child: _metric(
                  'LOT/SERIAL',
                  lot == 'N/A' ? '—' : lot,
                  isDark,
                ),
              ),
              Expanded(
                flex: 2,
                child: _metric(
                  'QUANTITY',
                  qty == 'N/A' ? '—' : qty,
                  isDark,
                  alignEnd: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(
    String label,
    String value,
    bool isDark, {
    bool alignEnd = false,
  }) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.grey[900],
          ),
        ),
      ],
    );
  }
}
