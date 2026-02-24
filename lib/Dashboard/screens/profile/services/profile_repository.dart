
import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/profile.dart';
import '../../../services/encryption_service.dart';
import '../../../services/hive_profile_service.dart';
import '../../../services/odoo_dashboard_service.dart';
import '../../../services/storage_service.dart';

/// Single source of truth for profile data operations.
///
/// This repository:
///   • Abstracts data sources (Odoo API + Hive local cache)
///   • Handles online/offline scenarios
///   • Manages version-specific field mapping (mobile vs mobile_phone)
///   • Encrypts and stores map tokens at company level
///   • Provides a clean interface for ProfileBloc / use cases
class ProfileRepository {
  final OdooDashboardService odooService;
  final HiveProfileService hiveService;
  final EncryptionService encryptionService;
  final DashboardStorageService storageService;

  ProfileRepository({
    required this.odooService,
    required this.hiveService,
    required this.encryptionService,
    required this.storageService,
  });

  /// Fetches the current user's profile.
  ///
  /// Behavior:
  ///   - If online → fetch from Odoo → save to Hive → return fresh data
  ///   - If offline or fetch fails → return cached profile from Hive
  ///   - Returns `null` only if both remote and local sources fail completely
  ///
  /// [userId] is required to fetch from Odoo.
  Future<Profile?> fetchProfile(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    int version = prefs.getInt('version') ?? 0;
    try {
      bool isOnline = await odooService.checkNetworkConnectivity();
      if (isOnline) {
        final userDetails = await odooService.getUserProfile(userId);
        if (userDetails != null) {
          String mobile;
          if (version < 18) {
            mobile = (userDetails['mobile'] is String) ? userDetails['mobile'] : '';
          } else {
            mobile = (userDetails['mobile_phone'] is String) ? userDetails['mobile_phone'] : '';
          }
          final profile = Profile(
            name: userDetails['name'] ?? '',
            email: userDetails['email'] ?? '',
            phone: userDetails['phone'] ?? '',
            company: (userDetails['company_id'] != null && (userDetails['company_id'] as List).isNotEmpty)
                ? userDetails['company_id'][1]
                : '',
            mobile: mobile,
            website: userDetails['website'] ?? '',
            jobTitle: userDetails['position'] ?? '',
            profileImage: userDetails['image_1920'] ?? '',
              mapToken: (await storageService.getSessionData())['mapToken']?.toString() ?? ''
          );
          await hiveService.saveProfile(profile);
          return profile;
        }
      } else {
        return await hiveService.getProfile();
      }
    } catch (e) {
      return await hiveService.getProfile();
    }
    return null;
  }

  /// Updates the user's profile on Odoo and locally.
  ///
  /// Returns `true` if the update succeeded on the server (and local cache was updated).
  /// Returns `false` if the server update failed or threw an exception.
  ///
  /// Side effects:
  ///   - Saves updated profile to Hive
  ///   - If mapToken is provided → encrypts and saves to company field + local storage
  Future<bool> updateProfile(Profile profile, int userId, int companyId) async {
    final prefs = await SharedPreferences.getInstance();
    int version = prefs.getInt('version') ?? 0;
    try {
      final updateData = {
        'name': profile.name,
        'email': profile.email,
        'phone': profile.phone,
        'image_1920': profile.profileImage ?? '',
        if (version < 18)
          'mobile': profile.mobile ?? '',
        if (version >= 18)
          'mobile_phone': profile.mobile ?? '',
      };
      bool success = await odooService.updateUserProfile(userId, updateData);
      if (success && profile.mapToken != null && profile.mapToken!.isNotEmpty) {
        final encryptedToken = encryptionService.encryptText(profile.mapToken!);
        await odooService.createMapKeyField(companyId, encryptedToken);
        await storageService.saveMapToken(profile.mapToken!);
      }
      await hiveService.saveProfile(profile);
      return success;
    } catch (_) {
      return false;
    }
  }
}
