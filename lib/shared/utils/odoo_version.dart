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

/// The field holding an attachment's content.
///
/// Odoo 20 removed `ir.attachment.datas` in favour of `raw`
/// (`odoo/addons/base/models/ir_attachment.py`: 19 declared both, 20 declares
/// only `raw` and `db_datas`).
///
/// Reading the old name fails loudly, but writing it fails *silently*: 20's
/// `_check_contents` warns and pops `datas` out of the values before create,
/// so the server returns a perfectly good id for an attachment with no
/// content. An upload that looks successful and stores nothing is the worst
/// shape this bug could take, which is why the write path matters more than
/// the read.
///
/// `raw` is base64 over JSON-RPC in both, so callers need no other change.
String attachmentDataField(int major) => major >= 20 ? 'raw' : 'datas';

/// The `ir.config_parameter` reader.
///
/// Odoo 20 dropped `get_param` for typed getters — `get_str`, `get_int`,
/// `get_bool`, `get_float` (`odoo/addons/base/models/ir_config_parameter.py`;
/// 19 still had `get_param` at line 60). Both take the key as the first
/// positional argument, so only the name changes.
///
/// Calling the old name on 20 raises, which the expiry check swallows and
/// reads as "not expired" — so an expired database is never detected and the
/// user is left on screens that fail with raw RPC errors instead of being
/// sent back to login.
String configParamGetMethod(int major) => major >= 20 ? 'get_str' : 'get_param';

/// Normalises a binary/image field value read back from Odoo.
///
/// Odoo 19 and earlier hand back a plain base64 string. Odoo 20 wraps it:
/// `Binary.convert_to_read` returns `{'content': '<base64>', 'size': n}` and
/// `Image` inherits that unchanged (`odoo/orm/fields_binary.py`). A plain
/// `read`/`search_read` uses `load='_classic_read'`, which takes that path —
/// the flat-string form only survives under `load: 'web'`, which this app
/// never requests.
///
/// So every avatar, attachment and signature arrives as a Map on 20 and a
/// String on 19. Returns the base64 payload for both, or `null` when there
/// is none — including Odoo's `false` for an empty binary.
///
/// Not version-gated on purpose: the shape itself is unambiguous, so this
/// stays correct even against a server whose version the app guessed wrong.
String? odooBinaryContent(dynamic value) {
  if (value is String) {
    return (value.isEmpty || value == 'false') ? null : value;
  }
  if (value is Map) {
    final content = value['content'];
    if (content is String && content.isNotEmpty) return content;
  }
  return null;
}

/// Whether the picking form offers Lock and Unlock as two state-conditioned
/// buttons, rather than one unconditional toggle.
///
/// Odoo 20 put them in the form's button bar
/// (`stock/views/stock_picking_views.xml`): **Lock** when the transfer is
/// unlocked and not cancelled, **Unlock** only once it is done or cancelled.
///
/// Up to 19 the same `action_toggle_is_locked` existed only as a server
/// action bound to the form's cog menu — `name="Lock/Unlock"`, no state
/// condition at all. Applying 20's rules there would hide the action in
/// states where Odoo still offers it, for instance on a locked transfer that
/// is only Ready.
///
/// Both forms sit behind `stock.group_stock_manager`, so only the state
/// conditions differ.
bool odooLockIsStateConditioned(int major) => major >= 20;
