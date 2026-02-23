import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/profile.dart';
import '../../../services/encryption_service.dart';
import '../../../services/hive_profile_service.dart';
import '../../../services/odoo_dashboard_service.dart';
import '../../../services/storage_service.dart';
import 'profile_event.dart';
import 'profile_state.dart';

/// Manages profile loading, updating, and image picking logic for the user profile screen.
///
/// Handles:
///   • Loading profile data (online from Odoo / offline from Hive)
///   • Updating profile fields via Odoo RPC
///   • Handling profile picture selection (base64 → temporary state update)
///   • Version-aware mobile field mapping (Odoo <18 vs ≥18)
///   • Encrypted map token storage at company level
class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final OdooDashboardService odooService;
  final DashboardStorageService storageService;
  final EncryptionService encryptionService;

  ProfileBloc({
    required this.odooService,
    required this.storageService,
    required this.encryptionService,
  }) : super(ProfileInitial()) {
    on<LoadProfile>(_onLoadProfile);
    on<UpdateProfile>(_onUpdateProfile);
    on<PickProfileImage>(_onPickProfileImage);
  }

  /// Loads the current user's profile data.
  ///
  /// Flow:
  /// 1. Check network connectivity
  /// 2. Online → fetch from Odoo → save to Hive
  /// 3. Offline → load from Hive
  /// 4. Emit [ProfileLoaded] or [ProfileError]
  Future<void> _onLoadProfile(LoadProfile event,
      Emitter<ProfileState> emit) async {
    emit(ProfileLoading());
    try {
      final prefs = await SharedPreferences.getInstance();
      int version = prefs.getInt('version') ?? 0;
      final sessionData = await storageService.getSessionData();
      final userId = sessionData['userId'];
      bool isOnline = await odooService.checkNetworkConnectivity();
      Profile? profile;

      if (isOnline) {
        final userDetails = await odooService.getUserProfile(userId ?? 0);
        String? profileImage;
        final imgValue = userDetails?['image_1920'];
        if (imgValue is String) {
          profileImage = imgValue;
        } else {
          profileImage = null;
        }

        String mobile = '';
        if (userDetails != null) {
          if (version < 18) {
            mobile = (userDetails['mobile'] is String) ? userDetails['mobile']! : '';
          } else {
            mobile = (userDetails['mobile_phone'] is String) ? userDetails['mobile_phone']! : '';
          }
        }
        profile = Profile(
            name: userDetails?['name'],
            email: userDetails?['email'],
            phone: userDetails?['phone'],
            mobile: mobile,
            company: userDetails?['company_id'] != null &&
                (userDetails!['company_id'] as List).isNotEmpty
                ? userDetails['company_id'][1].toString()
                : '',
            website: userDetails?['website'],
            jobTitle: userDetails?['position'],
            profileImage: profileImage,
            mapToken: (await storageService.getSessionData())['mapToken']
                ?.toString() ?? ''
        );

        // Persist fresh data locally
        await HiveProfileService().saveProfile(profile);
      } else {
        profile = await HiveProfileService().getProfile();
      }

      if (profile != null) {
        emit(ProfileLoaded(profile));
      } else {
        emit(const ProfileError("Failed to load profile"));
      }
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  /// Updates the user's profile on the Odoo server.
  ///
  /// After successful update:
  ///   • Handles map token encryption & storage (if provided)
  ///   • Triggers a fresh profile reload via [LoadProfile]
  Future<void> _onUpdateProfile(UpdateProfile event,
      Emitter<ProfileState> emit) async {
    emit(ProfileSaving());
    try {
      final sessionData = await storageService.getSessionData();
      final userId = sessionData['userId'];
      final companyId = sessionData['companyId'];

      final success = await odooService.updateUserProfile(
          userId ?? 0, event.updateData);
      if (success) {
        // Handle map token separately (company-level field)
        final mapToken = event.updateData['mapToken'];
        if (mapToken is String && mapToken.isNotEmpty) {
          final encryptedToken = encryptionService.encryptText(mapToken);
          await odooService.createMapKeyField(companyId ?? 1, encryptedToken);
          await storageService.saveMapToken(mapToken);
        }

        // Reload fresh data to reflect changes
        add(LoadProfile());
      } else {
        emit(const ProfileError("Failed to update profile"));
      }
    } catch (e) {
      emit(ProfileError(e.toString()));
    }
  }

  /// Temporarily updates the profile image in the current state
  /// (used during edit mode before final save)
  Future<void> _onPickProfileImage(PickProfileImage event,
      Emitter<ProfileState> emit) async {
    if (state is ProfileLoaded) {
      final current = (state as ProfileLoaded);
      final updatedProfile = current.profile.copyWith(
          profileImage: event.base64Image);
      emit(current.copyWith(profile: updatedProfile, isEdited: true));
    }
  }
}
