/// Major version of the connected Odoo server, or 0 when it cannot be read.
///
/// Handles the shapes Odoo reports: `17.0`, `17.0+e`, `17.0-20240101` and the
/// SaaS form `saas~16.3`, which must yield 16.
int odooMajorVersion(String? serverVersion) {
  final match = RegExp(r'\d+').firstMatch(serverVersion ?? '');
  if (match == null) return 0;
  return int.tryParse(match.group(0)!) ?? 0;
}

/// Whether `res.partner` still defines `mobile`, which Odoo 19 removed by
/// merging it into `phone`.
///
/// Asking a 19 server for it fails the entire read, taking every other field
/// in the same request with it, so both profile reads must agree on this —
/// they each had their own copy, and one drifting would break the other.
/// Unknown versions are treated as having it; both callers wrap the read.
bool odooHasPartnerMobile(int major) => major == 0 || major < 19;
