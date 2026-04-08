/// Immutable state class for the [SettingsBloc].
///
/// Holds all UI-relevant settings data and status flags for the Settings screen:
///   • Loading states (general + language/region specific)
///   • Appearance preferences (dark mode, reduce motion)
///   • Localization preferences (language, currency, timezone)
///   • Dynamic lists fetched from Odoo (languages, currencies, timezones)
///   • Transient error messages
///
/// Uses immutable pattern with [copyWith] for safe state updates in Bloc.
class SettingsState {
  final bool isLoading;
  final bool isLanguageLoading;
  final bool isDarkMode;
  final bool reduceMotion;
  final String language;
  final String currency;
  final String timezone;
  final List<Map<String, dynamic>> languages;
  final List<Map<String, dynamic>> currencies;
  final List<Map<String, dynamic>> timezones;
  final String? error;

  SettingsState({
    this.isLoading = false,
    this.isLanguageLoading = false,
    this.isDarkMode = false,
    this.reduceMotion = false,
    this.language = 'English (US)',
    this.currency = 'United States dollar',
    this.timezone = 'Europe/Brussels',
    this.languages = const [],
    this.currencies = const [],
    this.timezones = const [],
    this.error,
  });

  /// Creates a new instance with some fields replaced while preserving others.
  ///
  /// Typical usage in bloc:
  /// ```dart
  /// emit(state.copyWith(
  ///   isLoading: false,
  ///   languages: newLanguagesList,
  ///   error: null,
  /// ));
  /// ```
  SettingsState copyWith({
    bool? isLoading,
    bool? isLanguageLoading,
    bool? isDarkMode,
    bool? reduceMotion,
    String? language,
    String? currency,
    String? timezone,
    List<Map<String, dynamic>>? languages,
    List<Map<String, dynamic>>? currencies,
    List<Map<String, dynamic>>? timezones,
    String? error,
  }) {
    return SettingsState(
      isLoading: isLoading ?? this.isLoading,
      isLanguageLoading: isLanguageLoading ?? this.isLanguageLoading,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      language: language ?? this.language,
      currency: currency ?? this.currency,
      timezone: timezone ?? this.timezone,
      languages: languages ?? this.languages,
      currencies: currencies ?? this.currencies,
      timezones: timezones ?? this.timezones,
      error: error,
    );
  }
}