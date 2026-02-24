import 'package:hive/hive.dart';

part 'pending_updates.g.dart';

/// Represents a **pending update** to a stock picking header that could not be saved to Odoo
/// immediately due to lack of internet connection or server unavailability.
///
/// This model is stored in Hive to implement offline-first editing of picking details.
/// Once connectivity is restored, the app should retry applying these updates using
/// `OdooPickingFormService.saveChanges()` with the stored `pickingData` map.
///
/// The `pickingData` map typically contains the changed fields only (e.g. partner_id,
/// scheduled_date, origin, note, user_id, move_type, etc.).
@HiveType(typeId: 7)
class PendingUpdates extends HiveObject {
  @HiveField(0)
  final int pickingId;

  @HiveField(1)
  final Map<String, dynamic> pickingData;


  PendingUpdates({
    required this.pickingId,
    required this.pickingData,
  });
}
