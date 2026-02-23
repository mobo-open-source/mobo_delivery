import 'package:equatable/equatable.dart';

/// Base class for all events in the [ProfileBloc].
///
/// All profile-related events must extend this class to ensure proper
/// equality comparison (via [Equatable]) which is required for correct
/// Bloc behavior and rebuilding only when necessary.
abstract class ProfileEvent extends Equatable {
  const ProfileEvent();
  @override
  List<Object?> get props => [];
}

/// Triggers loading of the current user's profile data.
///
/// This event is typically dispatched when:
///   • The profile settings screen is opened
///   • After a successful update to refresh displayed data
///   • When recovering from offline → online transition
///
/// The bloc will attempt to load from Odoo if online, otherwise from Hive cache.
class LoadProfile extends ProfileEvent {}

/// Requests an update to one or more profile fields on the Odoo server.
///
/// Usage example:
/// ```dart
/// context.read<ProfileBloc>().add(UpdateProfile({
///   'name': 'Sara',
///   'mobile_phone': '+97 1234567890',
///   'image_1920': base64ImageString,
/// }));
/// ```
///
/// After a successful update, the bloc usually dispatches [LoadProfile] automatically
/// to refresh the UI with server-confirmed data.
class UpdateProfile extends ProfileEvent {
  /// Map of field names to new values that should be sent to Odoo.
  /// Common keys: 'name', 'email', 'phone', 'mobile'/'mobile_phone', 'image_1920', etc.
  final Map<String, dynamic> updateData;
  const UpdateProfile(this.updateData);

  @override
  List<Object?> get props => [updateData];
}

/// Notifies the bloc that the user has selected/changed their profile picture.
///
/// This event is usually fired immediately after image picking/cropping,
/// before the final save. It updates the in-memory state so the UI can
/// show a preview during edit mode.
///
/// The actual upload to Odoo happens when [UpdateProfile] is called
/// with the 'image_1920' key containing the base64 string.
class PickProfileImage extends ProfileEvent {
  final String base64Image;
  const PickProfileImage(this.base64Image);

  @override
  List<Object?> get props => [base64Image];
}
