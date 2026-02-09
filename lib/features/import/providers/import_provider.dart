import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:go_fundraise/core/database/database.dart';
import 'package:go_fundraise/core/models/parsed_data.dart';
import 'package:go_fundraise/features/import/parsers/backup_parser.dart';
import 'package:go_fundraise/features/import/parsers/csv_parser.dart';
import 'package:go_fundraise/features/import/parsers/jd_sweid_parser.dart';
import 'package:go_fundraise/features/import/parsers/little_caesars_parser.dart';

/// Supported import formats
enum ImportFormat {
  csv,
  jdSweid,
  littleCaesars,
  backup,
}

/// State for import process
class ImportState {
  final bool isLoading;
  final ParsedFundraiserData? parsedData;
  final BackupData? backupData;
  final String? error;
  final double progress;

  const ImportState({
    this.isLoading = false,
    this.parsedData,
    this.backupData,
    this.error,
    this.progress = 0,
  });

  ImportState copyWith({
    bool? isLoading,
    ParsedFundraiserData? parsedData,
    BackupData? backupData,
    String? error,
    double? progress,
    bool clearBackup = false,
    bool clearParsed = false,
  }) {
    return ImportState(
      isLoading: isLoading ?? this.isLoading,
      parsedData: clearParsed ? null : (parsedData ?? this.parsedData),
      backupData: clearBackup ? null : (backupData ?? this.backupData),
      error: error,
      progress: progress ?? this.progress,
    );
  }

  /// Whether we have a backup file ready to restore
  bool get hasBackup => backupData != null;
}

/// Notifier for import operations
class ImportNotifier extends StateNotifier<ImportState> {
  final AppDatabase _db;
  final _uuid = const Uuid();

  ImportNotifier(this._db) : super(const ImportState());

  /// Parse file from bytes (works on all platforms including web)
  Future<void> parseFileBytes(
    Uint8List bytes,
    String fileName,
    ImportFormat format,
  ) async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      progress: 0.1,
      clearBackup: true,
      clearParsed: true,
    );

    try {
      state = state.copyWith(progress: 0.3);

      // Handle backup format separately
      if (format == ImportFormat.backup) {
        final parser = BackupParser();
        final backupResult = await parser.parseBytes(bytes, fileName);
        state = state.copyWith(
          isLoading: false,
          backupData: backupResult,
          progress: 1.0,
        );
        return;
      }

      // Regular import formats
      ParsedFundraiserData result;
      switch (format) {
        case ImportFormat.csv:
          final parser = CsvParser();
          result = await parser.parseBytes(bytes, fileName);
          break;
        case ImportFormat.jdSweid:
          final parser = JdSweidParser();
          result = await parser.parseBytes(bytes, fileName);
          break;
        case ImportFormat.littleCaesars:
          final parser = LittleCaesarsParser();
          result = await parser.parseBytes(bytes, fileName);
          break;
        case ImportFormat.backup:
          // Already handled above
          return;
      }

      state = state.copyWith(
        isLoading: false,
        parsedData: result,
        progress: 1.0,
      );
    } on FormatException catch (e) {
      // Format validation error - show user-friendly message
      state = state.copyWith(
        isLoading: false,
        error: e.message,
        progress: 0,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        progress: 0,
      );
    }
  }

  /// Parse file from path (native platforms only)
  Future<void> parseFilePath(String path, ImportFormat format) async {
    if (kIsWeb) {
      state = state.copyWith(
        isLoading: false,
        error: 'File path not supported on web',
        progress: 0,
      );
      return;
    }

    final file = File(path);
    final bytes = await file.readAsBytes();
    final fileName = path.split('/').last;
    await parseFileBytes(bytes, fileName, format);
  }

  /// Update parsed data (for manual corrections)
  void updateParsedData(ParsedFundraiserData data) {
    state = state.copyWith(parsedData: data);
  }

  /// Update a specific customer in the parsed data
  void updateCustomer(int index, ParsedCustomerData customer) {
    final data = state.parsedData;
    if (data == null) return;

    final customers = List<ParsedCustomerData>.from(data.customers);
    customers[index] = customer;
    state = state.copyWith(
      parsedData: data.copyWith(customers: customers),
    );
  }

  /// Save parsed data to database
  /// [name] - Optional custom name to override the parsed name
  Future<String> saveToDatabase({String? name}) async {
    final data = state.parsedData;
    if (data == null) {
      throw Exception('No parsed data to save');
    }

    state = state.copyWith(isLoading: true, progress: 0.1);

    try {
      final now = DateTime.now().toIso8601String();
      final fundraiserId = _uuid.v4();
      final fundraiserName = name ?? data.name;

      // Create fundraiser
      await _db.insertFundraiser(FundraisersCompanion.insert(
        id: fundraiserId,
        name: fundraiserName,
        deliveryDate: Value(data.deliveryDate),
        deliveryLocation: Value(data.deliveryLocation),
        deliveryTime: Value(data.deliveryTime),
        sourceFileName: Value(data.sourceFileName),
        sourceType: data.sourceType,
        importedAt: now,
        createdAt: now,
      ));

      state = state.copyWith(progress: 0.2);

      // First pass: collect all unique items from all orders
      final uniqueItems = <String, FundraiserItemsCompanion>{};
      for (final customerData in data.customers) {
        for (final orderData in customerData.orders) {
          for (final itemData in orderData.items) {
            final key = '${itemData.productName}|${itemData.sku ?? ''}';
            if (!uniqueItems.containsKey(key)) {
              uniqueItems[key] = FundraiserItemsCompanion.insert(
                id: _uuid.v4(),
                fundraiserId: fundraiserId,
                productName: itemData.productName,
                sku: Value(itemData.sku),
                createdAt: now,
              );
            }
          }
        }
      }

      // Insert fundraiser items
      await _db.insertFundraiserItems(uniqueItems.values.toList());

      // Create a map from product key to item ID for fast lookup
      final itemIdMap = <String, String>{};
      for (final entry in uniqueItems.entries) {
        itemIdMap[entry.key] = entry.value.id.value;
      }

      state = state.copyWith(progress: 0.3);

      // Create customers and orders
      final customers = <CustomersCompanion>[];
      final orders = <OrdersCompanion>[];
      final orderItems = <OrderItemsCompanion>[];

      for (var i = 0; i < data.customers.length; i++) {
        final customerData = data.customers[i];
        final customerId = _uuid.v4();

        customers.add(CustomersCompanion.insert(
          id: customerId,
          fundraiserId: fundraiserId,
          displayName: customerData.displayName,
          emailNormalized: Value(customerData.email?.toLowerCase().trim()),
          phoneNormalized: Value(_normalizePhone(customerData.phone)),
          originalNames: jsonEncode(customerData.originalNames),
          originalEmails: jsonEncode(customerData.originalEmails),
          originalPhones: jsonEncode(customerData.originalPhones),
          totalBoxes: Value(customerData.totalBoxes),
          createdAt: now,
        ));

        // Create orders for this customer
        for (final orderData in customerData.orders) {
          final orderId = _uuid.v4();

          orders.add(OrdersCompanion.insert(
            id: orderId,
            customerId: customerId,
            fundraiserId: fundraiserId,
            originalOrderId: Value(orderData.originalOrderId),
            orderDate: Value(orderData.orderDate),
            paymentStatus: Value(orderData.paymentStatus),
            buyerName: Value(orderData.buyerName),
            buyerPhone: Value(orderData.buyerPhone),
            boxCount: Value(orderData.boxCount),
            rawText: Value(orderData.rawText),
            createdAt: now,
          ));

          // Create order items referencing fundraiser items
          for (var j = 0; j < orderData.items.length; j++) {
            final itemData = orderData.items[j];
            final key = '${itemData.productName}|${itemData.sku ?? ''}';
            final fundraiserItemId = itemIdMap[key]!;

            orderItems.add(OrderItemsCompanion.insert(
              id: _uuid.v4(),
              orderId: orderId,
              fundraiserItemId: fundraiserItemId,
              quantity: itemData.quantity,
              unitPriceCents: Value(itemData.unitPriceCents),
              totalPriceCents: Value(itemData.totalPriceCents),
              sortOrder: Value(j),
            ));
          }
        }

        // Update progress
        state = state.copyWith(
          progress: 0.3 + (0.6 * (i + 1) / data.customers.length),
        );
      }

      // Batch insert all records
      await _db.insertCustomers(customers);
      await _db.insertOrders(orders);
      await _db.insertOrderItems(orderItems);

      state = state.copyWith(isLoading: false, progress: 1.0);
      return fundraiserId;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        progress: 0,
      );
      rethrow;
    }
  }

  String? _normalizePhone(String? phone) {
    if (phone == null || phone.isEmpty) return null;
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return null;
    return digits.substring(digits.length - 10);
  }

  /// Rename a customer's display name (preserves original name in history)
  void renameCustomer(int index, String newName) {
    final data = state.parsedData;
    if (data == null || index < 0 || index >= data.customers.length) return;

    final customer = data.customers[index];
    final newOriginalNames = [...customer.originalNames];

    // Add the old display name to originalNames if not already present
    if (!newOriginalNames.contains(customer.displayName)) {
      newOriginalNames.add(customer.displayName);
    }

    final updatedCustomer = customer.copyWith(
      displayName: newName,
      originalNames: newOriginalNames,
    );

    final customers = List<ParsedCustomerData>.from(data.customers);
    customers[index] = updatedCustomer;
    state = state.copyWith(parsedData: data.copyWith(customers: customers));
  }

  /// Merge source customer into target customer (combines contact info and orders)
  void mergeCustomers(int sourceIndex, int targetIndex) {
    final data = state.parsedData;
    if (data == null ||
        sourceIndex < 0 ||
        sourceIndex >= data.customers.length ||
        targetIndex < 0 ||
        targetIndex >= data.customers.length ||
        sourceIndex == targetIndex) {
      return;
    }

    final source = data.customers[sourceIndex];
    final target = data.customers[targetIndex];

    // Merge original names (deduplicated)
    final mergedNames = <String>{
      ...target.originalNames,
      ...source.originalNames,
      target.displayName,
      source.displayName,
    }.toList();

    // Merge original emails (deduplicated)
    final mergedEmails = <String>{
      ...target.originalEmails,
      ...source.originalEmails,
    }.toList();

    // Merge original phones (deduplicated)
    final mergedPhones = <String>{
      ...target.originalPhones,
      ...source.originalPhones,
    }.toList();

    // Combine orders
    final mergedOrders = [...target.orders, ...source.orders];

    // Sum total boxes
    final mergedTotalBoxes = target.totalBoxes + source.totalBoxes;

    // Create merged customer (keeping target's identity)
    final mergedCustomer = target.copyWith(
      originalNames: mergedNames,
      originalEmails: mergedEmails,
      originalPhones: mergedPhones,
      email: target.email ?? source.email,
      phone: target.phone ?? source.phone,
      orders: mergedOrders,
      totalBoxes: mergedTotalBoxes,
    );

    // Build new customers list without the source
    final customers = <ParsedCustomerData>[];
    for (var i = 0; i < data.customers.length; i++) {
      if (i == sourceIndex) {
        // Skip the source customer (it's being merged)
        continue;
      } else if (i == targetIndex) {
        // Replace target with merged customer
        customers.add(mergedCustomer);
      } else {
        customers.add(data.customers[i]);
      }
    }

    state = state.copyWith(parsedData: data.copyWith(customers: customers));
  }

  /// Restore a backup file to database
  /// [name] - Optional custom name to override the backup name
  /// [restorePickupStatus] - Whether to restore pickup events (default: true)
  Future<String> saveBackupToDatabase({
    String? name,
    bool restorePickupStatus = true,
  }) async {
    final backup = state.backupData;
    if (backup == null) {
      throw Exception('No backup data to restore');
    }

    state = state.copyWith(isLoading: true, progress: 0.1);

    try {
      final now = DateTime.now().toIso8601String();
      final fundraiserId = _uuid.v4();
      final fundraiserName = name ?? backup.fundraiser.name;

      // Create ID mappings from old to new
      final customerIdMap = <String, String>{};
      final orderIdMap = <String, String>{};
      final itemIdMap = <String, String>{};

      // Create fundraiser
      await _db.insertFundraiser(FundraisersCompanion.insert(
        id: fundraiserId,
        name: fundraiserName,
        deliveryDate: Value(backup.fundraiser.deliveryDate),
        deliveryLocation: Value(backup.fundraiser.deliveryLocation),
        deliveryTime: Value(backup.fundraiser.deliveryTime),
        sourceFileName: Value(backup.sourceFileName),
        sourceType: 'backup',
        importedAt: now,
        createdAt: now,
      ));

      state = state.copyWith(progress: 0.2);

      // Create fundraiser items with new IDs
      final fundraiserItems = <FundraiserItemsCompanion>[];
      for (final item in backup.fundraiserItems) {
        final newId = _uuid.v4();
        itemIdMap[item.id] = newId;
        fundraiserItems.add(FundraiserItemsCompanion.insert(
          id: newId,
          fundraiserId: fundraiserId,
          productName: item.productName,
          sku: Value(item.sku),
          verifiedAt: Value(item.verifiedAt),
          createdAt: now,
        ));
      }
      await _db.insertFundraiserItems(fundraiserItems);

      state = state.copyWith(progress: 0.3);

      // Create customers with new IDs
      final customers = <CustomersCompanion>[];
      for (final customer in backup.customers) {
        final newId = _uuid.v4();
        customerIdMap[customer.id] = newId;
        customers.add(CustomersCompanion.insert(
          id: newId,
          fundraiserId: fundraiserId,
          displayName: customer.displayName,
          emailNormalized: Value(customer.emailNormalized),
          phoneNormalized: Value(customer.phoneNormalized),
          originalNames: customer.originalNames,
          originalEmails: customer.originalEmails,
          originalPhones: customer.originalPhones,
          totalBoxes: Value(customer.totalBoxes),
          createdAt: now,
        ));
      }
      await _db.insertCustomers(customers);

      state = state.copyWith(progress: 0.5);

      // Create orders and order items with new IDs
      final orders = <OrdersCompanion>[];
      final orderItems = <OrderItemsCompanion>[];

      for (final order in backup.orders) {
        final newOrderId = _uuid.v4();
        final newCustomerId = customerIdMap[order.customerId];
        if (newCustomerId == null) continue;

        orderIdMap[order.id] = newOrderId;
        orders.add(OrdersCompanion.insert(
          id: newOrderId,
          customerId: newCustomerId,
          fundraiserId: fundraiserId,
          originalOrderId: Value(order.orderId),
          orderDate: Value(order.orderDate),
          paymentStatus: Value(order.paymentStatus),
          buyerName: Value(order.buyerName),
          buyerPhone: Value(order.buyerPhone),
          createdAt: now,
        ));

        for (final item in order.items) {
          final newItemId = itemIdMap[item.fundraiserItemId];
          if (newItemId == null) continue;

          orderItems.add(OrderItemsCompanion.insert(
            id: _uuid.v4(),
            orderId: newOrderId,
            fundraiserItemId: newItemId,
            quantity: item.quantity,
            unitPriceCents: Value(item.unitPriceCents),
            totalPriceCents: Value(item.totalPriceCents),
            sortOrder: Value(item.sortOrder),
          ));
        }
      }

      await _db.insertOrders(orders);
      await _db.insertOrderItems(orderItems);

      state = state.copyWith(progress: 0.8);

      // Restore pickup events if requested
      if (restorePickupStatus) {
        for (final pickup in backup.pickupEvents) {
          final newCustomerId = customerIdMap[pickup.customerId];
          if (newCustomerId == null) continue;

          await _db.insertPickupEvent(PickupEventsCompanion.insert(
            id: _uuid.v4(),
            customerId: newCustomerId,
            fundraiserId: fundraiserId,
            status: pickup.status,
            pickedUpAt: Value(pickup.pickedUpAt),
            volunteerInitials: Value(pickup.volunteerInitials),
            notes: Value(pickup.notes),
            createdAt: now,
            updatedAt: now,
          ));
        }
      }

      state = state.copyWith(isLoading: false, progress: 1.0);
      return fundraiserId;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        progress: 0,
      );
      rethrow;
    }
  }

  /// Reset import state
  void reset() {
    state = const ImportState();
  }
}

/// Provider for import state and operations
final importProvider = StateNotifierProvider<ImportNotifier, ImportState>((ref) {
  final db = ref.watch(databaseProvider);
  return ImportNotifier(db);
});
