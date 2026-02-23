import 'package:hive/hive.dart';

part 'user.g.dart';

/// Minimal representation of an Odoo user (`res.users`) record,
/// cached in Hive for offline usage in picking assignment and display flows.
///
/// This model stores only the two most essential fields:
/// - `id` (database identifier)
/// - `name` (display name — usually full name or login)
///
/// Used mainly for:
/// • Populating "Responsible" dropdowns when editing pickings
/// • Displaying assigned user name in picking details
/// • Offline selection of responsible users
@HiveType(typeId: 4)
class User {
  @HiveField(0)
  final int id;

  @HiveField(1)
  final String name;

  User({required this.id, required this.name});

  /// Creates a `User` instance from Odoo JSON response (search_read result)
  ///
  /// Handles missing fields with safe fallbacks:
  /// - `id`: defaults to 0
  /// - `name`: defaults to empty string
  ///
  /// Expected minimal JSON shape:
  /// ```json
  /// {
  ///   "id": 42,
  ///   "name": "Sara"
  /// }
  /// ```
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
    );
  }

  /// Converts this user to a simple JSON map
  ///
  /// Used when:
  /// • Saving back to Hive (Hive handles it automatically)
  /// • Preparing data for dropdowns or other serialization
  /// • Debugging or logging
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }
}