import 'package:flutter_test/flutter_test.dart';
import 'package:odoo_delivery_app/NavBars/MapBox/services/odoo_map_service.dart';

/// Select Pickings on the Route tab lists what Odoo's Deliveries list shows
/// under its Draft + Waiting + Ready filters.
void main() {
  test('only outgoing pickings', () {
    final type = OdooMapService.openDeliveriesDomain.firstWhere(
      (c) => c.first == 'picking_type_code',
    );
    expect(type, ['picking_type_code', '=', 'outgoing']);
  });

  test('open states only — drafts in, done and cancelled out', () {
    final state = OdooMapService.openDeliveriesDomain.firstWhere(
      (c) => c.first == 'state',
    );
    expect(state[1], 'in');
    expect(state[2], ['draft', 'waiting', 'confirmed', 'assigned']);
    expect(state[2], isNot(contains('done')));
    expect(state[2], isNot(contains('cancel')));
  });
}
