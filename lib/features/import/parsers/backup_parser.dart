import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Parser for Go Fundraise backup files (.sfb compressed)
class BackupParser {
  /// Parse backup from compressed .sfb bytes
  Future<BackupData> parseBytes(Uint8List bytes, String fileName) async {
    // Verify gzip magic bytes (1f 8b)
    if (bytes.length < 2 || bytes[0] != 0x1f || bytes[1] != 0x8b) {
      throw const FormatException(
        'Invalid backup file. Please select a valid .sfb backup file.',
      );
    }

    // Decompress gzip data
    final decompressed = GZipDecoder().decodeBytes(bytes);
    final jsonBytes = Uint8List.fromList(decompressed);

    final jsonString = utf8.decode(jsonBytes);
    final data = jsonDecode(jsonString) as Map<String, dynamic>;

    // Validate version
    final version = data['version'] as int?;
    if (version == null || version > 1) {
      throw FormatException(
        'Unsupported backup version. Please update the app to import this file.',
      );
    }

    // Validate required fields
    if (!data.containsKey('fundraiser')) {
      throw FormatException(
        'Invalid backup file: missing fundraiser data.',
      );
    }

    final fundraiserData = data['fundraiser'] as Map<String, dynamic>;
    final customersData = (data['customers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final ordersData = (data['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final fundraiserItemsData = (data['fundraiserItems'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final pickupEventsData = (data['pickupEvents'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return BackupData(
      exportedAt: data['exportedAt'] as String?,
      fundraiser: BackupFundraiser.fromJson(fundraiserData),
      customers: customersData.map((c) => BackupCustomer.fromJson(c)).toList(),
      orders: ordersData.map((o) => BackupOrder.fromJson(o)).toList(),
      fundraiserItems: fundraiserItemsData.map((i) => BackupFundraiserItem.fromJson(i)).toList(),
      pickupEvents: pickupEventsData.map((p) => BackupPickupEvent.fromJson(p)).toList(),
      sourceFileName: fileName,
    );
  }

  /// Validate if bytes look like a compressed backup file
  static bool isBackupFile(Uint8List bytes) {
    // Check for gzip magic bytes (1f 8b)
    return bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
  }
}

/// Parsed backup data structure
class BackupData {
  final String? exportedAt;
  final BackupFundraiser fundraiser;
  final List<BackupCustomer> customers;
  final List<BackupOrder> orders;
  final List<BackupFundraiserItem> fundraiserItems;
  final List<BackupPickupEvent> pickupEvents;
  final String sourceFileName;

  BackupData({
    this.exportedAt,
    required this.fundraiser,
    required this.customers,
    required this.orders,
    required this.fundraiserItems,
    required this.pickupEvents,
    required this.sourceFileName,
  });

  /// Total number of customers
  int get customerCount => customers.length;

  /// Total number of orders
  int get orderCount => orders.length;

  /// Number of customers already picked up
  int get pickedUpCount => pickupEvents.where((p) => p.status == 'picked_up').length;
}

class BackupFundraiser {
  final String id;
  final String name;
  final String? deliveryDate;
  final String? deliveryLocation;
  final String? deliveryTime;
  final String? sourceFileName;
  final String? sourceType;
  final String? importedAt;
  final String createdAt;

  BackupFundraiser({
    required this.id,
    required this.name,
    this.deliveryDate,
    this.deliveryLocation,
    this.deliveryTime,
    this.sourceFileName,
    this.sourceType,
    this.importedAt,
    required this.createdAt,
  });

  factory BackupFundraiser.fromJson(Map<String, dynamic> json) {
    return BackupFundraiser(
      id: json['id'] as String,
      name: json['name'] as String,
      deliveryDate: json['deliveryDate'] as String?,
      deliveryLocation: json['deliveryLocation'] as String?,
      deliveryTime: json['deliveryTime'] as String?,
      sourceFileName: json['sourceFileName'] as String?,
      sourceType: json['sourceType'] as String?,
      importedAt: json['importedAt'] as String?,
      createdAt: json['createdAt'] as String,
    );
  }
}

class BackupCustomer {
  final String id;
  final String fundraiserId;
  final String displayName;
  final String? emailNormalized;
  final String? phoneNormalized;
  final String originalNames;
  final String originalEmails;
  final String originalPhones;
  final int totalBoxes;
  final String createdAt;

  BackupCustomer({
    required this.id,
    required this.fundraiserId,
    required this.displayName,
    this.emailNormalized,
    this.phoneNormalized,
    required this.originalNames,
    required this.originalEmails,
    required this.originalPhones,
    required this.totalBoxes,
    required this.createdAt,
  });

  factory BackupCustomer.fromJson(Map<String, dynamic> json) {
    return BackupCustomer(
      id: json['id'] as String,
      fundraiserId: json['fundraiserId'] as String,
      displayName: json['displayName'] as String,
      emailNormalized: json['emailNormalized'] as String?,
      phoneNormalized: json['phoneNormalized'] as String?,
      originalNames: json['originalNames'] as String,
      originalEmails: json['originalEmails'] as String,
      originalPhones: json['originalPhones'] as String,
      totalBoxes: json['totalBoxes'] as int,
      createdAt: json['createdAt'] as String,
    );
  }
}

class BackupOrder {
  final String id;
  final String customerId;
  final String fundraiserId;
  final String? orderId;
  final String? orderDate;
  final String? paymentStatus;
  final String? buyerName;
  final String? buyerPhone;
  final List<BackupOrderItem> items;

  BackupOrder({
    required this.id,
    required this.customerId,
    required this.fundraiserId,
    this.orderId,
    this.orderDate,
    this.paymentStatus,
    this.buyerName,
    this.buyerPhone,
    required this.items,
  });

  factory BackupOrder.fromJson(Map<String, dynamic> json) {
    final itemsData = (json['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return BackupOrder(
      id: json['id'] as String,
      customerId: json['customerId'] as String,
      fundraiserId: json['fundraiserId'] as String,
      orderId: json['orderId'] as String?,
      orderDate: json['orderDate'] as String?,
      paymentStatus: json['paymentStatus'] as String?,
      buyerName: json['buyerName'] as String?,
      buyerPhone: json['buyerPhone'] as String?,
      items: itemsData.map((i) => BackupOrderItem.fromJson(i)).toList(),
    );
  }
}

class BackupOrderItem {
  final String id;
  final String orderId;
  final String fundraiserItemId;
  final int quantity;
  final int? unitPriceCents;
  final int? totalPriceCents;
  final int? sortOrder;

  BackupOrderItem({
    required this.id,
    required this.orderId,
    required this.fundraiserItemId,
    required this.quantity,
    this.unitPriceCents,
    this.totalPriceCents,
    this.sortOrder,
  });

  factory BackupOrderItem.fromJson(Map<String, dynamic> json) {
    return BackupOrderItem(
      id: json['id'] as String,
      orderId: json['orderId'] as String,
      fundraiserItemId: json['fundraiserItemId'] as String,
      quantity: json['quantity'] as int,
      unitPriceCents: json['unitPriceCents'] as int?,
      totalPriceCents: json['totalPriceCents'] as int?,
      sortOrder: json['sortOrder'] as int?,
    );
  }
}

class BackupFundraiserItem {
  final String id;
  final String fundraiserId;
  final String productName;
  final String? sku;
  final String? verifiedAt;
  final String createdAt;

  BackupFundraiserItem({
    required this.id,
    required this.fundraiserId,
    required this.productName,
    this.sku,
    this.verifiedAt,
    required this.createdAt,
  });

  factory BackupFundraiserItem.fromJson(Map<String, dynamic> json) {
    return BackupFundraiserItem(
      id: json['id'] as String,
      fundraiserId: json['fundraiserId'] as String,
      productName: json['productName'] as String,
      sku: json['sku'] as String?,
      verifiedAt: json['verifiedAt'] as String?,
      createdAt: json['createdAt'] as String,
    );
  }
}

class BackupPickupEvent {
  final String id;
  final String customerId;
  final String fundraiserId;
  final String status;
  final String? pickedUpAt;
  final String? volunteerInitials;
  final String? notes;
  final String createdAt;

  BackupPickupEvent({
    required this.id,
    required this.customerId,
    required this.fundraiserId,
    required this.status,
    this.pickedUpAt,
    this.volunteerInitials,
    this.notes,
    required this.createdAt,
  });

  factory BackupPickupEvent.fromJson(Map<String, dynamic> json) {
    return BackupPickupEvent(
      id: json['id'] as String,
      customerId: json['customerId'] as String,
      fundraiserId: json['fundraiserId'] as String,
      status: json['status'] as String,
      pickedUpAt: json['pickedUpAt'] as String?,
      volunteerInitials: json['volunteerInitials'] as String?,
      notes: json['notes'] as String?,
      createdAt: json['createdAt'] as String,
    );
  }
}
