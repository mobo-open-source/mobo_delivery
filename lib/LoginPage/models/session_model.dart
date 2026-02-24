/// Represents the authenticated user's session data received from the server
/// after successful login/authentication.
///
/// This model typically contains:
/// - User identification details
/// - Session identifier
/// - Company/multi-company context
/// - Server metadata
/// - Permissions/system flags
///
/// Usually created by parsing the response from a login or session-check endpoint
/// (e.g., Odoo-style `/web/session/get_session_info` or similar APIs).
class SessionModel {
  final String? userName;
  final String? userLogin;
  final int? userId;
  final String sessionId;
  final String? serverVersion;
  final String? userLang;
  final int? partnerId;
  final String? userTimezone;
  final int? companyId;
  final String? companyName;
  final bool isSystem;
  final int? version;
  final List<int> allowedCompanyIds;

  SessionModel({
    required this.sessionId,
    this.userName,
    this.userLogin,
    this.userId,
    this.serverVersion,
    this.userLang,
    this.partnerId,
    this.userTimezone,
    this.companyId,
    this.companyName,
    this.isSystem = false,
    this.version,
    this.allowedCompanyIds = const [],
  });
}