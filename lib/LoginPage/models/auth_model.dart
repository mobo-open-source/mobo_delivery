/// Possible outcomes when attempting local/device authentication (biometrics, PIN, etc.).
///
/// Used primarily by authentication services (e.g. local_auth package) to communicate
/// the result of a biometric/PIN check to the rest of the app.
enum AuthenticationResult {
  success,
  failure,
  error,
  unavailable,
}

/// Data model representing the user's current authentication state.
///
/// This model is used to:
/// • Determine if the user has an active logged-in session
/// • Check if local/device authentication (biometrics/PIN) is required
/// • Optionally carry the result of the most recent local auth attempt
///
/// Typically populated from secure storage or auth service at app startup,
/// and passed to navigation/auth flow controllers.
class AuthModel {
  final bool isLoggedIn;
  final bool useLocalAuth;
  final AuthenticationResult? authResult;

  AuthModel({
    this.isLoggedIn = false,
    this.useLocalAuth = false,
    this.authResult,
  });

  /// Creates a new instance of [AuthModel] with some properties updated.
  ///
  /// This follows the immutable data class pattern commonly used in Flutter.
  /// Any omitted parameters keep their current values.
  ///
  /// Example:
  /// ```dart
  /// final updated = authModel.copyWith(
  ///   authResult: AuthenticationResult.success,
  /// );
  /// ```
  AuthModel copyWith({
    bool? isLoggedIn,
    bool? useLocalAuth,
    AuthenticationResult? authResult,
  }) {
    return AuthModel(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      useLocalAuth: useLocalAuth ?? this.useLocalAuth,
      authResult: authResult ?? this.authResult,
    );
  }
}