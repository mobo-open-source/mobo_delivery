/// Base class for all events handled by [SettingsBloc].
///
/// All settings-related events extend this class to ensure proper equality
/// comparison (via [Equatable] if you decide to add it later) and consistent
/// dispatching behavior in the settings screen.
abstract class SettingsEvent {}

/// Triggers initial loading of all settings and dynamic data.
///
/// Dispatched automatically when:
///   • SettingsBloc is created
///   • Settings page is first opened
///
/// Loads persisted preferences + fetches languages/currencies/timezones from Odoo.
class LoadSettingsEvent extends SettingsEvent {}

/// Toggles dark/light theme mode.
///
/// Updates local storage and notifies UI/providers to apply the change.
class ToggleDarkModeEvent extends SettingsEvent {
  final bool isDarkMode;
  ToggleDarkModeEvent(this.isDarkMode);
}

/// Toggles reduced motion / accessibility mode.
///
/// Disables or enables animations/transitions throughout the app.
class ToggleReduceMotionEvent extends SettingsEvent {
  /// `true` = reduce motion (minimal animations), `false` = full animations
  final bool reduceMotion;
  ToggleReduceMotionEvent(this.reduceMotion);
}

/// Updates the user's preferred display language.
///
/// Saves locally and (if online) updates the user record in Odoo.
class UpdateLanguageEvent extends SettingsEvent {
  final String language;
  final String languageCode;
  UpdateLanguageEvent(this.language, this.languageCode);
}

/// Changes the default currency for display/formatting in the app.
///
/// Currently stored only locally (no Odoo sync in current implementation).
class UpdateCurrencyEvent extends SettingsEvent {
  final String currency;
  UpdateCurrencyEvent(this.currency);
}

/// Updates the user's timezone preference.
///
/// Saves locally and syncs to Odoo user record (affects date/time display).
class UpdateTimezoneEvent extends SettingsEvent {
  final String timezone;
  final String timezoneCode;
  final String languageCode;
  UpdateTimezoneEvent(this.timezone, this.timezoneCode, this.languageCode);
}

/// Requests to clear the app's temporary cache directory.
///
/// Used to free up storage space (images, temp files, etc.).
class ClearCacheEvent extends SettingsEvent {}

/// Refreshes the lists of available languages, currencies, and timezones from Odoo.
///
/// Typically triggered by a refresh button/icon in the UI.
class RefreshLanguageAndRegionEvent extends SettingsEvent {}