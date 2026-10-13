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

/// The UoM field on `stock.move`.
///
/// Odoo 20 renamed `product_uom` to `uom_id` (`addons/stock/models/
/// stock_move.py`). Odoo rejects a read or a write naming a field the model
/// does not define — and rejects the *whole* call, losing every other field
/// in the same request — so this must match the server exactly.
///
/// `stock.move.line` was renamed the same way (`product_uom_id` → `uom_id`),
/// but the app never asks for that field, so it needs no equivalent here.
String stockMoveUomField(int major) => major >= 20 ? 'uom_id' : 'product_uom';

/// Whether returns are made through the `stock.return.picking` wizard.
///
/// Odoo 20 deleted that wizard (`addons/stock/wizard/stock_picking_return.py`
/// is gone) and moved returns onto `stock.picking` itself: `action_return()`
/// creates a draft return picking linked back through `return_id`.
///
/// An unknown version keeps the wizard, which is what every server the app
/// has ever talked to supports.
bool odooUsesReturnWizard(int major) => major == 0 || major < 20;

/// Whether `read_group` takes positional aggregates and returns tuples.
///
/// The name survived into Odoo 20 but the method behind it did not: 19 and
/// earlier take `(domain, fields, groupby)` and return a list of dicts keyed
/// by field name, while 20 takes `(domain, groupby, aggregates)` and returns
/// a list of plain tuples.
///
/// That makes it uniquely dangerous — the old call does not fail on 20, it
/// binds `fields` to `groupby` and hands back a shape the old parser reads as
/// zero. Callers must branch, and must verify the shape they got back rather
/// than trusting the version alone.
bool odooReadGroupReturnsTuples(int major) => major >= 20;
