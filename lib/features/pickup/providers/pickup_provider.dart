import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:go_fundraise/core/database/database.dart';

/// Filter options for customer list
enum PickupFilter { all, remaining, pickedUp }

/// State for pickup search
class PickupSearchState {
  final String query;
  final PickupFilter filter;

  const PickupSearchState({
    this.query = '',
    this.filter = PickupFilter.all,
  });

  PickupSearchState copyWith({
    String? query,
    PickupFilter? filter,
  }) {
    return PickupSearchState(
      query: query ?? this.query,
      filter: filter ?? this.filter,
    );
  }
}

/// Notifier for pickup search state
class PickupSearchNotifier extends StateNotifier<PickupSearchState> {
  PickupSearchNotifier() : super(const PickupSearchState());

  void setQuery(String query) {
    state = state.copyWith(query: query);
  }

  void setFilter(PickupFilter filter) {
    state = state.copyWith(filter: filter);
  }

  void reset() {
    state = const PickupSearchState();
  }
}

/// Provider for pickup search state
final pickupSearchProvider =
    StateNotifierProvider.family<PickupSearchNotifier, PickupSearchState, String>(
        (ref, fundraiserId) {
  return PickupSearchNotifier();
});

/// Provider that watches pickup events for a fundraiser
final pickupEventsProvider = StreamProvider.family<List<PickupEvent>, String>(
  (ref, fundraiserId) {
    final db = ref.watch(databaseProvider);
    return db.watchPickupEventsByFundraiser(fundraiserId);
  },
);

/// Provider that watches customers for a fundraiser
final customersProvider = StreamProvider.family<List<Customer>, String>(
  (ref, fundraiserId) {
    final db = ref.watch(databaseProvider);
    return db.watchCustomersByFundraiser(fundraiserId);
  },
);

/// Provider for customers with pickup status
final customersWithPickupProvider = Provider.family<
    AsyncValue<List<CustomerWithPickup>>, String>((ref, fundraiserId) {
  final searchState = ref.watch(pickupSearchProvider(fundraiserId));

  // Watch both customers and pickup events to react to changes in either
  final customersAsync = ref.watch(customersProvider(fundraiserId));
  final pickupEventsAsync = ref.watch(pickupEventsProvider(fundraiserId));

  // Combine both async values
  return customersAsync.when(
    data: (customers) => pickupEventsAsync.when(
      data: (pickupEvents) {
        final pickupMap = {for (var e in pickupEvents) e.customerId: e};

        var results = customers.map((customer) {
          return CustomerWithPickup(
            customer: customer,
            pickupEvent: pickupMap[customer.id],
          );
        }).toList();

        // Apply search filter
        if (searchState.query.isNotEmpty) {
          final query = searchState.query.toLowerCase();
          results = results.where((c) {
            // Search display name
            if (c.customer.displayName.toLowerCase().contains(query)) {
              return true;
            }

            // Search ALL emails (not just primary)
            final emails = c.customer.allEmails;
            if (emails.any((e) => e.toLowerCase().contains(query))) {
              return true;
            }

            // Search ALL phones (not just primary)
            final phones = c.customer.allPhones;
            if (phones.any((p) => p.contains(query))) {
              return true;
            }

            return false;
          }).toList();
        }

        // Apply pickup filter
        switch (searchState.filter) {
          case PickupFilter.remaining:
            results = results.where((c) => !c.isPickedUp).toList();
            break;
          case PickupFilter.pickedUp:
            results = results.where((c) => c.isPickedUp).toList();
            break;
          case PickupFilter.all:
            break;
        }

        return AsyncValue.data(results);
      },
      loading: () => const AsyncValue.loading(),
      error: (e, st) => AsyncValue.error(e, st),
    ),
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});

/// Provider for a single customer with full details
final customerDetailProvider =
    StreamProvider.family<CustomerDetail?, String>((ref, customerId) async* {
  final db = ref.watch(databaseProvider);

  // Watch pickup events for this customer
  await for (final pickupEvent in db.watchPickupEventByCustomer(customerId)) {
    final customer = await db.getCustomerById(customerId);
    if (customer == null) {
      yield null;
      continue;
    }

    final orders = await db.getOrdersByCustomer(customerId);
    final allItems = await db.getOrderItemsWithProductByCustomer(customerId);

    yield CustomerDetail(
      customer: customer,
      orders: orders,
      items: allItems,
      pickupEvent: pickupEvent,
    );
  }
});

/// Provider for pickup operations
final pickupServiceProvider = Provider((ref) {
  final db = ref.watch(databaseProvider);
  return PickupService(db);
});

class PickupService {
  final AppDatabase _db;
  final _uuid = const Uuid();

  PickupService(this._db);

  /// Mark a customer as picked up
  Future<void> markPickedUp(
    String customerId,
    String fundraiserId, {
    String? volunteerInitials,
    String? notes,
  }) async {
    final now = DateTime.now().toIso8601String();
    final existing = await _db.getPickupEventByCustomer(customerId);

    if (existing != null) {
      await _db.updatePickupEvent(existing.copyWith(
        status: 'picked_up',
        pickedUpAt: Value(now),
        volunteerInitials: Value(volunteerInitials),
        notes: Value(notes),
        updatedAt: now,
      ));
    } else {
      await _db.insertPickupEvent(PickupEventsCompanion.insert(
        id: _uuid.v4(),
        customerId: customerId,
        fundraiserId: fundraiserId,
        status: 'picked_up',
        pickedUpAt: Value(now),
        volunteerInitials: Value(volunteerInitials),
        notes: Value(notes),
        createdAt: now,
        updatedAt: now,
      ));
    }
  }

  /// Undo pickup (mark as not picked up)
  Future<void> undoPickup(String customerId) async {
    final existing = await _db.getPickupEventByCustomer(customerId);
    if (existing != null) {
      await _db.deletePickupEvent(existing.id);
    }
  }

  /// Rename a customer's display name (preserves original name in history)
  Future<void> renameCustomer(String customerId, String newName) async {
    final customer = await _db.getCustomerById(customerId);
    if (customer == null) return;

    // Decode current original names
    List<String> originalNames;
    try {
      originalNames = (jsonDecode(customer.originalNames) as List).cast<String>();
    } catch (_) {
      originalNames = [];
    }

    // Add old display name to originalNames if not already present
    if (!originalNames.contains(customer.displayName)) {
      originalNames.add(customer.displayName);
    }

    final updated = customer.copyWith(
      displayName: newName,
      originalNames: jsonEncode(originalNames),
    );

    await _db.updateCustomer(updated);
  }

  /// Merge source customer into target customer
  Future<void> mergeCustomers(String sourceId, String targetId) async {
    await _db.mergeCustomers(sourceId, targetId);
  }

  /// Revert every manual change for a customer: remove manually-added
  /// orders/items, restore imported fields from their snapshot, and put
  /// the customer's contact info back to its imported state. Pickup events
  /// are left alone (they represent volunteer action, not source data).
  Future<void> resetCustomer(String customerId) async {
    await _db.resetCustomerToImport(customerId);
  }

  /// Attach a manually-created order (with [items]) to a customer. Used for
  /// rewards added at pickup (e.g., a "Thank You Crest"). New product names
  /// auto-register as fundraiser items via upsert, so the same reward can
  /// be picked from a list on the next customer. The order and each item
  /// are marked source_kind='manual' so they're removed by a later
  /// "Reset to Original". totalBoxes is recalculated at the end so the
  /// customer card and progress counters stay in sync.
  Future<void> addCustomOrder(
    String customerId, {
    required List<AddCustomItemInput> items,
  }) async {
    if (items.isEmpty) return;

    final customer = await _db.getCustomerById(customerId);
    if (customer == null) return;

    final now = DateTime.now().toIso8601String();
    final orderId = _uuid.v4();

    await _db.insertOrder(OrdersCompanion.insert(
      id: orderId,
      customerId: customerId,
      fundraiserId: customer.fundraiserId,
      sourceKind: const Value('manual'),
      createdAt: now,
    ));

    final companions = <OrderItemsCompanion>[];
    for (var i = 0; i < items.length; i++) {
      final input = items[i];
      final fundraiserItemId = await _db.upsertFundraiserItem(
        id: _uuid.v4(),
        fundraiserId: customer.fundraiserId,
        productName: input.productName,
        sku: input.sku,
        createdAt: now,
      );
      companions.add(OrderItemsCompanion.insert(
        id: _uuid.v4(),
        orderId: orderId,
        fundraiserItemId: fundraiserItemId,
        quantity: input.quantity,
        sortOrder: Value(i),
        sourceKind: const Value('manual'),
      ));
    }
    await _db.insertOrderItems(companions);

    await _db.recalculateCustomerTotalBoxes(customerId);
  }
}

/// Input row for [PickupService.addCustomOrder]. Either references an
/// existing fundraiser item (via productName+sku) or a brand-new one that
/// will be registered on save.
class AddCustomItemInput {
  final String productName;
  final String? sku;
  final int quantity;

  const AddCustomItemInput({
    required this.productName,
    this.sku,
    required this.quantity,
  });
}

/// Customer with pickup status
class CustomerWithPickup {
  final Customer customer;
  final PickupEvent? pickupEvent;

  CustomerWithPickup({
    required this.customer,
    this.pickupEvent,
  });

  bool get isPickedUp => pickupEvent?.status == 'picked_up';
  String? get pickedUpAt => pickupEvent?.pickedUpAt;
  String? get volunteerInitials => pickupEvent?.volunteerInitials;
}

/// Full customer detail with orders and items
class CustomerDetail {
  final Customer customer;
  final List<Order> orders;
  final List<OrderItemWithProduct> items;
  final PickupEvent? pickupEvent;

  CustomerDetail({
    required this.customer,
    required this.orders,
    required this.items,
    this.pickupEvent,
  });

  bool get isPickedUp => pickupEvent?.status == 'picked_up';

  /// Consolidated items across all orders
  /// Returns map of display name (with SKU if available) to quantity
  Map<String, int> get consolidatedItems {
    final map = <String, int>{};
    for (final item in items) {
      map[item.displayName] = (map[item.displayName] ?? 0) + item.quantity;
    }
    return map;
  }
}
