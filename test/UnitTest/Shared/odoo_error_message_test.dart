import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_delivery_app/shared/utils/odoo_error_message.dart';

void main() {
  test('keeps the part of an access error that names the model', () {
    final e =
        "OdooException: {code: 0, message: Odoo Server Error, data: {name: "
        "odoo.exceptions.AccessError, message: Uh-oh! Looks like you have "
        "stumbled upon some top-secret records.\n\nSorry, Demo User doesn't have "
        "'read' access to:\n- Module (ir.module.module)\n\nContact your "
        "administrator., arguments: [x], context: {}, debug: Traceback (most "
        "recent call last):\n  File \"/usr/lib/odoo/http.py\", line 1\n}}";
    final out = briefOdooMessage(e);
    expect(out, contains('ir.module.module'));
    expect(out, contains("doesn't have"));
    expect(out, isNot(contains('Traceback')));
  });

  test('extracts the real reason, not the generic envelope', () {
    final e =
        'OdooException: {code: 0, message: Odoo Server Error, data: {name: '
        'builtins.ValueError, message: Cannot convert stock.picking.return_count '
        'to SQL because it is not stored, arguments: [y], context: {}, debug: '
        'Traceback (most recent call last):\n}}';
    expect(briefOdooMessage(e), contains('not stored'));
    expect(briefOdooMessage(e), isNot(contains('Odoo Server Error')));
  });

  test('leaves non-Odoo failures alone', () {
    expect(briefOdooMessage(Exception('plain failure')),
        contains('plain failure'));
  });
}
