import 'dart:async';
import 'package:bloc/bloc.dart';
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
    on<LoadCountries>(_onLoadCountries);
    on<LoadStates>(_onLoadStates);
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
      final sessionData = await storageService.getSessionData();
      final userId = sessionData['userId'];
      bool isOnline = await odooService.checkNetworkConnectivity();
      Profile? profile;

      if (isOnline) {
        final userDetails = await odooService.getUserProfile(userId ?? 0);
        String? profileImage;
        final imgValue = userDetails?['image_1920'];
        if (imgValue is String && imgValue != 'false') {
          profileImage = imgValue;
        } else {
          profileImage = null;
        }

        String mobile = '';
        if (userDetails != null) {
          final mv = userDetails['mobile'];
          if (mv is String && mv.isNotEmpty && mv != 'false') {
            mobile = mv;
          }
        }
        profile = Profile(
          name: userDetails?['name'] is String ? userDetails!['name'] : '',
          email: userDetails?['email'] is String ? userDetails!['email'] : '',
          phone: userDetails?['phone'] is String ? userDetails!['phone'] : '',
          mobile: mobile,
          company: userDetails?['company_id'] is List &&
                  (userDetails!['company_id'] as List).isNotEmpty
              ? userDetails['company_id'][1].toString()
              : '',
          website: userDetails?['website'] is String ? userDetails!['website'] : '',
          profileImage: profileImage,
          mapToken: (await storageService.getSessionData())['mapToken']
                  ?.toString() ?? '',
          street: userDetails?['street'] is String ? userDetails!['street'] : '',
          street2: userDetails?['street2'] is String ? userDetails!['street2'] : '',
          city: userDetails?['city'] is String ? userDetails!['city'] : '',
          zip: userDetails?['zip'] is String ? userDetails!['zip'] : '',
          countryId: (userDetails?['country_id'] is List && (userDetails!['country_id'] as List).isNotEmpty)
              ? userDetails['country_id'][0] as int
              : null,
          countryName: (userDetails?['country_id'] is List && (userDetails!['country_id'] as List).length > 1)
              ? userDetails['country_id'][1].toString()
              : '',
          stateId: (userDetails?['state_id'] is List && (userDetails!['state_id'] as List).isNotEmpty)
              ? userDetails['state_id'][0] as int
              : null,
          stateName: (userDetails?['state_id'] is List && (userDetails!['state_id'] as List).length > 1)
              ? userDetails['state_id'][1].toString()
              : '',
          function: userDetails?['function'] is String ? userDetails!['function'] : '',
        );

        // Persist fresh data locally
        await HiveProfileService().saveProfile(profile);
      } else {
        profile = await HiveProfileService().getProfile();
      }

      if (profile != null) {
        emit(ProfileLoaded(profile));
      } else {
        emit(const ProfileError("Failed to load profile: Profile is null"));
      }
    } catch (e) {
      emit(ProfileError("Failed to load profile: $e"));
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

      // Separate mapToken (company-level field, not on res.users)
      final odooData = Map<String, dynamic>.from(event.updateData);
      final mapToken = odooData.remove('mapToken');

      final success = await odooService.updateUserProfile(
          userId ?? 0, odooData);
      if (success) {
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
        profileImage: event.base64Image,
      );
      emit(current.copyWith(profile: updatedProfile, isEdited: true));
    }
  }

  /// Fetches the list of countries from Odoo.
  Future<void> _onLoadCountries(
      LoadCountries event, Emitter<ProfileState> emit) async {
    if (state is ProfileLoaded) {
      final current = state as ProfileLoaded;
      emit(current.copyWith(isLoadingCountries: true));
      try {
        final countries = await odooService.getCountries();
        emit(current.copyWith(
          countries: countries,
          isLoadingCountries: false,
        ));
      } catch (_) {
        emit(current.copyWith(isLoadingCountries: false));
      }
    }
  }

  /// Fetches the list of states for a specific country from Odoo.
  Future<void> _onLoadStates(
      LoadStates event, Emitter<ProfileState> emit) async {
    if (state is ProfileLoaded) {
      final current = state as ProfileLoaded;
      emit(current.copyWith(isLoadingStates: true, states: []));
      try {
        final states = await odooService.getStates(event.countryId);
        emit(current.copyWith(
          states: states,
          isLoadingStates: false,
        ));
      } catch (_) {
        emit(current.copyWith(isLoadingStates: false));
      }
    }
  }

}
