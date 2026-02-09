import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:go_fundraise/core/models/parsed_data.dart';
import 'package:go_fundraise/features/import/parsers/customer_consolidator.dart';
import 'package:go_fundraise/features/import/parsers/parser_utils.dart';

/// Parser for CSV fundraiser data files
class CsvParser {
  /// Parse a CSV file and extract fundraiser data (native platforms)
  Future<ParsedFundraiserData> parse(File file) async {
    final bytes = await file.readAsBytes();
    return parseBytes(bytes, file.path.split('/').last);
  }

  /// Parse CSV from bytes (works on all platforms including web)
  Future<ParsedFundraiserData> parseBytes(Uint8List bytes, String fileName) async {
    final content = utf8.decode(bytes);
    final warnings = <String>[];
    final errors = <String>[];

    // Allow browser event loop to process (fixes "only works with console open" issue on web)
    await Future.microtask(() {});

    // Parse CSV
    final rows = const CsvToListConverter().convert(content, eol: '\n');

    if (rows.isEmpty) {
      errors.add('CSV file is empty');
      return ParsedFundraiserData(
        name: '',
        sourceFileName: fileName,
        sourceType: 'csv',
        customers: [],
        warnings: warnings,
        errors: errors,
      );
    }

    // Find header row and map columns
    final columnMap = _mapColumns(rows.first.map((e) => e.toString()).toList());

    if (columnMap.isEmpty) {
      errors.add('Could not identify required columns in CSV');
      return ParsedFundraiserData(
        name: '',
        sourceFileName: fileName,
        sourceType: 'csv',
        customers: [],
        warnings: warnings,
        errors: errors,
      );
    }

    // Parse data rows
    final rawOrders = <RawOrderData>[];

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((cell) => cell.toString().trim().isEmpty)) {
        continue;
      }

      final order = _parseRow(row, columnMap, warnings, i + 1);
      if (order != null) {
        rawOrders.add(order);
      }
    }

    // Allow browser event loop to process
    await Future.microtask(() {});

    // Consolidate customers
    final consolidator = CustomerConsolidator();
    final customers = consolidator.consolidate(rawOrders);

    // Add warnings for customers without contact info
    for (final customer in customers) {
      if (!customer.hasContactInfo) {
        warnings.add('Customer "${customer.displayName}" has no email or phone');
      }
    }

    return ParsedFundraiserData(
      name: '', // Leave blank for CSV - user should provide name
      sourceFileName: fileName,
      sourceType: 'csv',
      customers: customers,
      warnings: warnings,
      errors: errors,
    );
  }

  Map<String, int> _mapColumns(List<String> headers) {
    final map = <String, int>{};
    final normalizedHeaders =
        headers.map((h) => h.toLowerCase().trim()).toList();

    // Name column variations
    final nameVariations = [
      'name',
      'customer name',
      'full name',
      'customer',
      'buyer',
      'supporter',
      'first name',
      'last name',
    ];
    for (var i = 0; i < normalizedHeaders.length; i++) {
      for (final variation in nameVariations) {
        if (normalizedHeaders[i].contains(variation)) {
          map['name'] = i;
          break;
        }
      }
      if (map.containsKey('name')) break;
    }

    // First/Last name columns
    for (var i = 0; i < normalizedHeaders.length; i++) {
      if (normalizedHeaders[i].contains('first') &&
          normalizedHeaders[i].contains('name')) {
        map['firstName'] = i;
      }
      if (normalizedHeaders[i].contains('last') &&
          normalizedHeaders[i].contains('name')) {
        map['lastName'] = i;
      }
    }

    // Email column
    for (var i = 0; i < normalizedHeaders.length; i++) {
      if (normalizedHeaders[i].contains('email')) {
        map['email'] = i;
        break;
      }
    }

    // Phone column
    final phoneVariations = ['phone', 'telephone', 'mobile', 'cell'];
    for (var i = 0; i < normalizedHeaders.length; i++) {
      for (final variation in phoneVariations) {
        if (normalizedHeaders[i].contains(variation)) {
          map['phone'] = i;
          break;
        }
      }
      if (map.containsKey('phone')) break;
    }

    // Order ID column
    final orderIdVariations = ['order id', 'order #', 'order number', 'orderid'];
    for (var i = 0; i < normalizedHeaders.length; i++) {
      for (final variation in orderIdVariations) {
        if (normalizedHeaders[i].contains(variation)) {
          map['orderId'] = i;
          break;
        }
      }
      if (map.containsKey('orderId')) break;
    }

    // Date column
    final dateVariations = ['date', 'order date', 'created'];
    for (var i = 0; i < normalizedHeaders.length; i++) {
      for (final variation in dateVariations) {
        if (normalizedHeaders[i].contains(variation)) {
          map['date'] = i;
          break;
        }
      }
      if (map.containsKey('date')) break;
    }

    // Product/Item column
    final productVariations = ['product', 'item', 'description', 'items'];
    for (var i = 0; i < normalizedHeaders.length; i++) {
      for (final variation in productVariations) {
        if (normalizedHeaders[i].contains(variation)) {
          map['product'] = i;
          break;
        }
      }
      if (map.containsKey('product')) break;
    }

    // Quantity column
    final qtyVariations = ['quantity', 'qty', 'count', 'amount'];
    for (var i = 0; i < normalizedHeaders.length; i++) {
      for (final variation in qtyVariations) {
        if (normalizedHeaders[i] == variation ||
            normalizedHeaders[i].startsWith('$variation ')) {
          map['quantity'] = i;
          break;
        }
      }
      if (map.containsKey('quantity')) break;
    }

    // Price column
    final priceVariations = ['price', 'total', 'amount', 'cost'];
    for (var i = 0; i < normalizedHeaders.length; i++) {
      for (final variation in priceVariations) {
        if (normalizedHeaders[i].contains(variation) &&
            !map.containsKey('quantity')) {
          map['price'] = i;
          break;
        }
      }
      if (map.containsKey('price')) break;
    }

    // Payment status column
    final statusVariations = ['status', 'payment', 'paid'];
    for (var i = 0; i < normalizedHeaders.length; i++) {
      for (final variation in statusVariations) {
        if (normalizedHeaders[i].contains(variation)) {
          map['status'] = i;
          break;
        }
      }
      if (map.containsKey('status')) break;
    }

    return map;
  }

  RawOrderData? _parseRow(
    List<dynamic> row,
    Map<String, int> columnMap,
    List<String> warnings,
    int rowNumber,
  ) {
    String? getValue(String key) {
      final index = columnMap[key];
      if (index == null || index >= row.length) return null;
      final value = row[index].toString().trim();
      return value.isEmpty ? null : value;
    }

    // Get name (combine first/last if separate columns)
    String? name = getValue('name');
    if (name == null) {
      final firstName = getValue('firstName');
      final lastName = getValue('lastName');
      if (firstName != null || lastName != null) {
        name = [firstName, lastName].whereType<String>().join(' ').trim();
      }
    }

    if (name == null || name.isEmpty) {
      warnings.add('Row $rowNumber: Missing customer name, skipping');
      return null;
    }

    // Parse items if product column exists
    final items = <ParsedOrderItemData>[];
    final product = getValue('product');
    if (product != null) {
      final quantity = int.tryParse(getValue('quantity') ?? '1') ?? 1;
      final priceStr = getValue('price')?.replaceAll(RegExp(r'[^\d.]'), '');
      final price = priceStr != null
          ? (double.tryParse(priceStr) ?? 0) * 100
          : null;

      items.add(ParsedOrderItemData(
        productName: product,
        quantity: quantity,
        totalPriceCents: price?.round(),
      ));
    }

    return RawOrderData(
      name: name,
      email: getValue('email'),
      phone: getValue('phone'),
      orderId: getValue('orderId'),
      orderDate: getValue('date'),
      paymentStatus: getValue('status'),
      items: items,
    );
  }
}
