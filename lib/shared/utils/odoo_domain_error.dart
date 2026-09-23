/// Recognises the errors Odoo raises when it refuses a *search domain*
/// itself, as opposed to failing to run a perfectly valid one.
///
/// Which fields can appear in a domain is not constant across deployments.
/// A field may be computed and non-stored (no column to query), may have
/// been renamed or dropped between Odoo majors, or may belong to a module
/// the customer's server does not have. Odoo answers all of these by
/// rejecting the whole request, so one unsupported filter takes down the
/// entire list rather than just that filter.
///
/// The app cannot know every server's schema ahead of time, so the reliable
/// behaviour is to notice this specific class of failure, retry without the
/// filters, and tell the user which part was unsupported — instead of
/// showing a generic failure for a list that would otherwise load fine.
bool isUnsupportedDomainError(Object e) {
  final s = e.toString().toLowerCase();
  return s.contains('because it is not stored') ||
      s.contains('cannot be searched') ||
      s.contains('unsearchable') ||
      s.contains('invalid field') ||
      s.contains('invalid item in domain') ||
      s.contains('invalid domain') ||
      s.contains('does not exist on') ||
      s.contains('unknown field');
}
