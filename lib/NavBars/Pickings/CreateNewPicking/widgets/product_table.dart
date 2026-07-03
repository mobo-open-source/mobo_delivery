import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../../shared/utils/globals.dart';
import '../models/stock_move.dart';

class ProductTable extends StatelessWidget {
  final List<StockMoveModel> moveProducts;
  final VoidCallback onAddLine;
  final void Function(int index) onEdit;
  final void Function(int index) onDelete;

  const ProductTable({
    Key? key,
    required this.moveProducts,
    required this.onAddLine,
    required this.onEdit,
    required this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (moveProducts.isEmpty)
            _buildEmptyState(isDark)
          else ...[
            _buildListHeader(isDark),
            const SizedBox(height: 8),
            ...moveProducts.asMap().entries.map(
              (e) => _buildProductCard(e.value, e.key, isDark),
            ),
            const SizedBox(height: 12),
            _buildAddLineButton(isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildListHeader(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '${moveProducts.length} product${moveProducts.length == 1 ? '' : 's'}',
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white54 : Colors.grey[600],
          ),
        ),
        TextButton.icon(
          onPressed: onAddLine,
          icon: const Icon(HugeIcons.strokeRoundedAdd01, size: 16),
          label: Text(
            'Add',
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: TextButton.styleFrom(
            foregroundColor: isDark ? Colors.white : Colors.black87,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _buildProductCard(StockMoveModel product, int index, bool isDark) {
    return GestureDetector(
      onTap: () => onEdit(index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            _buildProductImage(product),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.productName,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  _buildBadge(
                    'Qty',
                    _fmtQty(product.productUomQty),
                    isDark,
                    highlight: true,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => onDelete(index),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(
                  HugeIcons.strokeRoundedDelete02,
                  size: 18,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductImage(StockMoveModel product) {
    if (product.imageBase64 != null && product.imageBase64!.isNotEmpty) {
      try {
        final base64String = product.imageBase64!.contains(',')
            ? product.imageBase64!.split(',')[1]
            : product.imageBase64!;
        final bytes = base64Decode(base64String);
        return Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            image: DecorationImage(
              image: MemoryImage(bytes),
              fit: BoxFit.cover,
            ),
          ),
        );
      } catch (_) {}
    }
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppStyle.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        HugeIcons.strokeRoundedPackage,
        size: 22,
        color: AppStyle.primaryColor,
      ),
    );
  }

  Widget _buildBadge(
    String label,
    String value,
    bool isDark, {
    bool highlight = false,
  }) {
    final bgColor = highlight
        ? AppStyle.primaryColor.withValues(alpha: 0.1)
        : (isDark ? Colors.white10 : Colors.grey.shade100);
    final labelColor = highlight
        ? AppStyle.primaryColor
        : (isDark ? Colors.white38 : Colors.grey.shade500);
    final valueColor = highlight
        ? AppStyle.primaryColor
        : (isDark ? Colors.white70 : Colors.black87);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: labelColor,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  String _fmtQty(double value) =>
      value.truncateToDouble() == value ? value.toStringAsFixed(0) : '$value';

  Widget _buildEmptyState(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        children: [
          Icon(
            HugeIcons.strokeRoundedPackage,
            size: 48,
            color: isDark ? Colors.grey[600] : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No products added yet',
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add a product to get started',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: isDark ? Colors.grey[600] : Colors.grey[500],
            ),
          ),
          const SizedBox(height: 20),
          _buildAddLineButton(isDark),
        ],
      ),
    );
  }

  Widget _buildAddLineButton(bool isDark) {
    final bgColor = isDark ? Colors.grey[700]! : Colors.grey[500]!;
    final fgColor = isDark ? Colors.white : Colors.white;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onAddLine,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              HugeIcons.strokeRoundedPackageAdd,
              size: 18,
              color: fgColor,
            ),
            const SizedBox(width: 8),
            Text(
              'Add a product',
              style: GoogleFonts.manrope(
                color: fgColor,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
