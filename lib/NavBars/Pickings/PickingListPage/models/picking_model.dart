import 'package:hive/hive.dart';

part 'picking_model.g.dart';

/// Simplified / flattened representation of a stock picking / transfer,
/// optimized for fast display and filtering in list views (e.g. `PickingsGroupedPage`).
///
/// This model is **not** the full `stock.picking` record — it's a denormalized,
/// UI-focused version with string-based fields for quick rendering and search.
///
/// Main use cases:
/// • Showing picking cards in grouped or flat lists
/// • Filtering by item, state, partner, origin, warehouse, dates, etc.
/// • Avoiding repeated parsing of many2one lists in UI code
///
/// Most fields are stored as `String` (even IDs) to simplify search and display.
/// For detailed editing/validation, use `PickingForm` or fetch full record from Odoo/Hive.
@HiveType(typeId: 0)
class Picking extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String item;

  @HiveField(2)
  String scheduledDate;

  @HiveField(3)
  String deadlineDate;

  @HiveField(4)
  String state;

  @HiveField(5)
  String partner;

  @HiveField(6)
  String origin;

  @HiveField(7)
  List<Map<String, dynamic>> moveIds;

  @HiveField(8)
  String warehouseName;

  @HiveField(9)
  String partnerId;

  @HiveField(10)
  String pickingTypeCode;

  @HiveField(11)
  String pickingTypeId;

  @HiveField(12)
  String pickingTypeIdInt;

  @HiveField(13)
  String productAvailability;

  @HiveField(14)
  String returnCount;

  @HiveField(15)
  String showCheckAvailability;

  @HiveField(16)
  String locationIdInt;

  @HiveField(17)
  String locationDestIdInt;

  @HiveField(18)
  String moveType;

  @HiveField(19)
  String userId;

  @HiveField(20)
  String userIdInt;

  @HiveField(21)
  String groupId;

  @HiveField(22)
  String groupIdInt;

  @HiveField(23)
  String companyId;

  @HiveField(24)
  String companyIdInt;

  Picking({
    required this.id,
    required this.item,
    required this.scheduledDate,
    required this.deadlineDate,
    required this.state,
    required this.partner,
    required this.origin,
    required this.moveIds,
    required this.warehouseName,
    required this.partnerId,
    required this.pickingTypeCode,
    required this.pickingTypeId,
    required this.pickingTypeIdInt,
    required this.productAvailability,
    required this.returnCount,
    required this.showCheckAvailability,
    required this.locationIdInt,
    required this.locationDestIdInt,
    required this.moveType,
    required this.userId,
    required this.userIdInt,
    required this.groupId,
    required this.groupIdInt,
    required this.companyId,
    required this.companyIdInt,
  });
}
