import 'package:shared_preferences/shared_preferences.dart';

import '../../core/company/session/company_session_manager.dart';

/// Reads the values and field domains Odoo's own form view would use, so a
/// mobo detail page opens showing what the Odoo form shows.
///
/// The app used to assemble every create payload by hand, which meant a blank
/// Responsible where Odoo prefills the current user, and a dropdown offering
/// every user on the system where Odoo offers only warehouse staff.
///
/// Asking the server is not the same as copying its rules into Dart.
/// `default_get` resolves a default in this order — context, then an admin's
/// **User-defined Defaults** (`ir.default`), then the field's own `default=`,
/// then company fallbacks. Hardcoding "the logged-in user" reproduces only the
/// third of those and silently overrides the first two, so a customer who
/// configured a default in Odoo would find the app ignoring it.
///
/// Every method here fails open: any RPC problem returns nothing and leaves
/// the caller on its previous behaviour. A form that cannot reach the server
/// is still a usable form.
class OdooDefaultsService {
  OdooDefaultsService._();

  static final OdooDefaultsService instance = OdooDefaultsService._();

  static const Duration _timeout = Duration(seconds: 20);

  /// Field domains already read, keyed by account as well as model and field:
  /// a domain is a property of the server, and two accounts are two servers.
  final Map<String, List<dynamic>> _domainCache = {};

  /// Forgets everything learned about the previous account's server.
  void reset() => _domainCache.clear();

  Future<String> _accountKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('url') ?? '';
      final db =
          prefs.getString('selectedDatabase') ??
          prefs.getString('database') ??
          '';
      final uid = prefs.getInt('userId') ?? 0;
      return '$url|$db|$uid';
    } catch (_) {
      return '';
    }
  }

  /// What Odoo would prefill on a new [model] record, for the subset of
  /// [fields] that actually have a default.
  ///
  /// Safe to call with fields that do not exist on this Odoo version:
  /// `default_get` looks each one up with `self._fields.get(name)` and skips
  /// what it does not recognise, so one field list serves every release.
  ///
  /// Returns **null** when the server could not be asked, and an empty map
  /// when it was asked and defaulted nothing. The caller needs to tell those
  /// apart: the first is a reason to fall back to a local default, while the
  /// second is the server's answer and must be respected — an administrator
  /// who cleared a default should not have the app reinstate it.
  Future<Map<String, dynamic>?> defaultsFor(
    String model,
    List<String> fields, {
    Map<String, dynamic> context = const {},
  }) async {
    if (fields.isEmpty) return const {};
    try {
      final result = await CompanySessionManager.callKwWithCompany({
        'model': model,
        'method': 'default_get',
        'args': [fields],
        'kwargs': {'context': context},
      }).timeout(_timeout);
      if (result is Map) {
        return result.map((key, value) => MapEntry('$key', value));
      }
    } catch (_) {
      // Fall through to null — the caller decides what to do without an answer.
    }
    return null;
  }

  /// The domain Odoo applies to a relational [field], so a dropdown offers the
  /// same records the Odoo form offers.
  ///
  /// Read from the server rather than written out here, because the domain
  /// itself moves between releases: `stock.picking.user_id` filters on
  /// `groups_id` in Odoo 18 and `all_group_ids` in 19 and 20. Odoo evaluates a
  /// callable domain before returning it, so what arrives is a plain list with
  /// group ids already resolved — correct on every version, and correct when a
  /// customer has customised it.
  ///
  /// Returns null when there is no usable domain, which callers must treat as
  /// "no filter" rather than "match nothing".
  Future<List<dynamic>?> relationDomain(String model, String field) async {
    final key = '${await _accountKey()}|$model|$field';
    final cached = _domainCache[key];
    if (cached != null) return cached;

    try {
      final result = await CompanySessionManager.callKwWithCompany({
        'model': model,
        'method': 'fields_get',
        'args': [
          [field],
          ['domain'],
        ],
        'kwargs': const {},
      }).timeout(_timeout);

      if (result is Map) {
        final described = result[field];
        if (described is Map) {
          final domain = usableDomain(described['domain']);
          // Only a success is cached. Caching a failure would strand the
          // dropdown on the unfiltered list for the rest of the session.
          if (domain != null) _domainCache[key] = domain;
          return domain;
        }
      }
    } catch (_) {
      // Fail open — the caller keeps whatever it had.
    }
    return null;
  }
}

/// A field domain the app can send to `search_read`, or null.
///
/// Odoo describes a domain as either a list or a **string**. The string form
/// is an expression evaluated against the other fields of an open form
/// (`[('company_id', '=', company_id)]`), so it means nothing outside that
/// form and would be rejected or, worse, silently mismatched if forwarded.
/// Only the list form is usable here.
List<dynamic>? usableDomain(dynamic raw) {
  if (raw is List) return raw;
  return null;
}

/// The defaults the Create Picking form can act on, read out of a
/// `default_get` response.
class PickingCreateDefaults {
  const PickingCreateDefaults({
    this.responsibleUserId,
    this.scheduledDateUtc,
    this.shippingPolicy,
  });

  /// `user_id` — Odoo's Responsible, which defaults to the logged-in user.
  final int? responsibleUserId;

  /// `scheduled_date`, as Odoo sends it: naive UTC.
  final DateTime? scheduledDateUtc;

  /// `move_type` — the Shipping Policy, when the server offered one.
  final String? shippingPolicy;
}

/// Reads a `stock.picking.default_get` response.
///
/// Tolerant by design. A many2one default normally arrives as a bare id, but
/// `false` means "no default" and a `[id, name]` pair is accepted too, so an
/// unexpected shape degrades to "no default" instead of throwing inside a
/// form's first build.
PickingCreateDefaults parsePickingCreateDefaults(Map<String, dynamic> raw) {
  return PickingCreateDefaults(
    responsibleUserId: _odooId(raw['user_id']),
    scheduledDateUtc: _odooDateTime(raw['scheduled_date']),
    shippingPolicy:
        raw['move_type'] is String && (raw['move_type'] as String).isNotEmpty
        ? raw['move_type'] as String
        : null,
  );
}

int? _odooId(dynamic value) {
  if (value is bool) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is List && value.isNotEmpty) return _odooId(value.first);
  return null;
}

DateTime? _odooDateTime(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  // Odoo serialises datetimes as naive UTC, "yyyy-MM-dd HH:mm:ss".
  return DateTime.tryParse('${value.replaceFirst(' ', 'T')}Z')?.toUtc();
}
