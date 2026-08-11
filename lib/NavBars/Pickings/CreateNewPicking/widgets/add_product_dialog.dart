import 'dart:convert';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../../shared/utils/globals.dart';
import '../../../../shared/widgets/buttons/mobo_button.dart';
import '../../../../shared/widgets/inputs/mobo_text_field.dart'
    show MoboTextField, RequiredLabel;
import '../models/product.dart';

class AddProductDialog extends StatefulWidget {
  final List<ProductModel> products;
  final Function(ProductModel?, double) onAdd;
  final ProductModel? initialProduct;
  final double? initialQuantity;

  const AddProductDialog({
    Key? key,
    required this.products,
    required this.onAdd,
    this.initialProduct,
    this.initialQuantity,
  }) : super(key: key);

  bool get isEditMode => initialProduct != null;

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  ProductModel? selectedProduct;
  late final TextEditingController qtyController;
  String _errorMessage = '';
  bool _isDropdownOpen = false;

  @override
  void initState() {
    super.initState();
    selectedProduct = widget.initialProduct;
    qtyController = TextEditingController(
      text: widget.initialQuantity != null
          ? _fmtQty(widget.initialQuantity!)
          : '1',
    );
  }

  String _fmtQty(double v) =>
      v.truncateToDouble() == v ? v.toStringAsFixed(0) : '$v';

  @override
  void dispose() {
    qtyController.dispose();
    super.dispose();
  }

  Widget _buildProductImage(ProductModel product, {double size = 40}) {
    if (product.imageBase64 != null && product.imageBase64!.isNotEmpty) {
      try {
        final base64String = product.imageBase64!.contains(',')
            ? product.imageBase64!.split(',')[1]
            : product.imageBase64!;
        final bytes = base64Decode(base64String);
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            image: DecorationImage(
              image: MemoryImage(bytes),
              fit: BoxFit.cover,
            ),
          ),
        );
      } catch (_) {}
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppStyle.primaryColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        HugeIcons.strokeRoundedPackage,
        size: size * 0.45,
        color: AppStyle.primaryColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? Colors.grey[850] : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.isEditMode ? 'Edit Product' : 'Add a Product',
        style: GoogleFonts.manrope(
          fontWeight: FontWeight.w600,
          fontSize: 18,
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.95,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RequiredLabel(
              "Product",
              isRequired: true,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : Colors.black87,
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: isDark
                    ? const Color(0xFF2A2A2A)
                    : const Color(0xFFF8FAFB),
                border: Border.all(
                  color: _isDropdownOpen
                      ? AppStyle.primaryColor
                      : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: DropdownSearch<ProductModel>(
                onBeforePopupOpening: (_) async {
                  setState(() => _isDropdownOpen = true);
                  return true;
                },
                popupProps: PopupProps.menu(
                  onDismissed: () => setState(() => _isDropdownOpen = false),
                  menuProps: MenuProps(
                    backgroundColor: isDark ? Colors.grey[900] : Colors.white,
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  showSearchBox: true,
                  searchFieldProps: TextFieldProps(
                    decoration: InputDecoration(
                      hintText: 'Search products...',
                      hintStyle: GoogleFonts.manrope(
                        fontWeight: FontWeight.w400,
                        color: isDark ? Colors.white54 : Colors.grey[500],
                        fontStyle: FontStyle.italic,
                      ),
                      prefixIcon: Icon(
                        HugeIcons.strokeRoundedSearch01,
                        size: 20,
                        color: isDark ? Colors.white54 : Colors.grey[500],
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xffF8FAFB),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppStyle.primaryColor,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),

                  itemBuilder: (context, product, isSelected) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          _buildProductImage(product, size: 38),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              product.cleanName,
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? AppStyle.primaryColor
                                    : (isDark ? Colors.white : Colors.black87),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: AppStyle.primaryColor,
                            ),
                        ],
                      ),
                    );
                  },
                ),
                items: widget.products,
                selectedItem: selectedProduct,
                itemAsString: (item) => item.cleanName,
                onChanged: (value) {
                  setState(() {
                    selectedProduct = value;
                    _errorMessage = '';
                  });
                },
                dropdownBuilder: (context, item) {
                  if (item == null) {
                    return Text(
                      'Select a product',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                        color: isDark ? Colors.white54 : Colors.grey[500],
                      ),
                    );
                  }
                  return Row(
                    children: [
                      _buildProductImage(item, size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.cleanName,
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  );
                },
                dropdownDecoratorProps: DropDownDecoratorProps(
                  dropdownSearchDecoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    prefixIcon: selectedProduct == null
                        ? Icon(
                            HugeIcons.strokeRoundedPackage,
                            size: 20,
                            color: isDark ? Colors.grey[400] : Colors.grey[500],
                          )
                        : null,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
                validator: (value) =>
                    value == null ? 'Please select a product' : null,
              ),
            ),
            const SizedBox(height: 16),
            RequiredLabel(
              "Quantity",
              isRequired: true,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : Colors.black87,
            ),
            const SizedBox(height: 8),
            MoboTextField(
              controller: qtyController,
              hintText: 'Enter quantity',
              keyboardType: TextInputType.number,
              prefixIcon: Icon(
                HugeIcons.strokeRoundedPinCode,
                size: 20,
                color: isDark ? Colors.grey[400] : Colors.grey[500],
              ),
            ),
            if (_errorMessage.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage,
                style: GoogleFonts.manrope(
                  color: Colors.red,
                  fontWeight: FontWeight.w400,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: MoboButton.secondary(
                label: 'CANCEL',
                borderRadius: 8,
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MoboButton.primary(
                label: widget.isEditMode ? 'Update' : 'Add',
                icon: widget.isEditMode
                    ? HugeIcons.strokeRoundedPencilEdit01
                    : HugeIcons.strokeRoundedPackageAdd,
                borderRadius: 8,
                onPressed: selectedProduct == null
                    ? null
                    : () {
                        final enteredQty =
                            double.tryParse(qtyController.text.trim()) ?? 0.0;
                        if (enteredQty <= 0) {
                          setState(
                            () => _errorMessage =
                                'Quantity must be greater than zero.',
                          );
                        } else {
                          widget.onAdd(selectedProduct, enteredQty);
                          Navigator.of(context).pop();
                        }
                      },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
