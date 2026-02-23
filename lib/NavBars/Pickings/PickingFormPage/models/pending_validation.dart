import 'package:hive/hive.dart';

part 'pending_validation.g.dart';

/// Represents a **pending validation** action on a stock picking that could not be
/// executed immediately due to no internet connection or server unavailability.
///
/// This model is stored in Hive to support offline-first validation of pickings.
/// When the device comes back online, the app should retry calling
/// `OdooPickingFormService.validatePicking()` using the stored `pickingId`.
///
/// The `pickingData` map usually contains a snapshot of the picking at the time
/// of queuing (useful for conflict detection or display in sync queue UI).
@HiveType(typeId: 6)
class PendingValidation extends HiveObject {
  @HiveField(0)
  final int pickingId;

  @HiveField(1)
  final Map<String, dynamic> pickingData;

  PendingValidation({
    required this.pickingId,
    required this.pickingData,
  });
}