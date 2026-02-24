import 'package:hive/hive.dart';
import '../../CreateNewPicking/models/Hive/pending_creates.dart';
import '../models/operation_type.dart';
import '../models/partner.dart';
import '../models/partner_details.dart';
import '../models/pending_updates.dart';
import '../models/pending_validation.dart';
import '../models/picking_form.dart';
import '../models/product.dart';
import '../models/product_update.dart';
import '../models/stock_move.dart';
import '../models/user.dart';

/// Central service for all Hive storage operations in the app.
///
/// Manages multiple typed boxes for:
/// • Cached Odoo master data (products, partners, users, operation types)
/// • Stock pickings & return pickings
/// • Stock moves
/// • Offline pending actions (validations, cancellations, updates, new creations, product line updates)
/// • Partner details (address + image)
///
/// All save operations typically **clear + rewrite** the entire box (except pending queues).
/// This is intentional for simplicity in an offline-first mobile app with relatively small datasets.
class HiveService {
  // ───────────────────────────────────────────────
  //  Box names (used as keys for Hive.openBox)
  // ───────────────────────────────────────────────
  static const String _pickingBoxName = 'stock_picking_box';
  static const String _pickingReturnBoxName = 'stock_picking_return_box';
  static const String _productBoxName = 'product_product_box';
  static const String _partnerBoxName = 'res_partner_box';
  static const String _userBoxName = 'res_users_box';
  static const String _moveBoxName = 'stock_move_box';
  static const String _pendingValidationsBox = 'pending_validations';
  static const String _pendingCancellationsBox = 'pending_cancellations';
  static const String _pendingUpdatesBox = 'pending_updates';
  static const String _pendingCreatesBox = 'pending_creates';
  static const String _productUpdatesBox = 'product_updates';
  static const String _operationTypeBoxName = 'operation_type_box';
  static const String _partnerDetailsBoxName = 'partner_details_box';
  late Box<int> _totalCountBox;

  /// Registers all necessary Hive adapters and opens all required boxes.
  ///
  /// Must be called early (usually in main() or app init phase).
  /// Safe to call multiple times — checks if adapter is already registered.
  /// Opens boxes lazily only when needed, but pre-opens most here for simplicity.
  Future<void> initialize() async {
    // Register adapters only if not already registered
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(PickingFormAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ProductAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(PartnerAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(UserAdapter());
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(StockMoveAdapter());
    if (!Hive.isAdapterRegistered(6)) Hive.registerAdapter(PendingValidationAdapter());
    if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(PendingUpdatesAdapter());
    if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(PendingCreatesAdapter());
    if (!Hive.isAdapterRegistered(9)) Hive.registerAdapter(ProductUpdatesAdapter());
    if (!Hive.isAdapterRegistered(10)) Hive.registerAdapter(OperationTypeAdapter());
    if (!Hive.isAdapterRegistered(12)) Hive.registerAdapter(PartnerDetailsAdapter());

    // Open all main boxes
    await Hive.openBox<PickingForm>(_pickingBoxName);
    await Hive.openBox<PickingForm>(_pickingReturnBoxName);
    await Hive.openBox<Product>(_productBoxName);
    await Hive.openBox<Partner>(_partnerBoxName);
    await Hive.openBox<User>(_userBoxName);
    await Hive.openBox<StockMove>(_moveBoxName);
    await Hive.openBox<PendingValidation>(_pendingValidationsBox);
    await Hive.openBox<PendingValidation>(_pendingCancellationsBox);
    await Hive.openBox<PendingUpdates>(_pendingUpdatesBox);
    await Hive.openBox<PendingCreates>(_pendingCreatesBox);
    await Hive.openBox<ProductUpdates>(_productUpdatesBox);
    await Hive.openBox<OperationType>(_operationTypeBoxName);
    await Hive.openBox<PartnerDetails>(_partnerDetailsBoxName);

    _totalCountBox = await Hive.openBox<int>('totalCountBox');
  }

  // ───────────────────────────────────────────────
  //  Total count (used e.g. for badge on sync screen)
  // ───────────────────────────────────────────────
  Future<void> saveTotalCount(int count) async {
    await _totalCountBox.put('total', count);
  }

  int getTotalCount() => _totalCountBox.get('total') ?? 0;

  // ───────────────────────────────────────────────
  //  Pending VALIDATIONS queue
  // ───────────────────────────────────────────────

  /// Queues a picking validation to be executed when online
  Future<void> savePendingValidation(int pickingId, Map<String, dynamic> pickingData) async {
    final box = Hive.box<PendingValidation>(_pendingValidationsBox);
    final pendingValidation = PendingValidation(
      pickingId: pickingId,
      pickingData: pickingData,
    );
    await box.put('pending_$pickingId', pendingValidation);
  }

  Future<List<PendingValidation>> getPendingValidations() async {
    if (!Hive.isBoxOpen(_pendingValidationsBox)) {
      await Hive.openBox<PendingValidation>(_pendingValidationsBox);
    }
    final box = Hive.box<PendingValidation>(_pendingValidationsBox);
    return box.values.toList();
  }

  Future<void> clearPendingValidation(int pickingId) async {
    final box = Hive.box<PendingValidation>(_pendingValidationsBox);
    await box.delete('pending_$pickingId');
  }

  Future<void> clearAllPendingValidations() async {
    final box = Hive.box<PendingValidation>(_pendingValidationsBox);
    await box.clear();
  }

  // ───────────────────────────────────────────────
  //  Pending CANCELLATIONS queue
  // ───────────────────────────────────────────────

  Future<void> savePendingCancellation(int pickingId, Map<String, dynamic> pickingData) async {
    final box = Hive.box<PendingValidation>(_pendingCancellationsBox);
    final pendingCancellation = PendingValidation(pickingId: pickingId, pickingData: pickingData);
    await box.put('pending_cancellation_$pickingId', pendingCancellation);
  }

  Future<List<PendingValidation>> getPendingCancellations() async {
    if (!Hive.isBoxOpen(_pendingCancellationsBox)) {
      await Hive.openBox<PendingValidation>(_pendingCancellationsBox);
    }
    final box = Hive.box<PendingValidation>(_pendingCancellationsBox);
    return box.values.toList();
  }

  Future<void> clearPendingCancellation(int pickingId) async {
    final box = Hive.box<PendingValidation>(_pendingCancellationsBox);
    await box.delete('pending_cancellation_$pickingId');
  }

  Future<void> clearAllPendingCancellations() async {
    final box = Hive.box<PendingValidation>(_pendingCancellationsBox);
    await box.clear();
  }

  // ───────────────────────────────────────────────
  //  Pending field UPDATES (header changes)
  // ───────────────────────────────────────────────

  Future<void> savePendingUpdates(int pickingId, Map<String, dynamic> pickingData) async {
    final box = Hive.box<PendingUpdates>(_pendingUpdatesBox);
    final pendingUpdates = PendingUpdates(pickingId: pickingId,
      pickingData: pickingData,
    );
    await box.put('pending_updates_$pickingId', pendingUpdates);
  }

  Future<List<PendingUpdates>> getPendingUpdates() async {
    if (!Hive.isBoxOpen(_pendingUpdatesBox)) {
      await Hive.openBox<PendingUpdates>(_pendingUpdatesBox);
    }
    final box = Hive.box<PendingUpdates>(_pendingUpdatesBox);
    return box.values.toList();
  }

  Future<void> clearPendingUpdates(int pickingId) async {
    final box = Hive.box<PendingUpdates>(_pendingUpdatesBox);
    await box.delete('pending_updates_$pickingId');
  }

  Future<void> clearAllPendingUpdates() async {
    final box = Hive.box<PendingUpdates>(_pendingUpdatesBox);
    await box.clear();
  }

  // ───────────────────────────────────────────────
  //  Pending NEW PICKING creations
  // ───────────────────────────────────────────────

  static const String _pendingCreatesCounterBox = 'pending_creates_counter';

  Future<int> _getNextPendingCreateId() async {
    final counterBox = await Hive.openBox<int>(_pendingCreatesCounterBox);

    final counter = counterBox.get('counter', defaultValue: 0)!;
    final nextId = counter + 1;

    await counterBox.put('counter', nextId);

    return nextId;
  }

  /// Saves a new picking creation request for offline queuing
  /// Uses auto-incrementing negative/local ID
  Future<void> savePendingCreates(Map<String, dynamic> pickingData) async {
    final box = Hive.box<PendingCreates>(_pendingCreatesBox);
    final localId = await _getNextPendingCreateId();

    final pendingCreates = PendingCreates(
      pickingId: localId,
      pickingData: pickingData,
    );

    await box.put('pending_creates_$localId', pendingCreates);
  }

  Future<List<PendingCreates>> getPendingCreates() async {
    if (!Hive.isBoxOpen(_pendingCreatesBox)) {
      await Hive.openBox<PendingCreates>(_pendingCreatesBox);
    }
    final box = Hive.box<PendingCreates>(_pendingCreatesBox);
    return box.values.whereType<PendingCreates>().toList();
  }

  Future<void> clearPendingCreates(int pickingId) async {
    final box = Hive.box<PendingCreates>(_pendingCreatesBox);
    await box.delete('pending_creates_$pickingId');
  }

  Future<void> clearAllPendingCreates() async {
    final box = Hive.box<PendingCreates>(_pendingCreatesBox);
    await box.clear();
  }

  // ───────────────────────────────────────────────
  //  Pending PRODUCT LINE updates / additions
  // ───────────────────────────────────────────────

  Future<void> savePendingProductUpdates(int localId, Map<String, dynamic> productData, String PickingName) async {
    final box = await Hive.openBox<ProductUpdates>(_productUpdatesBox);

    final productUpdates = ProductUpdates(
      pickingId: localId,
      pickingName: PickingName,
      productData: productData,
    );

    await box.put('product_updates$localId', productUpdates);
  }

  Future<List<ProductUpdates>> getPendingProductUpdates() async {
    if (!Hive.isBoxOpen(_productUpdatesBox)) {
      await Hive.openBox<ProductUpdates>(_productUpdatesBox);
    }
    final box = Hive.box<ProductUpdates>(_productUpdatesBox);
    return box.values.whereType<ProductUpdates>().toList();
  }

  Future<void> clearPendingProductUpdates(int pickingId) async {
    final box = Hive.box<ProductUpdates>(_productUpdatesBox);
    await box.delete('product_updates$pickingId');
  }

  Future<void> clearAllPendingProductUpdates() async {
    final box = Hive.box<ProductUpdates>(_productUpdatesBox);
    await box.clear();
  }

  // ───────────────────────────────────────────────
  //  Cached master & picking data
  // ───────────────────────────────────────────────

  /// Replaces entire picking cache with new list
  Future<void> savePickings(List<Map<String, dynamic>> pickings) async {
    final box = Hive.box<PickingForm>(_pickingBoxName);
    await box.clear();
    for (var picking in pickings) {
      await box.put('picking_${picking['id']}', PickingForm.fromJson(picking));
    }
  }

  Future<List<PickingForm>> getPickings() async {
    final box = Hive.box<PickingForm>(_pickingBoxName);
    return box.values.toList();
  }

  Future<PickingForm?> getPickingById(int id) async {
    final box = Hive.box<PickingForm>(_pickingBoxName);
    return box.get('picking_$id');
  }

  // Similar methods for returns, products, partners, users, operation types, moves...

  Future<void> savePartnerDetails(PartnerDetails details) async {
    final box = await _getBox<PartnerDetails>(_partnerDetailsBoxName);
    await box.put('partner_${details.id}', details);
  }

  Future<PartnerDetails?> getPartnerDetails(int id) async {
    final box = await _getBox<PartnerDetails>(_partnerDetailsBoxName);
    return box.get('partner_$id');
  }

  Future<void> saveReturnPickings(List<Map<String, dynamic>> pickings) async {
    final box = Hive.box<PickingForm>(_pickingReturnBoxName);
    await box.clear();
    for (var picking in pickings) {
      await box.put('picking_${picking['id']}', PickingForm.fromJson(picking));
    }
  }

  Future<List<PickingForm>> getReturnPickings() async {
    final box = Hive.box<PickingForm>(_pickingReturnBoxName);
    return box.values.toList();
  }


  Future<void> saveProducts(List<Map<String, dynamic>> products) async {
    final box = Hive.box<Product>(_productBoxName);
    await box.clear();
    for (var product in products) {
      await box.put('product_${product['id']}', Product.fromJson(product));
    }
  }

  Future<List<Product>> getProducts() async {
    final box = Hive.box<Product>(_productBoxName);
    return box.values.toList();
  }

  Future<void> savePartners(List<Map<String, dynamic>> partners) async {
    final box = Hive.box<Partner>(_partnerBoxName);
    await box.clear();
    for (var partner in partners) {
      await box.put('partner_${partner['id']}', Partner.fromJson(partner));
    }
  }

  Future<List<Partner>> getPartners() async {
    final box = Hive.box<Partner>(_partnerBoxName);
    return box.values.toList();
  }

  Future<void> saveUsers(List<Map<String, dynamic>> users) async {
    final box = Hive.box<User>(_userBoxName);
    await box.clear();
    for (var user in users) {
      await box.put('user_${user['id']}', User.fromJson(user));
    }
  }

  Future<List<User>> getUsers() async {
    final box = Hive.box<User>(_userBoxName);
    return box.values.toList();
  }

  Future<void> saveOperationTypes(List<Map<String, dynamic>> operationTypes) async {
    final box = Hive.box<OperationType>(_operationTypeBoxName);
    await box.clear();
    for (var operationType in operationTypes) {
      await box.put('operationType_${operationType['id']}', OperationType.fromJson(operationType));
    }
  }

  Future<List<OperationType>> getOperationTypes() async {
    final box = Hive.box<OperationType>(_operationTypeBoxName);
    return box.values.toList();
  }


  Future<void> saveStockMoves(List<Map<String, dynamic>> moves) async {
    final box = Hive.box<StockMove>(_moveBoxName);
    await box.clear();
    for (var move in moves) {
      await box.put('move_${move['id']}', StockMove.fromJson(move));
    }
  }

  Future<List<StockMove>> getStockMoves({int? pickingId}) async {
    final box = Hive.box<StockMove>(_moveBoxName);
    if (pickingId != null) {
      return box.values
          .where((move) => move.pickingId != null && move.pickingId![0] == pickingId)
          .toList();
    }
    return box.values.toList();
  }

  // ───────────────────────────────────────────────
  //  Utility / cleanup
  // ───────────────────────────────────────────────

  Future<Box<T>> _getBox<T>(String boxName) async {
    if (!Hive.isBoxOpen(boxName)) {
      return await Hive.openBox<T>(boxName);
    }
    return Hive.box<T>(boxName);
  }

  /// Clears **all** cached and pending data — use with caution (e.g. logout / reset)
  Future<void> clearAllData() async {
    await Hive.box<PickingForm>(_pickingBoxName).clear();
    await Hive.box<PickingForm>(_pickingReturnBoxName).clear();
    await Hive.box<Product>(_productBoxName).clear();
    await Hive.box<Partner>(_partnerBoxName).clear();
    await Hive.box<User>(_userBoxName).clear();
    await Hive.box<StockMove>(_moveBoxName).clear();
    await Hive.box<PendingValidation>(_pendingValidationsBox).clear();
    await Hive.box<PendingValidation>(_pendingCancellationsBox).clear();
    await Hive.box<PendingUpdates>(_pendingUpdatesBox).clear();
    await Hive.box<PendingCreates>(_pendingCreatesBox).clear();
    await Hive.box<ProductUpdates>(_productUpdatesBox).clear();
    await Hive.box<OperationType>(_operationTypeBoxName).clear();
    await Hive.box<PartnerDetails>(_partnerDetailsBoxName).clear();
  }
}