/// Models for parsed import data before database insertion

class ParsedFundraiserData {
  final String name;
  final String? deliveryDate;
  final String? deliveryLocation;
  final String? deliveryTime;
  final String sourceFileName;
  final String sourceType; // 'pdf' | 'csv'
  final List<ParsedCustomerData> customers;
  final List<String> warnings;
  final List<String> errors;

  ParsedFundraiserData({
    required this.name,
    this.deliveryDate,
    this.deliveryLocation,
    this.deliveryTime,
    required this.sourceFileName,
    required this.sourceType,
    required this.customers,
    this.warnings = const [],
    this.errors = const [],
  });

  int get totalOrders => customers.fold(0, (sum, c) => sum + c.orders.length);
  int get totalBoxes => customers.fold(0, (sum, c) => sum + c.totalBoxes);

  ParsedFundraiserData copyWith({
    String? name,
    String? deliveryDate,
    String? deliveryLocation,
    String? deliveryTime,
    String? sourceFileName,
    String? sourceType,
    List<ParsedCustomerData>? customers,
    List<String>? warnings,
    List<String>? errors,
  }) {
    return ParsedFundraiserData(
      name: name ?? this.name,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      deliveryLocation: deliveryLocation ?? this.deliveryLocation,
      deliveryTime: deliveryTime ?? this.deliveryTime,
      sourceFileName: sourceFileName ?? this.sourceFileName,
      sourceType: sourceType ?? this.sourceType,
      customers: customers ?? this.customers,
      warnings: warnings ?? this.warnings,
      errors: errors ?? this.errors,
    );
  }
}

class ParsedCustomerData {
  final String? id; // Temporary ID for tracking during import
  final String displayName;
  final String? email;
  final String? phone;
  final List<String> originalNames;
  final List<String> originalEmails;
  final List<String> originalPhones;
  final List<ParsedOrderData> orders;
  final int totalBoxes;
  final List<String> warnings;
  final bool needsReview;

  ParsedCustomerData({
    this.id,
    required this.displayName,
    this.email,
    this.phone,
    this.originalNames = const [],
    this.originalEmails = const [],
    this.originalPhones = const [],
    this.orders = const [],
    this.totalBoxes = 0,
    this.warnings = const [],
    this.needsReview = false,
  });

  bool get hasEmail => email != null && email!.isNotEmpty;
  bool get hasPhone => phone != null && phone!.isNotEmpty;
  bool get hasContactInfo => hasEmail || hasPhone;

  ParsedCustomerData copyWith({
    String? id,
    String? displayName,
    String? email,
    String? phone,
    List<String>? originalNames,
    List<String>? originalEmails,
    List<String>? originalPhones,
    List<ParsedOrderData>? orders,
    int? totalBoxes,
    List<String>? warnings,
    bool? needsReview,
  }) {
    return ParsedCustomerData(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      originalNames: originalNames ?? this.originalNames,
      originalEmails: originalEmails ?? this.originalEmails,
      originalPhones: originalPhones ?? this.originalPhones,
      orders: orders ?? this.orders,
      totalBoxes: totalBoxes ?? this.totalBoxes,
      warnings: warnings ?? this.warnings,
      needsReview: needsReview ?? this.needsReview,
    );
  }
}

class ParsedOrderData {
  final String? originalOrderId;
  final String? orderDate;
  final String? paymentStatus;
  final String? buyerName;     // Buyer name (for LC: the supporter who placed the order)
  final String? buyerPhone;    // Buyer's phone number
  final int? boxCount;
  final List<ParsedOrderItemData> items;
  final String? rawText;

  ParsedOrderData({
    this.originalOrderId,
    this.orderDate,
    this.paymentStatus,
    this.buyerName,
    this.buyerPhone,
    this.boxCount,
    this.items = const [],
    this.rawText,
  });

  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);
}

class ParsedOrderItemData {
  final String productName;
  final String? sku;
  final int quantity;
  final int? unitPriceCents;
  final int? totalPriceCents;

  ParsedOrderItemData({
    required this.productName,
    this.sku,
    required this.quantity,
    this.unitPriceCents,
    this.totalPriceCents,
  });
}
