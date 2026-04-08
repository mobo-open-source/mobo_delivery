import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import '../../../../shared/utils/globals.dart';
import '../models/product.dart';

/// Dialog for adding a new product line (stock move) to a picking creation form.
///
/// Displays:
///   - Searchable dropdown of available products
///   - Quantity input field (numeric)
///   - Real-time validation (product required, quantity > 0)
///   - "Add" button (disabled until valid)
///   - Error messages below fields when validation fails
///
/// Calls `onAdd` callback with selected product and quantity when user confirms.
/// Designed to be shown via `showDialog`.
class AddProductDialog extends StatefulWidget {
  /// Full list of available products to choose from
  final List<ProductModel> products;

  /// Callback invoked when user confirms valid product + quantity
  final Function(ProductModel?, double) onAdd;

  const AddProductDialog({
    Key? key,
    required this.products,
    required this.onAdd,
  }) : super(key: key);

  @override
  State<AddProductDialog> createState() => _AddProductDialogState();
}

/// Manages state and validation logic for the add-product dialog.
///
/// Responsibilities:
///   - Initializes product dropdown and quantity controller
///   - Validates input on "Add" press
///   - Shows inline error messages for missing product or invalid quantity
///   - Calls parent callback and closes dialog on valid submission
class _AddProductDialogState extends State<AddProductDialog> {
  ProductModel? selectedProduct;
  final TextEditingController qtyController = TextEditingController(text: '1');
  String _errorMessage = '';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? Colors.grey[850] : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'Add a Product Line',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
        ],
      ),
      content: Container(
        height: _errorMessage.isNotEmpty
            ? MediaQuery.of(context).size.height * 0.20
            : MediaQuery.of(context).size.height * 0.18,
        width: MediaQuery.of(context).size.width * 0.95,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Product selection
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Product",
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white60 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 5),
                  DropdownSearch<ProductModel>(
                    popupProps: PopupProps.menu(
                      showSearchBox: true,
                      searchFieldProps: TextFieldProps(
                        decoration: InputDecoration(
                          hintText: "Search Product",
                          hintStyle: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    items: widget.products,
                    itemAsString: (item) => item.name,
                    onChanged: (value) {
                      setState(() {
                        selectedProduct = value;
                      });
                    },
                    dropdownDecoratorProps: DropDownDecoratorProps(
                      dropdownSearchDecoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        hintText: "Select Product",
                        hintStyle: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white60 : Colors.black87,
                        ),
                        prefixIcon: Icon(
                          Icons.inventory_2,
                          color: isDark ? Colors.grey[400] : Colors.grey[500],
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white24 : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: isDark
                                ? Colors.white
                                : AppStyle.primaryColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    validator: (value) =>
                        value == null ? 'Please select a product' : null,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Quantity input
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Quantity",
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white60 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 5),
                  TextField(
                    controller: qtyController,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      hintText: 'Add Quantity',
                      hintStyle: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white60 : Colors.black87,
                      ),
                      prefixIcon: Icon(
                        Icons.format_list_numbered,
                        color: isDark ? Colors.grey[400] : Colors.grey[500],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDark ? Colors.white24 : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: isDark ? Colors.white : AppStyle.primaryColor,
                          width: 2,
                        ),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Error message (shown below fields)
              if (_errorMessage.isNotEmpty)
                Text(
                  _errorMessage,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
            ],
          ),
        ),
      ),

      // Action buttons
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white : Colors.black87,
                  side: BorderSide(
                    color: isDark ? Colors.white : Color(0xFFBB2649),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                child: Text(
                  "CANCEL",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppStyle.primaryColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  final enteredQty =
                      double.tryParse(qtyController.text.trim()) ?? 0.0;

                  if (selectedProduct == null) {
                    setState(() {
                      _errorMessage = "Please select a product.";
                    });
                  } else if (enteredQty <= 0) {
                    setState(() {
                      _errorMessage = "Quantity must be greater than zero.";
                    });
                  } else {
                    setState(() {
                      _errorMessage = '';
                    });
                    widget.onAdd(selectedProduct, enteredQty);
                    Navigator.of(context).pop();
                  }
                },
                icon: Icon(
                  Icons.add,
                  color: isDark ? Colors.black : Colors.white,
                ),
                label: Text(
                  'Add',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.black : Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark
                      ? Colors.white
                      : AppStyle.primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
