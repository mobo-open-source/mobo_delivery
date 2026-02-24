import 'package:hive/hive.dart';

part 'profile.g.dart';

/// A data model representing a user's profile information.
///
/// This class is designed to be stored persistently using **Hive**,
/// a lightweight and fast NoSQL database for Flutter and Dart applications.
///
/// All fields are nullable to support partial profile data.
@HiveType(typeId: 11)
class Profile extends HiveObject {
  @HiveField(0)
  String? name;

  @HiveField(1)
  String? email;

  @HiveField(2)
  String? phone;

  @HiveField(3)
  String? company;

  @HiveField(4)
  String? mapToken;

  @HiveField(5)
  String? profileImage;

  @HiveField(6)
  String? mobile;

  @HiveField(7)
  String? website;

  @HiveField(8)
  String? jobTitle;

  /// Creates a new [Profile] instance.
  ///
  /// All parameters are optional and nullable.
  Profile({
    this.name,
    this.email,
    this.phone,
    this.company,
    this.mapToken,
    this.profileImage,
    this.mobile,
    this.website,
    this.jobTitle,
  });

  /// Creates a copy of this [Profile] with some fields replaced with new values.
  ///
  /// Any parameter that is null keeps the original value.
  /// Useful for immutable-style updates.
  ///
  /// Example:
  /// ```dart
  /// final updated = profile.copyWith(
  ///   name: "Sara",
  ///   jobTitle: "Lead Developer",
  /// );
  /// ```
  Profile copyWith({
    String? name,
    String? email,
    String? phone,
    String? company,
    String? mapToken,
    String? profileImage,
    String? mobile,
    String? website,
    String? jobTitle,
  }) {
    return Profile(
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      company: company ?? this.company,
      mapToken: mapToken ?? this.mapToken,
      profileImage: profileImage ?? this.profileImage,
      mobile: mobile ?? this.mobile,
      website: website ?? this.website,
      jobTitle: jobTitle ?? this.jobTitle,
    );
  }
}
