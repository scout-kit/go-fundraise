import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_fundraise/core/database/tables.dart';
import 'package:go_fundraise/core/database/connection/connection.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Fundraisers,
    Customers,
    Orders,
    FundraiserItems,
    OrderItems,
    PickupEvents,
    Photos,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(createDatabaseConnection());

  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        // Create indexes for search performance
        await customStatement('''
          CREATE INDEX IF NOT EXISTS idx_customers_fundraiser
          ON customers(fundraiser_id)
        ''');
        await customStatement('''
          CREATE INDEX IF NOT EXISTS idx_customers_search
          ON customers(fundraiser_id, display_name, phone_normalized, email_normalized)
        ''');
        await customStatement('''
          CREATE INDEX IF NOT EXISTS idx_orders_customer
          ON orders(customer_id)
        ''');
        await customStatement('''
          CREATE INDEX IF NOT EXISTS idx_pickup_customer
          ON pickup_events(customer_id)
        ''');
        await customStatement('''
          CREATE INDEX IF NOT EXISTS idx_photos_fundraiser
          ON photos(fundraiser_id)
        ''');
        await customStatement('''
          CREATE INDEX IF NOT EXISTS idx_fundraiser_items_fundraiser
          ON fundraiser_items(fundraiser_id)
        ''');
        // Unique constraint: only one photo per fundraiser item (nulls are allowed)
        await customStatement('''
          CREATE UNIQUE INDEX IF NOT EXISTS idx_photos_fundraiser_item_unique
          ON photos(fundraiser_item_id) WHERE fundraiser_item_id IS NOT NULL
        ''');
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 3) {
          // Drop old item_verifications table if exists
          await customStatement('DROP TABLE IF EXISTS item_verifications');
          // Create new fundraiser_items table
          await m.createTable(fundraiserItems);
          await customStatement('''
            CREATE INDEX IF NOT EXISTS idx_fundraiser_items_fundraiser
            ON fundraiser_items(fundraiser_id)
          ''');
          // Recreate order_items with new schema (foreign key to fundraiser_items)
          // This requires migrating existing data - for simplicity, we'll drop and recreate
          await customStatement('DROP TABLE IF EXISTS order_items');
          await m.createTable(orderItems);
        }
        if (from < 4) {
          // Migration: Replace associatedSku/associatedLabel with fundraiserItemId FK
          // Add new column
          await customStatement('''
            ALTER TABLE photos ADD COLUMN fundraiser_item_id TEXT
            REFERENCES fundraiser_items(id)
          ''');
          // Migrate existing associations by matching SKU or product name
          await customStatement('''
            UPDATE photos
            SET fundraiser_item_id = (
              SELECT fi.id FROM fundraiser_items fi
              WHERE fi.fundraiser_id = photos.fundraiser_id
              AND (
                (photos.associated_sku IS NOT NULL AND photos.associated_sku != '' AND fi.sku = photos.associated_sku)
                OR (
                  (photos.associated_sku IS NULL OR photos.associated_sku = '')
                  AND photos.associated_label IS NOT NULL
                  AND fi.product_name = photos.associated_label
                )
              )
              LIMIT 1
            )
            WHERE photos.associated_sku IS NOT NULL OR photos.associated_label IS NOT NULL
          ''');
          // Drop old columns (SQLite doesn't support DROP COLUMN before 3.35, so we recreate)
          // For simplicity, we'll leave the old columns but they won't be used
          // Create unique index for one-photo-per-item constraint
          await customStatement('''
            CREATE UNIQUE INDEX IF NOT EXISTS idx_photos_fundraiser_item_unique
            ON photos(fundraiser_item_id) WHERE fundraiser_item_id IS NOT NULL
          ''');
        }
        if (from < 5) {
          // Migration: Add buyer_name and buyer_phone columns to orders table
          // These store the buyer info (for LC: the supporter who placed the order)
          await customStatement('''
            ALTER TABLE orders ADD COLUMN buyer_name TEXT
          ''');
          await customStatement('''
            ALTER TABLE orders ADD COLUMN buyer_phone TEXT
          ''');
        }
      },
    );
  }

  // Fundraiser queries
  Future<List<Fundraiser>> getAllFundraisers() =>
      (select(fundraisers)..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Stream<List<Fundraiser>> watchAllFundraisers() =>
      (select(fundraisers)..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  Future<Fundraiser?> getFundraiserById(String id) =>
      (select(fundraisers)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertFundraiser(FundraisersCompanion fundraiser) =>
      into(fundraisers).insert(fundraiser);

  Future<bool> updateFundraiser(FundraisersCompanion fundraiser) =>
      update(fundraisers).replace(Fundraiser(
        id: fundraiser.id.value,
        name: fundraiser.name.value,
        deliveryDate: fundraiser.deliveryDate.value,
        deliveryLocation: fundraiser.deliveryLocation.value,
        deliveryTime: fundraiser.deliveryTime.value,
        sourceFileName: fundraiser.sourceFileName.value,
        sourceType: fundraiser.sourceType.value,
        importedAt: fundraiser.importedAt.value,
        createdAt: fundraiser.createdAt.value,
      ));

  Future<int> deleteFundraiser(String id) async {
    // Delete all related data first
    await (delete(photos)..where((t) => t.fundraiserId.equals(id))).go();
    await (delete(pickupEvents)..where((t) => t.fundraiserId.equals(id))).go();
    await (delete(orderItems)
          ..where((t) => t.orderId.isInQuery(
              selectOnly(orders)
                ..addColumns([orders.id])
                ..where(orders.fundraiserId.equals(id)))))
        .go();
    await (delete(orders)..where((t) => t.fundraiserId.equals(id))).go();
    await (delete(customers)..where((t) => t.fundraiserId.equals(id))).go();
    await (delete(fundraiserItems)..where((t) => t.fundraiserId.equals(id))).go();
    return (delete(fundraisers)..where((t) => t.id.equals(id))).go();
  }

  // Customer queries
  Future<List<Customer>> getCustomersByFundraiser(String fundraiserId) =>
      (select(customers)
            ..where((t) => t.fundraiserId.equals(fundraiserId))
            ..orderBy([(t) => OrderingTerm.asc(t.displayName)]))
          .get();

  Stream<List<Customer>> watchCustomersByFundraiser(String fundraiserId) =>
      (select(customers)
            ..where((t) => t.fundraiserId.equals(fundraiserId))
            ..orderBy([(t) => OrderingTerm.asc(t.displayName)]))
          .watch();

  Future<Customer?> getCustomerById(String id) =>
      (select(customers)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<Customer>> searchCustomers(
    String fundraiserId,
    String query,
  ) async {
    final normalizedQuery = query.toLowerCase().trim();
    if (normalizedQuery.isEmpty) {
      return getCustomersByFundraiser(fundraiserId);
    }

    return (select(customers)
          ..where((t) =>
              t.fundraiserId.equals(fundraiserId) &
              (t.displayName.lower().contains(normalizedQuery) |
                  t.emailNormalized.contains(normalizedQuery) |
                  t.phoneNormalized.contains(normalizedQuery)))
          ..orderBy([(t) => OrderingTerm.asc(t.displayName)])
          ..limit(50))
        .get();
  }

  Future<int> insertCustomer(CustomersCompanion customer) =>
      into(customers).insert(customer);

  Future<void> insertCustomers(List<CustomersCompanion> customerList) async {
    await batch((batch) {
      batch.insertAll(customers, customerList);
    });
  }

  /// Update a customer record
  Future<bool> updateCustomer(Customer customer) =>
      update(customers).replace(customer);

  /// Delete a customer and their associated pickup events
  Future<int> deleteCustomer(String customerId) async {
    await (delete(pickupEvents)..where((t) => t.customerId.equals(customerId))).go();
    return (delete(customers)..where((t) => t.id.equals(customerId))).go();
  }

  /// Move all orders from one customer to another
  Future<int> moveOrdersToCustomer(String fromCustomerId, String toCustomerId) async {
    return (update(orders)..where((t) => t.customerId.equals(fromCustomerId)))
        .write(OrdersCompanion(customerId: Value(toCustomerId)));
  }

  /// Merge two customers: combines contact info, moves orders, deletes source
  /// The target customer will have combined originalNames/Emails/Phones arrays
  Future<void> mergeCustomers(String sourceId, String targetId) async {
    await transaction(() async {
      final source = await getCustomerById(sourceId);
      final target = await getCustomerById(targetId);
      if (source == null || target == null) {
        throw Exception('Customer not found');
      }

      // Decode and merge JSON arrays
      List<String> mergeJsonArrays(String sourceJson, String targetJson) {
        final sourceList = (jsonDecode(sourceJson) as List).cast<String>();
        final targetList = (jsonDecode(targetJson) as List).cast<String>();
        final merged = <String>{...targetList, ...sourceList}.toList();
        return merged;
      }

      final mergedNames = mergeJsonArrays(source.originalNames, target.originalNames);
      final mergedEmails = mergeJsonArrays(source.originalEmails, target.originalEmails);
      final mergedPhones = mergeJsonArrays(source.originalPhones, target.originalPhones);

      // Move orders from source to target
      await moveOrdersToCustomer(sourceId, targetId);

      // Update target customer with merged data
      final updatedTarget = Customer(
        id: target.id,
        fundraiserId: target.fundraiserId,
        displayName: target.displayName,
        emailNormalized: target.emailNormalized ?? source.emailNormalized,
        phoneNormalized: target.phoneNormalized ?? source.phoneNormalized,
        originalNames: jsonEncode(mergedNames),
        originalEmails: jsonEncode(mergedEmails),
        originalPhones: jsonEncode(mergedPhones),
        totalBoxes: target.totalBoxes + source.totalBoxes,
        createdAt: target.createdAt,
      );
      await updateCustomer(updatedTarget);

      // Delete source customer (and their pickup events)
      await deleteCustomer(sourceId);
    });
  }

  // Order queries
  Future<List<Order>> getOrdersByCustomer(String customerId) =>
      (select(orders)
            ..where((t) => t.customerId.equals(customerId))
            ..orderBy([(t) => OrderingTerm.desc(t.orderDate)]))
          .get();

  Future<int> insertOrder(OrdersCompanion order) => into(orders).insert(order);

  Future<void> insertOrders(List<OrdersCompanion> orderList) async {
    await batch((batch) {
      batch.insertAll(orders, orderList);
    });
  }

  // Order item queries
  Future<List<OrderItem>> getOrderItemsByOrder(String orderId) =>
      (select(orderItems)
            ..where((t) => t.orderId.equals(orderId))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .get();

  /// Get order items with product info for an order
  Future<List<OrderItemWithProduct>> getOrderItemsWithProductByOrder(String orderId) async {
    final result = await customSelect(
      '''
      SELECT
        oi.id,
        oi.order_id,
        oi.fundraiser_item_id,
        oi.quantity,
        oi.unit_price_cents,
        oi.total_price_cents,
        oi.sort_order,
        fi.product_name,
        fi.sku
      FROM order_items oi
      INNER JOIN fundraiser_items fi ON oi.fundraiser_item_id = fi.id
      WHERE oi.order_id = ?
      ORDER BY oi.sort_order ASC
      ''',
      variables: [Variable.withString(orderId)],
    ).get();

    return result.map((row) => OrderItemWithProduct(
      id: row.read<String>('id'),
      orderId: row.read<String>('order_id'),
      fundraiserItemId: row.read<String>('fundraiser_item_id'),
      quantity: row.read<int>('quantity'),
      unitPriceCents: row.read<int?>('unit_price_cents'),
      totalPriceCents: row.read<int?>('total_price_cents'),
      sortOrder: row.read<int?>('sort_order'),
      productName: row.read<String>('product_name'),
      sku: row.read<String?>('sku'),
    )).toList();
  }

  /// Get order items with product info for a customer
  Future<List<OrderItemWithProduct>> getOrderItemsWithProductByCustomer(String customerId) async {
    final customerOrders = await getOrdersByCustomer(customerId);
    final allItems = <OrderItemWithProduct>[];
    for (final order in customerOrders) {
      final items = await getOrderItemsWithProductByOrder(order.id);
      allItems.addAll(items);
    }
    return allItems;
  }

  Future<List<OrderItem>> getOrderItemsByCustomer(String customerId) async {
    final customerOrders = await getOrdersByCustomer(customerId);
    final allItems = <OrderItem>[];
    for (final order in customerOrders) {
      final items = await getOrderItemsByOrder(order.id);
      allItems.addAll(items);
    }
    return allItems;
  }

  Future<int> insertOrderItem(OrderItemsCompanion item) =>
      into(orderItems).insert(item);

  Future<void> insertOrderItems(List<OrderItemsCompanion> itemList) async {
    await batch((batch) {
      batch.insertAll(orderItems, itemList);
    });
  }

  // Pickup event queries
  Future<PickupEvent?> getPickupEventByCustomer(String customerId) =>
      (select(pickupEvents)..where((t) => t.customerId.equals(customerId)))
          .getSingleOrNull();

  Stream<PickupEvent?> watchPickupEventByCustomer(String customerId) =>
      (select(pickupEvents)..where((t) => t.customerId.equals(customerId)))
          .watchSingleOrNull();

  Future<List<PickupEvent>> getPickupEventsByFundraiser(
          String fundraiserId) =>
      (select(pickupEvents)..where((t) => t.fundraiserId.equals(fundraiserId)))
          .get();

  Stream<List<PickupEvent>> watchPickupEventsByFundraiser(
          String fundraiserId) =>
      (select(pickupEvents)..where((t) => t.fundraiserId.equals(fundraiserId)))
          .watch();

  Future<int> insertPickupEvent(PickupEventsCompanion event) =>
      into(pickupEvents).insert(event);

  Future<bool> updatePickupEvent(PickupEvent event) =>
      update(pickupEvents).replace(event);

  Future<int> deletePickupEvent(String id) =>
      (delete(pickupEvents)..where((t) => t.id.equals(id))).go();

  // Photo queries
  Future<List<Photo>> getPhotosByFundraiser(String fundraiserId) =>
      (select(photos)
            ..where((t) => t.fundraiserId.equals(fundraiserId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Stream<List<Photo>> watchPhotosByFundraiser(String fundraiserId) =>
      (select(photos)
            ..where((t) => t.fundraiserId.equals(fundraiserId))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  Future<int> insertPhoto(PhotosCompanion photo) => into(photos).insert(photo);

  Future<bool> updatePhoto(Photo photo) => update(photos).replace(photo);

  Future<int> deletePhoto(String id) =>
      (delete(photos)..where((t) => t.id.equals(id))).go();

  /// Get photo for a specific fundraiser item by ID (returns single photo or null)
  Future<Photo?> getPhotoByFundraiserItemId(String fundraiserItemId) =>
      (select(photos)..where((t) => t.fundraiserItemId.equals(fundraiserItemId)))
          .getSingleOrNull();

  /// Watch photo for a specific fundraiser item by ID
  Stream<Photo?> watchPhotoByFundraiserItemId(String fundraiserItemId) =>
      (select(photos)..where((t) => t.fundraiserItemId.equals(fundraiserItemId)))
          .watchSingleOrNull();

  /// Update photo's fundraiser item association
  Future<void> updatePhotoFundraiserItemId(
      String photoId, String? fundraiserItemId) async {
    await (update(photos)..where((t) => t.id.equals(photoId)))
        .write(PhotosCompanion(
      fundraiserItemId: Value(fundraiserItemId),
    ));
  }

  /// Clear photo association for a specific item (unlink photo from item)
  Future<int> clearPhotoForFundraiserItem(String fundraiserItemId) async {
    return (update(photos)
          ..where((t) => t.fundraiserItemId.equals(fundraiserItemId)))
        .write(const PhotosCompanion(
      fundraiserItemId: Value(null),
    ));
  }

  /// Get photo counts by fundraiser item ID for a fundraiser
  /// Returns a map where key is fundraiserItemId
  Future<Map<String, int>> getPhotoCountsByItemId(String fundraiserId) async {
    final allPhotos = await getPhotosByFundraiser(fundraiserId);
    final counts = <String, int>{};

    for (final photo in allPhotos) {
      if (photo.fundraiserItemId != null) {
        counts[photo.fundraiserItemId!] =
            (counts[photo.fundraiserItemId!] ?? 0) + 1;
      }
    }

    return counts;
  }

  /// Delete photo for a specific fundraiser item
  Future<int> deletePhotoByFundraiserItemId(String fundraiserItemId) async {
    return (delete(photos)
          ..where((t) => t.fundraiserItemId.equals(fundraiserItemId)))
        .go();
  }

  // Fundraiser item queries
  Future<List<FundraiserItem>> getFundraiserItemsByFundraiser(
          String fundraiserId) =>
      (select(fundraiserItems)
            ..where((t) => t.fundraiserId.equals(fundraiserId))
            ..orderBy([(t) => OrderingTerm.asc(t.productName)]))
          .get();

  Future<FundraiserItem?> getFundraiserItemById(String id) =>
      (select(fundraiserItems)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<List<FundraiserItem>> watchFundraiserItemsByFundraiser(
          String fundraiserId) =>
      (select(fundraiserItems)
            ..where((t) => t.fundraiserId.equals(fundraiserId))
            ..orderBy([(t) => OrderingTerm.asc(t.productName)]))
          .watch();

  Future<FundraiserItem?> getFundraiserItemByProductKey(
      String fundraiserId, String productName, String? sku) =>
      (select(fundraiserItems)
            ..where((t) =>
                t.fundraiserId.equals(fundraiserId) &
                t.productName.equals(productName) &
                (sku != null ? t.sku.equals(sku) : t.sku.isNull())))
          .getSingleOrNull();

  Future<int> insertFundraiserItem(FundraiserItemsCompanion item) =>
      into(fundraiserItems).insert(item);

  Future<void> insertFundraiserItems(List<FundraiserItemsCompanion> itemList) async {
    await batch((batch) {
      batch.insertAll(fundraiserItems, itemList);
    });
  }

  Future<bool> updateFundraiserItem(FundraiserItem item) =>
      update(fundraiserItems).replace(item);

  Future<int> toggleFundraiserItemVerification(String itemId) async {
    final item = await (select(fundraiserItems)..where((t) => t.id.equals(itemId))).getSingleOrNull();
    if (item == null) return 0;

    final now = DateTime.now().toIso8601String();
    final newItem = FundraiserItem(
      id: item.id,
      fundraiserId: item.fundraiserId,
      productName: item.productName,
      sku: item.sku,
      verifiedAt: item.verifiedAt == null ? now : null,
      createdAt: item.createdAt,
    );
    await update(fundraiserItems).replace(newItem);
    return 1;
  }

  Future<void> clearAllFundraiserItemVerifications(String fundraiserId) async {
    await (update(fundraiserItems)..where((t) => t.fundraiserId.equals(fundraiserId)))
        .write(const FundraiserItemsCompanion(verifiedAt: Value(null)));
  }

  /// Get all items aggregated by product for a fundraiser with total quantities
  Future<List<AggregatedFundraiserItem>> getAggregatedItemsByFundraiser(
      String fundraiserId) async {
    final result = await customSelect(
      '''
      SELECT
        fi.id,
        fi.product_name,
        fi.sku,
        fi.verified_at,
        fi.created_at,
        COALESCE(SUM(oi.quantity), 0) as total_quantity
      FROM fundraiser_items fi
      LEFT JOIN order_items oi ON fi.id = oi.fundraiser_item_id
      WHERE fi.fundraiser_id = ?
      GROUP BY fi.id, fi.product_name, fi.sku, fi.verified_at, fi.created_at
      ORDER BY fi.product_name ASC
      ''',
      variables: [Variable.withString(fundraiserId)],
    ).get();

    return result.map((row) {
      return AggregatedFundraiserItem(
        id: row.read<String>('id'),
        productName: row.read<String>('product_name'),
        sku: row.read<String?>('sku'),
        verifiedAt: row.read<String?>('verified_at'),
        totalQuantity: row.read<int>('total_quantity'),
      );
    }).toList();
  }

  // Statistics queries
  Future<FundraiserStats> getFundraiserStats(String fundraiserId) async {
    final customerList = await getCustomersByFundraiser(fundraiserId);
    final pickupList = await getPickupEventsByFundraiser(fundraiserId);

    final pickedUpCount =
        pickupList.where((p) => p.status == 'picked_up').length;

    return FundraiserStats(
      totalCustomers: customerList.length,
      pickedUpCount: pickedUpCount,
      remainingCount: customerList.length - pickedUpCount,
    );
  }

  Stream<FundraiserStats> watchFundraiserStats(String fundraiserId) {
    // Watch pickup events - they change most often during pickup day
    return watchPickupEventsByFundraiser(fundraiserId).asyncMap((pickups) async {
      final customers = await getCustomersByFundraiser(fundraiserId);
      final pickedUpCount = pickups.where((p) => p.status == 'picked_up').length;

      return FundraiserStats(
        totalCustomers: customers.length,
        pickedUpCount: pickedUpCount,
        remainingCount: customers.length - pickedUpCount,
      );
    });
  }
}

class FundraiserStats {
  final int totalCustomers;
  final int pickedUpCount;
  final int remainingCount;

  FundraiserStats({
    required this.totalCustomers,
    required this.pickedUpCount,
    required this.remainingCount,
  });

  double get progressPercent =>
      totalCustomers > 0 ? pickedUpCount / totalCustomers : 0;
}

/// Order item with product info from fundraiser_items join
class OrderItemWithProduct {
  final String id;
  final String orderId;
  final String fundraiserItemId;
  final int quantity;
  final int? unitPriceCents;
  final int? totalPriceCents;
  final int? sortOrder;
  final String productName;
  final String? sku;

  OrderItemWithProduct({
    required this.id,
    required this.orderId,
    required this.fundraiserItemId,
    required this.quantity,
    this.unitPriceCents,
    this.totalPriceCents,
    this.sortOrder,
    required this.productName,
    this.sku,
  });

  /// Display name with SKU if available
  String get displayName =>
      sku != null && sku!.isNotEmpty ? '$productName ($sku)' : productName;
}

/// Aggregated item across all orders in a fundraiser with verification status
class AggregatedFundraiserItem {
  final String id;
  final String productName;
  final String? sku;
  final String? verifiedAt;
  final int totalQuantity;

  AggregatedFundraiserItem({
    required this.id,
    required this.productName,
    this.sku,
    this.verifiedAt,
    required this.totalQuantity,
  });

  /// Whether this item has been verified as received
  bool get isVerified => verifiedAt != null;

  /// Display name with SKU if available
  String get displayName =>
      sku != null && sku!.isNotEmpty ? '$productName ($sku)' : productName;
}

// Provider for the database
final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('Database must be overridden in main.dart');
});

/// Extension on Customer to decode JSON arrays for multiple contacts
extension CustomerExtension on Customer {
  /// Get all unique emails for this customer (decoded from originalEmails JSON)
  List<String> get allEmails {
    try {
      final decoded = jsonDecode(originalEmails);
      if (decoded is List) {
        // Deduplicate by normalizing (lowercase, trim) and using a Set
        final seen = <String>{};
        final unique = <String>[];
        for (final email in decoded) {
          final normalized = email.toString().toLowerCase().trim();
          if (normalized.isNotEmpty && !seen.contains(normalized)) {
            seen.add(normalized);
            unique.add(email.toString());
          }
        }
        return unique;
      }
      return emailNormalized != null ? [emailNormalized!] : [];
    } catch (_) {
      return emailNormalized != null ? [emailNormalized!] : [];
    }
  }

  /// Get all unique phones for this customer (decoded from originalPhones JSON)
  List<String> get allPhones {
    try {
      final decoded = jsonDecode(originalPhones);
      if (decoded is List) {
        // Deduplicate by normalizing (digits only) and using a Set
        final seen = <String>{};
        final unique = <String>[];
        for (final phone in decoded) {
          final normalized = phone.toString().replaceAll(RegExp(r'\D'), '');
          // Use last 10 digits for comparison (handles +1, 1- prefixes)
          final key = normalized.length >= 10
              ? normalized.substring(normalized.length - 10)
              : normalized;
          if (key.isNotEmpty && !seen.contains(key)) {
            seen.add(key);
            unique.add(phone.toString());
          }
        }
        return unique;
      }
      return phoneNormalized != null ? [phoneNormalized!] : [];
    } catch (_) {
      return phoneNormalized != null ? [phoneNormalized!] : [];
    }
  }

  /// Returns true if customer has more than one unique email address
  bool get hasMultipleEmails => allEmails.length > 1;

  /// Returns true if customer has more than one unique phone number
  bool get hasMultiplePhones => allPhones.length > 1;
}
