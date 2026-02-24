import 'package:hive/hive.dart';

part 'picking_form.g.dart';

/// Represents a **stock picking** / transfer record (`stock.picking`) from Odoo,
/// cached in Hive for offline viewing, editing, and queuing actions (validate, cancel, update).
///
/// This is the **core model** used throughout the picking details screen:
/// • Displays header info (reference, partner, type, dates, state, origin, note…)
/// • Shows availability, return count, responsible user, company, etc.
/// • Stores enough data to support offline editing and sync queuing
///
/// Fields are mostly nullable to handle partial data or missing values from API/cache.
/// Many2one fields are stored as `List<dynamic>` (Odoo's `[id, display_name]` format).
@HiveType(typeId: 1)
class PickingForm {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final List<dynamic>? partnerId;

  @HiveField(3)
  final List<dynamic>? pickingTypeId;

  @HiveField(4)
  final String? scheduledDate;

  @HiveField(5)
  final String? dateDeadline;

  @HiveField(6)
  final String? dateDone;

  @HiveField(7)
  final String? productsAvailability;

  @HiveField(8)
  final String? origin;

  @HiveField(9)
  String state;

  @HiveField(10)
  final String? note;

  @HiveField(11)
  final String? moveType;

  @HiveField(12)
  final List<dynamic>? userId;

  @HiveField(13)
  final List<dynamic>? groupId;

  @HiveField(14)
  final List<dynamic>? companyId;

  @HiveField(15)
  final int returnCount;

  @HiveField(16)
  final List<int>? returnIds;

  @HiveField(17)
  final bool showCheckAvailability;

  @HiveField(18)
  final String? pickingTypeCode;

  @HiveField(19)
  final int? locationIdInt;

  @HiveField(20)
  final int? locationDestIdInt;

  PickingForm({
    required this.id,
    required this.name,
    this.partnerId,
    this.pickingTypeId,
    this.scheduledDate,
    this.dateDeadline,
    this.dateDone,
    this.productsAvailability,
    this.origin,
    required this.state,
    this.note,
    this.moveType,
    this.userId,
    this.groupId,
    this.companyId,
    required this.returnCount,
    this.returnIds,
    required this.showCheckAvailability,
    this.pickingTypeCode,
    this.locationIdInt,
    this.locationDestIdInt,
  });

  /// Creates a `PickingForm` from Odoo JSON response (search_read result)
  ///
  /// Handles type safety and fallbacks for missing/invalid fields.
  /// Uses safe casting with defaults where possible.
  factory PickingForm.fromJson(Map<String, dynamic> json) {
    return PickingForm(
      id: json['id'] is int ? json['id'] : 0,
      name: json['name'] is String ? json['name'] : '',
      partnerId: json['partner_id'] is List ? json['partner_id'] : null,
      pickingTypeId: json['picking_type_id'] is List ? json['picking_type_id'] : null,
      scheduledDate: json['scheduled_date'] is String ? json['scheduled_date'] : null,
      dateDeadline: json['date_deadline'] is String ? json['date_deadline'] : null,
      dateDone: json['date_done'] is String ? json['date_done'] : null,
      productsAvailability: json['products_availability'] is String ? json['products_availability'] : null,
      origin: json['origin'] is String ? json['origin'] : null,
      state: json['state'] is String ? json['state'] : 'draft',
      note: json['note'] is String ? json['note'] : (json['note'] == false ? null : json['note']?.toString()),
      moveType: json['move_type'] is String ? json['move_type'] : null,
      userId: json['user_id'] is List ? json['user_id'] : null,
      groupId: json['group_id'] is List ? json['group_id'] : null,
      companyId: json['company_id'] is List ? json['company_id'] : null,
      returnCount: json['return_count'] is int ? json['return_count'] : 0,
      returnIds: json['return_ids'] != null ? List<int>.from(json['return_ids']) : null,
      showCheckAvailability: json['show_check_availability'] is bool ? json['show_check_availability'] : false,
      pickingTypeCode: json['picking_type_code'] is String ? json['picking_type_code'] : null,
      locationIdInt: json['location_id_int'] is int ? json['location_id_int'] : null,
      locationDestIdInt: json['location_dest_id_int'] is int ? json['location_dest_id_int'] : null,
    );
  }

  /// Converts this picking to a JSON-compatible map
  ///
  /// Used when:
  /// • Saving to Hive (Hive handles it automatically)
  /// • Preparing data for pending queues
  /// • Debugging or logging
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'partner_id': partnerId,
      'picking_type_id': pickingTypeId,
      'scheduled_date': scheduledDate,
      'date_deadline': dateDeadline,
      'date_done': dateDone,
      'products_availability': productsAvailability,
      'origin': origin,
      'state': state,
      'note': note,
      'move_type': moveType,
      'user_id': userId,
      'group_id': groupId,
      'company_id': companyId,
      'return_count': returnCount,
      'return_ids': returnIds,
      'show_check_availability': showCheckAvailability,
      'picking_type_code': pickingTypeCode,
      'location_id_int': locationIdInt,
      'location_dest_id_int': locationDestIdInt,
    };
  }
}