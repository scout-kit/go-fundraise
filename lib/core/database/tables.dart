import 'package:drift/drift.dart';

/// Core tables for the Go Fundraise app database

@DataClassName('Fundraiser')
class Fundraisers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get deliveryDate => text().nullable()();
  TextColumn get deliveryLocation => text().nullable()();
  TextColumn get deliveryTime => text().nullable()();
  TextColumn get sourceFileName => text().nullable()();
  TextColumn get sourceType => text()(); // 'pdf' | 'csv'
  TextColumn get importedAt => text()();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Customer')
class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get fundraiserId => text().references(Fundraisers, #id)();
  TextColumn get displayName => text()();
  TextColumn get emailNormalized => text().nullable()();
  TextColumn get phoneNormalized => text().nullable()();
  TextColumn get originalNames => text()(); // JSON array
  TextColumn get originalEmails => text()(); // JSON array
  TextColumn get originalPhones => text()(); // JSON array
  IntColumn get totalBoxes => integer().withDefault(const Constant(0))();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Order')
class Orders extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get fundraiserId => text().references(Fundraisers, #id)();
  TextColumn get originalOrderId => text().nullable()();
  TextColumn get orderDate => text().nullable()();
  TextColumn get paymentStatus => text().nullable()();
  TextColumn get buyerName => text().nullable()(); // Buyer name (for LC: the supporter)
  TextColumn get buyerPhone => text().nullable()(); // Buyer's phone number
  IntColumn get boxCount => integer().nullable()();
  TextColumn get rawText => text().nullable()(); // Original parsed block
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Unique items for a fundraiser (normalized product catalog)
@DataClassName('FundraiserItem')
class FundraiserItems extends Table {
  TextColumn get id => text()();
  TextColumn get fundraiserId => text().references(Fundraisers, #id)();
  TextColumn get productName => text()();
  TextColumn get sku => text().nullable()();
  TextColumn get verifiedAt => text().nullable()(); // When item was verified as received
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('OrderItem')
class OrderItems extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text().references(Orders, #id)();
  TextColumn get fundraiserItemId => text().references(FundraiserItems, #id)();
  IntColumn get quantity => integer()();
  IntColumn get unitPriceCents => integer().nullable()();
  IntColumn get totalPriceCents => integer().nullable()();
  IntColumn get sortOrder => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PickupEvent')
class PickupEvents extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get fundraiserId => text().references(Fundraisers, #id)();
  TextColumn get status => text()(); // 'picked_up' | 'partial' | 'not_picked_up'
  TextColumn get pickedUpAt => text().nullable()();
  TextColumn get volunteerInitials => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Photo')
class Photos extends Table {
  TextColumn get id => text()();
  TextColumn get fundraiserId => text().references(Fundraisers, #id)();
  TextColumn get filePath => text()();
  TextColumn get caption => text().nullable()();
  /// FK to FundraiserItems - links photo to a specific item (nullable for unassociated photos)
  TextColumn get fundraiserItemId =>
      text().nullable().references(FundraiserItems, #id)();
  TextColumn get thumbnailPath => text().nullable()();
  TextColumn get createdAt => text()();

  @override
  Set<Column> get primaryKey => {id};
}

