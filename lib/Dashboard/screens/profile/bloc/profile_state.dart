import 'package:equatable/equatable.dart';

import '../../../models/profile.dart';

/// Base class for all states emitted by [ProfileBloc].
///
/// All profile-related states extend this class to enable proper equality
/// comparison (via [Equatable]) which is essential for efficient rebuilding
/// in `BlocBuilder` and `BlocListener`.
abstract class ProfileState extends Equatable {
  const ProfileState();
  @override
  List<Object?> get props => [];
}

/// Initial/empty state before any profile operation has started.
class ProfileInitial extends ProfileState {}

/// Profile data is currently being loaded (from Odoo or Hive cache).
class ProfileLoading extends ProfileState {}

/// Profile data has been successfully loaded and is ready for display.
///
/// This is the main "happy path" state shown in the UI when profile details
/// are available (whether from network or offline cache).
class ProfileLoaded extends ProfileState {
  final Profile profile;
  final bool isEdited;

  const ProfileLoaded(this.profile, {this.isEdited = false});

  /// Creates a copy of this state with optional overrides.
  ///
  /// Commonly used in the bloc when:
  ///   - Temporarily updating preview image
  ///   - Toggling edit mode
  ProfileLoaded copyWith({Profile? profile, bool? isEdited}) {
    return ProfileLoaded(
      profile ?? this.profile,
      isEdited: isEdited ?? this.isEdited,
    );
  }

  @override
  List<Object?> get props => [profile, isEdited];
}

/// Profile is currently being saved to the Odoo server.
class ProfileSaving extends ProfileState {}

/// An error occurred during loading or saving the profile.
class ProfileError extends ProfileState {
  final String message;
  const ProfileError(this.message);

  @override
  List<Object?> get props => [message];
}
