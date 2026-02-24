import 'package:hive/hive.dart';

part 'return_picking.g.dart';

/// Represents a **return picking** (reverse transfer / return delivery) record
/// linked to an original stock picking, cached in Hive for offline access.
///
/// This model is used to:
/// • Display list of returns associated with a main picking (`PickingDetailsPage`)
/// • Show return details (reference, partner, date, origin, state) even when offline
/// • Navigate to detailed view of a return picking
///
/// Data is typically fetched via `OdooPickingFormService.loadReturnPickings()`
/// and stored per original picking ID for quick retrieval.
@HiveType(typeId: 14)
class ReturnPicking extends HiveObject {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final int pickingId;

  @HiveField(2)
  final String name;

  @HiveField(3)
  final int partnerId;

  @HiveField(4)
  final String scheduledDate;

  @HiveField(5)
  final String origin;

  @HiveField(6)
  final String state;

  @HiveField(7)
  final Map<String, dynamic> data;

  ReturnPicking({
    required this.id,
    this.pickingId = 0,
    required this.name,
    required this.partnerId,
    required this.scheduledDate,
    required this.origin,
    required this.state,
    required this.data,
  });
}
