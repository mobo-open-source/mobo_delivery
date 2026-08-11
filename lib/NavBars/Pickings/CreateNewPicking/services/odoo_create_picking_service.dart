import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/company/session/company_session_manager.dart';
import '../../PickingFormPage/services/hive_service.dart';
import '../models/product.dart';
import '../models/partner.dart';
import '../models/user.dart';
import '../models/operation_type.dart';

/// Service class responsible for creating and managing stock pickings in Odoo
/// through XML-RPC calls, while handling connectivity checks, data loading,
/// and version-specific compatibility (especially Odoo 19+ changes).
class OdooCreatePickingService {
  String url;

  OdooCreatePickingService(this.url);

  /// Checks whether the device has an active internet connection and
  /// whether the Odoo server is reachable by performing a quick GET request
  /// to the /web endpoint with a short timeout.
  ///
  /// Returns `true` only if both network is available and server responds with 200 OK.
  /// Uses SharedPreferences to retrieve the latest stored server URL.
  Future<bool> checkNetworkConnectivity() async {
    final prefs = await SharedPreferences.getInstance();
    url = prefs.getString('url') ?? '';
    final connectivityResult = await Connectivity().checkConnectivity();

    if (connectivityResult.any((r) => r != ConnectivityResult.none)) {
      try {
        final response = await http
            .get(Uri.parse('$url/web'))
            .timeout(const Duration(seconds: 5));

        return response.statusCode == 200;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  /// Loads all available products from Odoo using `product.product` model's
  /// `search_read` method with default domain (all records).
  ///
  /// Returns a list of `ProductModel` objects or empty list if any error occurs.
  /// Does not apply any domain filter — fetches all products visible to the user.
  Future<List<ProductModel>> loadProducts() async {
    try {
      final productItems = await CompanySessionManager.callKwWithCompany({
        'model': 'product.product',
        'method': 'search_read',
        'args': [[]],
        'kwargs': {
          'fields': ['id', 'display_name', 'name', 'uom_id', 'image_128'],
        },
      });
      final items = (productItems as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (items.isNotEmpty) {
        await HiveService().saveProducts(items);
        return items.map((item) => ProductModel.fromJson(item)).toList();
      }
      final cached = await HiveService().getProducts();
      return cached
          .map((p) => ProductModel(id: p.id, name: p.name, uom_id: p.uom_id))
          .toList();
    } catch (e) {
      debugPrint('loadProducts error: $e');
      final cached = await HiveService().getProducts();
      return cached
          .map((p) => ProductModel(id: p.id, name: p.name, uom_id: p.uom_id))
          .toList();
    }
  }

  /// Fetches all partners (customers, suppliers, contacts) from the `res.partner`
  /// model using `search_read` without any domain restriction.
  ///
  /// Returns a list of `PartnerModel` instances or empty list in case of failure.
  /// Typically used to populate dropdowns or selection lists in picking creation.
  Future<List<PartnerModel>> loadPartners() async {
    try {
      final partnerItems = await CompanySessionManager.callKwWithCompany({
        'model': 'res.partner',
        'method': 'search_read',
        'args': [[]],
        'kwargs': {
          'fields': ['id', 'name'],
        },
      });
      return (partnerItems as List)
          .map((item) => PartnerModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Retrieves all Odoo users from the `res.users` model via `search_read`.
  ///
  /// Returns a list of `UserModel` objects or empty list if the request fails.
  /// Usually used to assign responsible users to stock pickings/operations.
  Future<List<UserModel>> loadUsers() async {
    try {
      final userItems = await CompanySessionManager.callKwWithCompany({
        'model': 'res.users',
        'method': 'search_read',
        'args': [[]],
        'kwargs': {
          'fields': ['id', 'name'],
        },
      });
      return (userItems as List)
          .map((item) => UserModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Loads stock picking types (operation types) from `stock.picking.type` model.
  /// Only fetches essential fields: id, name, default source & destination locations.
  ///
  /// Returns list of `OperationTypeModel` or empty list on error.
  /// These types determine the default locations and behavior of created pickings.
  Future<List<OperationTypeModel>> loadOperationTypes() async {
    try {
      final operationTypeItems = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking.type',
        'method': 'search_read',
        'args': [
          [
            ['active', '=', true],
          ],
        ],
        'kwargs': {
          'fields': [
            'id',
            'display_name',
            'default_location_src_id',
            'default_location_dest_id',
            'company_id',
          ],
        },
      });

      final list = (operationTypeItems as List)
          .map(
            (item) => OperationTypeModel.fromJson(item as Map<String, dynamic>),
          )
          .toList();

      if (list.isNotEmpty) {
        await HiveService().saveOperationTypes(
          list
              .map(
                (o) => {
                  'id': o.id,
                  'name': o.name,
                  'default_location_src_id': o.defaultLocationSrcId,
                  'default_location_dest_id': o.defaultLocationDestId,
                },
              )
              .toList(),
        );
      }
      return list;
    } catch (e) {
      debugPrint('loadOperationTypes error: $e');
      return [];
    }
  }

  /// Creates a new stock picking (transfer) in Odoo using the `stock.picking` model's
  /// `create` method. Supports optional fields like origin, user_id and note.
  ///
  /// Returns the newly created picking ID (integer) on success.
  /// Throws an exception if creation fails (network error, access rights, validation...).
  Future<int> createPicking({
    required int partnerId,
    required int operationTypeId,
    required String scheduledDate,
    String? origin,
    required String moveType,
    int? userId,
    String? note,
  }) async {
    try {
      final pickingData = {
        'partner_id': partnerId,
        'picking_type_id': operationTypeId,
        'scheduled_date': scheduledDate,
        'move_type': moveType,
        if (origin != null && origin.isNotEmpty) 'origin': origin,
        if (userId != null) 'user_id': userId,
        if (note != null && note.isNotEmpty) 'note': note,
      };

      final pickingId = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'create',
        'args': [pickingData],
        'kwargs': {},
      });
      return pickingId as int;
    } catch (e) {
      rethrow;
    }
  }

  /// Reads the source (`location_id`) and destination (`location_dest_id`) locations
  /// of an existing stock picking after it has been created.
  ///
  /// Returns a map containing both location IDs (or null if not set).
  /// Throws exception if the picking cannot be read or does not exist.
  Future<Map<String, dynamic>> getPickingLocations(int pickingId) async {
    final pickingResult = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'read',
      'args': [
        [pickingId],
        ['location_id', 'location_dest_id'],
      ],
      'kwargs': {},
    });

    final pickingInfo = (pickingResult as List).isNotEmpty
        ? pickingResult[0] as Map<String, dynamic>
        : null;

    if (pickingInfo == null) {
      throw Exception("Failed to fetch picking details");
    }

    final locationId = pickingInfo['location_id'] != null
        ? pickingInfo['location_id'][0] as int
        : null;
    final locationDestId = pickingInfo['location_dest_id'] != null
        ? pickingInfo['location_dest_id'][0] as int
        : null;

    return {'location_id': locationId, 'location_dest_id': locationDestId};
  }

  /// Creates a single stock move line (`stock.move`) and attaches it to the
  /// given picking. Handles version-specific differences: Odoo 19+ removed
  /// the mandatory `name` field.
  ///
  /// Throws on RPC failure so the caller can roll back / surface to the user.
  /// Previously this swallowed every exception, leaving newly-created
  /// pickings silently empty when a single move failed (bad UoM, invalid
  /// location, access right). The caller now decides what to do.
  Future<void> createStockMove({
    required String name,
    required int productId,
    required double productUomQty,
    required int productUomId,
    required int pickingId,
    required int locationId,
    required int locationDestId,
    int? companyId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    int version = prefs.getInt('version') ?? 0;
    final payload = <String, dynamic>{
      if (version < 19) 'name': name,
      'product_id': productId,
      'product_uom_qty': productUomQty,
      'product_uom': productUomId,
      'picking_id': pickingId,
      'location_id': locationId,
      'location_dest_id': locationDestId,
      if (companyId != null) 'company_id': companyId,
    };

    await CompanySessionManager.callKwWithCompany({
      'model': 'stock.move',
      'method': 'create',
      'args': [payload],
      'kwargs': {},
    }, companyId: companyId);
  }

  /// Reads the picking's `company_id` so freshly-created moves can be
  /// stamped with the same company the picking belongs to. Without this,
  /// in multi-company setups, moves default to the user's primary
  /// company — either tripping Odoo's "Incompatible companies on
  /// records" check or saving the move under a company whose record
  /// rules hide it from the picking's view.
  Future<int?> getPickingCompanyId(int pickingId) async {
    try {
      final result = await CompanySessionManager.callKwWithCompany({
        'model': 'stock.picking',
        'method': 'read',
        'args': [
          [pickingId],
          ['company_id'],
        ],
        'kwargs': {},
      });
      if (result is List && result.isNotEmpty) {
        final raw = (result.first as Map<String, dynamic>)['company_id'];
        if (raw is List && raw.isNotEmpty && raw.first is int) {
          return raw.first as int;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> confirmPicking(int pickingId, {int? companyId}) async {
    await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'action_confirm',
      'args': [
        [pickingId],
      ],
      'kwargs': {},
    }, companyId: companyId);
  }

  /// Fetches detailed information about a newly created picking using `search_read`
  /// with a precise domain (`id = pickingId`) and a selected set of fields.
  ///
  /// Returns a map with picking data or `null` if no record was found or request failed.
  /// Field list is adjusted based on Odoo version (group_id removed in v19+).
  Future<Map<String, dynamic>?> getNewPickingDetails(int pickingId) async {
    final prefs = await SharedPreferences.getInstance();
    int version = prefs.getInt('version') ?? 0;
    List<String> pickingFields = [
      'id',
      'name',
      'partner_id',
      'picking_type_id',
      'scheduled_date',
      'origin',
      'move_type',
      'user_id',
      'note',
      'state',
      'return_count',
      'date_deadline',
      'date_done',
      'products_availability',
      'picking_type_code',
      'company_id',
    ];

    if (version < 19) {
      pickingFields.addAll(['group_id']);
    }

    final newPicking = await CompanySessionManager.callKwWithCompany({
      'model': 'stock.picking',
      'method': 'search_read',
      'args': [
        [
          ['id', '=', pickingId],
        ],
      ],
      'kwargs': {'fields': pickingFields},
    });

    if (newPicking != null && (newPicking as List).isNotEmpty) {
      return newPicking[0] as Map<String, dynamic>;
    }
    return null;
  }
}
