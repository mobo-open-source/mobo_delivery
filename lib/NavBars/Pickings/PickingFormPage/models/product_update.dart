import 'package:hive/hive.dart';

part 'product_update.g.dart';

/// Represents a **pending update or addition** of a product line (stock move)
/// in a picking that could not be sent to Odoo immediately due to offline state.
///
/// This model is queued in Hive when the user adds or modifies a move line
/// while offline (e.g. via the "Add a line" or edit dialog in `PickingDetailsPage`).
///
/// When connectivity returns, the app should retry creating/updating the move
/// using `OdooPickingFormService.addProductToLine()` or `updateProductMove()`
/// with the data stored in `productData`.
@HiveType(typeId: 9)
class ProductUpdates extends HiveObject {
  @HiveField(0)
  int pickingId;

  @HiveField(1)
  Map<String, dynamic> productData;

  @HiveField(2)
  String? pickingName;

  ProductUpdates({
    required this.pickingId,
    required this.productData,
    required this.pickingName,
  });
}

