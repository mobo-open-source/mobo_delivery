import 'package:hive/hive.dart';

part 'partner_details.g.dart';

/// Stores detailed information about an Odoo partner (`res.partner`) for offline display
/// in the picking details screen — specifically the formatted address and base64-encoded avatar.
///
/// This model is cached in Hive after fetching from Odoo so that:
/// • Partner name + address + image can be shown even when offline
/// • No repeated RPC calls are needed for the same partner
/// • Image is stored as base64 string (from Odoo's `image_1920` field)
///
/// Typically used in `PickingDetailsPage` to show partner avatar and full address below the name.
@HiveType(typeId: 12)
class PartnerDetails extends HiveObject {
  @HiveField(0)
  int id;

  @HiveField(1)
  String? address;

  @HiveField(2)
  String? imageBase64;

  PartnerDetails({
    required this.id,
    this.address,
    this.imageBase64,
  });

  /// Creates a `PartnerDetails` instance from JSON (usually from service layer)
  ///
  /// Expects keys:
  /// - `id`         (required)
  /// - `address`    (optional)
  /// - `image_1920` (optional base64 string)
  ///
  /// Safe defaults: `id: 0`, `address: null`, `imageBase64: null`
  factory PartnerDetails.fromJson(Map<String, dynamic> json) {
    return PartnerDetails(
      id: json['id'] ?? 0,
      address: json['address'],
      imageBase64: json['image_1920'],
    );
  }

  /// Converts this object back to a JSON-compatible map
  ///
  /// Used when:
  /// • Saving to Hive (already done automatically by Hive)
  /// • Preparing data for UI display or debugging
  /// • Potentially sending back to other services
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'address': address,
      'image_1920': imageBase64,
    };
  }
}
