import 'package:equatable/equatable.dart';

/// Minimal representation of an Odoo user (from `res.users` model).
///
/// This model is typically used to:
/// - assign a responsible person to stock pickings/transfers
/// - display user names in dropdowns or assignment fields
/// - show who created/validated/processed a picking
///
/// Only the essential fields (id + name) are included to keep it lightweight.
class UserModel extends Equatable {
  final int id;
  final String name;

  const UserModel({
    required this.id,
    required this.name,
  });

  /// Creates a `UserModel` instance from Odoo `search_read` response data.
  ///
  /// Expected minimal JSON shape:
  /// ```json
  /// {
  ///   "id": 42,
  ///   "name": "Sara"
  /// }
  /// ```
  /// Throws if `id` or `name` are missing or have incorrect type.
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }

  /// Properties used for value-based equality comparison (via `equatable`).
  ///
  /// Two users are considered equal if they have the same `id` and `name`.
  @override
  List<Object?> get props => [id, name];
}