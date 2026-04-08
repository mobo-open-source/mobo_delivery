import 'package:hive_ce/hive.dart';

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
  String? street;

  @HiveField(9)
  String? street2;

  @HiveField(10)
  String? city;

  @HiveField(11)
  String? zip;

  @HiveField(12)
  int? countryId;

  @HiveField(13)
  int? stateId;

  @HiveField(14)
  String? countryName;

  @HiveField(15)
  String? stateName;

  @HiveField(16)
  String? function;

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
    this.street,
    this.street2,
    this.city,
    this.zip,
    this.countryId,
    this.stateId,
    this.countryName,
    this.stateName,
    this.function,
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
    String? street,
    String? street2,
    String? city,
    String? zip,
    int? countryId,
    int? stateId,
    String? countryName,
    String? stateName,
    String? function,
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
      street: street ?? this.street,
      street2: street2 ?? this.street2,
      city: city ?? this.city,
      zip: zip ?? this.zip,
      countryId: countryId ?? this.countryId,
      stateId: stateId ?? this.stateId,
      countryName: countryName ?? this.countryName,
      stateName: stateName ?? this.stateName,
      function: function ?? this.function,
    );
  }
}
