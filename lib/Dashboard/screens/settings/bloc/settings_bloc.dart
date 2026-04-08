import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:path_provider/path_provider.dart';
import '../../../services/odoo_dashboard_service.dart';
import '../../../services/settings_storage_service.dart';
import '../../../services/storage_service.dart';
import 'settings_event.dart';
import 'settings_state.dart';

/// Central business logic for the Settings screen.
///
/// Responsibilities:
///   • Load and persist user preferences (dark mode, reduce motion, language, currency, timezone)
///   • Fetch dynamic options from Odoo (languages, currencies, timezones)
///   • Update user language/timezone on Odoo server
///   • Clear app cache
///   • Handle offline/online states gracefully (though most settings are local)
class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsStorageService settingsStorageService;
  final DashboardStorageService dashboardStorageService;
  late OdooDashboardService odooService;
  int? userId;

  /// Creates SettingsBloc and registers all settings-related event handlers.
  /// Also initializes Odoo client using stored session data.
  /// Automatically triggers initial settings load after setup.
  SettingsBloc({
    required this.settingsStorageService,
    required this.dashboardStorageService,
  }) : super(SettingsState()) {
    on<LoadSettingsEvent>(_onLoadSettings);
    on<ToggleDarkModeEvent>(_onToggleDarkMode);
    on<ToggleReduceMotionEvent>(_onToggleReduceMotion);
    on<UpdateLanguageEvent>(_onUpdateLanguage);
    on<UpdateCurrencyEvent>(_onUpdateCurrency);
    on<UpdateTimezoneEvent>(_onUpdateTimezone);
    on<ClearCacheEvent>(_onClearCache);
    on<RefreshLanguageAndRegionEvent>(_onRefreshLanguageAndRegion);

    // Initialize Odoo client right away
    _initializeOdooClient();
  }

  /// Sets up Odoo RPC client using stored session data
  Future<void> _initializeOdooClient() async {
    final sessionData = await dashboardStorageService.getSessionData();
    final url = sessionData['url'];
    userId = sessionData['userId'];
    final session = OdooSession(
      id: sessionData['sessionId'],
      userId: sessionData['userId'],
      partnerId: sessionData['partnerId'],
      userLogin: sessionData['userLogin'],
      userName: sessionData['userName'],
      userLang: sessionData['userLang'],
      userTz: '',
      isSystem: sessionData['isSystem'],
      dbName: sessionData['db'],
      serverVersion: sessionData['serverVersion'],
      companyId: sessionData['companyId'],
      allowedCompanies: dashboardStorageService.parseCompanies(
        sessionData['allowedCompanies'],
      ),
    );
    odooService = OdooDashboardService(url, session);

    // Auto-load settings after client is ready
    add(LoadSettingsEvent());
  }

  /// Loads all settings and dynamic Odoo data (languages, currencies, timezones)
  Future<void> _onLoadSettings(
      LoadSettingsEvent event, Emitter<SettingsState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      await settingsStorageService.initialize();

      // Load persisted local preferences
      final language = settingsStorageService.getString('language') ?? state.language;
      final currency = settingsStorageService.getString('currency') ?? state.currency;
      final timezone = settingsStorageService.getString('timezone') ?? state.timezone;
      final darkMode = settingsStorageService.getBool('darkMode') ?? state.isDarkMode;
      final reduceMotion = settingsStorageService.getBool('reduceMotion') ?? state.reduceMotion;

      // Fetch dynamic options from Odoo
      final languagesRaw = await odooService.fetchLanguage() ?? [];
      final currenciesRaw = await odooService.fetchCurrency() ?? [];
      final timezones = await odooService.fetchTimezones();

      final languages = languagesRaw.cast<Map<String, dynamic>>();
      final currencies = currenciesRaw.cast<Map<String, dynamic>>();
      emit(state.copyWith(
        isLoading: false,
        language: language,
        currency: currency,
        timezone: timezone,
        isDarkMode: darkMode,
        reduceMotion: reduceMotion,
        languages: languages,
        currencies: currencies,
        timezones: timezones,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: 'Failed to load settings: $e'));
    }
  }

  /// Toggles dark mode preference.
  /// Saves the preference locally and updates UI state.
  /// Does not require server communication.
  Future<void> _onToggleDarkMode(
      ToggleDarkModeEvent event, Emitter<SettingsState> emit) async {
    await settingsStorageService.setBool('darkMode', event.isDarkMode);
    emit(state.copyWith(isDarkMode: event.isDarkMode));
  }

  /// Toggles reduce motion accessibility setting.
  /// Stores preference locally and updates state.
  /// Helps control animation usage across the app.
  Future<void> _onToggleReduceMotion(
      ToggleReduceMotionEvent event, Emitter<SettingsState> emit) async {
    await settingsStorageService.setBool('reduceMotion', event.reduceMotion);
    emit(state.copyWith(reduceMotion: event.reduceMotion));
  }

  /// Updates preferred language (local storage + Odoo user record)
  Future<void> _onUpdateLanguage(
      UpdateLanguageEvent event, Emitter<SettingsState> emit) async {
    try {
      await settingsStorageService.setString('language', event.language);
      await odooService.updateLanguage(userId!, {
        'lang': event.languageCode,
        'tz': state.timezone,
      });
      emit(state.copyWith(language: event.language));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to update language: $e'));
    }
  }

  /// Updates preferred currency (currently only local storage)
  Future<void> _onUpdateCurrency(
      UpdateCurrencyEvent event, Emitter<SettingsState> emit) async {
    try {
      await settingsStorageService.setString('currency', event.currency);
      emit(state.copyWith(currency: event.currency));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to update currency: $e'));
    }
  }

  /// Updates timezone (local + Odoo user record)
  Future<void> _onUpdateTimezone(
      UpdateTimezoneEvent event, Emitter<SettingsState> emit) async {
    try {
      await settingsStorageService.setString('timezone', event.timezone);
      await odooService.updateLanguage(userId!, {
        'lang': event.languageCode ?? state.language,
        'tz': event.timezoneCode,
      });
      emit(state.copyWith(timezone: event.timezone));
    } catch (e) {
      emit(state.copyWith(error: 'Failed to update timezone: $e'));
    }
  }

  /// Clears temporary cache directory
  Future<void> _onClearCache(
      ClearCacheEvent event, Emitter<SettingsState> emit) async {
    try {
      final cacheDir = await getTemporaryDirectory();
      await _deleteDir(cacheDir);
      emit(state.copyWith());
    } catch (e) {
      emit(state.copyWith(error: 'Failed to clear cache: $e'));
    }
  }

  /// Refreshes language, currency, and timezone lists from Odoo
  Future<void> _onRefreshLanguageAndRegion(
      RefreshLanguageAndRegionEvent event, Emitter<SettingsState> emit) async {
    emit(state.copyWith(isLanguageLoading: true));
    try {
      final languagesRaw = await odooService.fetchLanguage() ?? [];
      final currenciesRaw = await odooService.fetchCurrency() ?? [];
      final timezones = await odooService.fetchTimezones();

      final languages = languagesRaw.cast<Map<String, dynamic>>();
      final currencies = currenciesRaw.cast<Map<String, dynamic>>();
      emit(state.copyWith(
        isLanguageLoading: false,
        languages: languages,
        currencies: currencies,
        timezones: timezones,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLanguageLoading: false,
        error: 'Failed to refresh language and region: $e',
      ));
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Recursively deletes files and folders inside a directory.
  /// Used for clearing temporary cache storage.
  /// Silently ignores deletion errors.
  Future<void> _deleteDir(FileSystemEntity file) async {
    if (file is Directory) {
      final List<FileSystemEntity> children = file.listSync();
      for (final child in children) {
        await _deleteDir(child);
      }
    }
    try {
      await file.delete();
    } catch (_) {}
  }
}