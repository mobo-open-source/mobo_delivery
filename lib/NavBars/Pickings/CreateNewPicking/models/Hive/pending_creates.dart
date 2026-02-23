import 'package:hive/hive.dart';

part 'pending_creates.g.dart';

/// Represents a stock picking creation request that could not be sent to Odoo
/// immediately due to lack of internet connection or server unavailability.
///
/// This model is stored locally using Hive to enable offline-first picking creation.
/// Once connectivity is restored, the app should retry sending these pending records
/// using `OdooCreatePickingService.createPicking()` with the stored `pickingData`.
@HiveType(typeId: 8)
class PendingCreates extends HiveObject {
  @HiveField(0)
  int pickingId;

  @HiveField(1)
  Map<String, dynamic> pickingData;

  /// Creates a new pending picking record to be synced later when online.
  ///
  /// [pickingId] should be a unique local identifier (often negative or generated).
  /// [pickingData] must contain all required fields expected by Odoo's picking creation.
  PendingCreates({
    required this.pickingId,
    required this.pickingData,
  });
}
