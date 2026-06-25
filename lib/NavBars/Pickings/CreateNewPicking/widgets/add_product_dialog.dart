import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../../shared/utils/globals.dart';
import '../../../../shared/widgets/buttons/mobo_button.dart';
import '../../../../shared/widgets/inputs/mobo_text_field.dart' show MoboTextField, RequiredLabel;
import '../models/product.dart';

class AddProductDialog extends StatefulWidget {
  final List<ProductModel> products;
  final Function(ProductModel?, double) onAdd;

  const AddProductDialog({
    Key? key,
    required this.products,
    required this.onAdd,
  }) : super(key: key);

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<AddProductDialog> {
  ProductModel? selectedProduct;
  final TextEditingController qtyController = TextEditingController(text: '1');
  String _errorMessage = '';

  @override
  void dispose() {
    qtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? Colors.grey[850] : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Add a Product Line',
        style: TextStyle(
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
          const SizedBox(height: 5),
          DropdownSearch<ProductModel>(
                popupProps: PopupProps.menu(
                  menuProps: MenuProps(
                    backgroundColor:
                        isDark ? Colors.grey[900] : Colors.grey[50],
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  showSearchBox: true,
                  searchFieldProps: TextFieldProps(
                    decoration: InputDecoration(
                      hintText: 'Search products...',
                      hintStyle: TextStyle(
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
                      fillColor: isDark ? Colors.grey[850] : Colors.grey[100],
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
                ),
                items: widget.products,
                itemAsString: (item) => item.name,
                onChanged: (value) {
                  setState(() {
                    selectedProduct = value;
                    _errorMessage = '';
                  });
                },
                dropdownDecoratorProps: DropDownDecoratorProps(
                  dropdownSearchDecoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    hintText: 'Select Product',
                    hintStyle: TextStyle(
                      fontWeight: FontWeight.w400,
                      color: isDark ? Colors.white54 : Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                    prefixIcon: Icon(
                      HugeIcons.strokeRoundedPackage,
                      color: isDark ? Colors.grey[400] : Colors.grey[500],
                    ),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF2A2A2A)
                        : const Color(0xFFF8FAFB),
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
                validator: (value) =>
                    value == null ? 'Please select a product' : null,
              ),
              const SizedBox(height: 16),
              RequiredLabel(
                "Quantity",
                isRequired: true,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white60 : Colors.black87,
              ),
              const SizedBox(height: 5),
              MoboTextField(
                controller: qtyController,
                hintText: 'Enter quantity',
                keyboardType: TextInputType.number,
                showShadow: false,
                prefixIcon: Icon(
                  HugeIcons.strokeRoundedPinCode,
                  color: isDark ? Colors.grey[400] : Colors.grey[500],
                ),
              ),
          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _errorMessage,
              style: const TextStyle(
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
                label: 'Add',
                icon: HugeIcons.strokeRoundedAdd01,
                borderRadius: 8,
                onPressed: () {
                  final enteredQty =
                      double.tryParse(qtyController.text.trim()) ?? 0.0;
                  if (selectedProduct == null) {
                    setState(
                      () => _errorMessage = 'Please select a product.',
                    );
                  } else if (enteredQty <= 0) {
                    setState(
                      () =>
                          _errorMessage = 'Quantity must be greater than zero.',
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
