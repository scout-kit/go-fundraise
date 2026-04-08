/// Square Online CSV Order Export Parser
///
/// This parser is specifically designed for Square Online order CSV exports
/// and is completely isolated from other parsers (JD Sweid, Little Caesars, CSV).
///
/// ## CSV Format Expected:
/// - 32 fixed columns with known header names
/// - One row per line item (multiple rows per order)
/// - Order ID format: "Square Online XXXXXXXXXX"
/// - Customer info in Recipient Name/Email/Phone columns
/// - Item Variation contains participant names (not product variants)
/// - Prices in dollars (e.g., 4.0), dates in YYYY/MM/DD format
///
/// ## Isolation Guarantees:
/// - All Square-specific parsing logic is defined within this class
/// - No Square-specific code in shared utilities
/// - Format validation (header check) is Square-specific
/// - Changes to this parser will not affect other parsers
///
/// ## Shared Utilities Used (generic, not Square-specific):
/// - ParserUtils.normalizePhone() - standard phone normalization
/// - ParserUtils.generateDefaultName() - generic name generation
/// - CustomerConsolidator - generic customer deduplication by email/phone/name
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:go_fundraise/core/models/parsed_data.dart';
import 'package:go_fundraise/features/import/parsers/customer_consolidator.dart';
import 'package:go_fundraise/features/import/parsers/parser_utils.dart';

/// Parser for Square Online order CSV exports.
///
/// Only the [parseBytes] method is public; all parsing logic is private.
class SquareParser {
  // Required header columns for format validation
  static const _requiredHeaders = [
    'Order',
    'Recipient Name',
    'Item Name',
    'Item Quantity',
  ];

  /// Parse CSV from bytes (works on all platforms including web)
  Future<ParsedFundraiserData> parseBytes(
      Uint8List bytes, String fileName) async {
    final content = utf8.decode(bytes);
    final warnings = <String>[];
    final errors = <String>[];

    // Allow browser event loop to process
    await Future.microtask(() {});

    // Parse CSV
    final rows = const CsvToListConverter().convert(content, eol: '\n');

    if (rows.isEmpty) {
      throw const FormatException('CSV file is empty');
    }

    // Map and validate header columns
    final headers = rows.first.map((e) => e.toString().trim()).toList();
    final columnMap = _mapColumns(headers);

    if (columnMap == null) {
      throw const FormatException(
        'This file does not appear to be a Square Online order export. '
        'Please select the correct import type.',
      );
    }

    // Allow browser event loop to process
    await Future.microtask(() {});

    // Group data rows by Order ID to build multi-item orders
    final orderGroups = _groupRowsByOrder(rows, columnMap, warnings);

    // Allow browser event loop to process
    await Future.microtask(() {});

    // Convert order groups to RawOrderData
    final rawOrders = <RawOrderData>[];
    for (final entry in orderGroups.entries) {
      final order = _buildOrder(entry.key, entry.value, columnMap, warnings);
      if (order != null) {
        rawOrders.add(order);
      }
    }

    // Allow browser event loop to process
    await Future.microtask(() {});

    // Consolidate customers (email-first matching)
    final consolidator = CustomerConsolidator();
    final customers = consolidator.consolidate(rawOrders);

    // Generate default name
    final defaultName = ParserUtils.generateDefaultName('Square');

    return ParsedFundraiserData(
      name: defaultName,
      sourceFileName: fileName,
      sourceType: 'csv',
      customers: customers,
      warnings: warnings,
      errors: errors,
    );
  }

  /// Map header names to column indices. Returns null if required headers are missing.
  Map<String, int>? _mapColumns(List<String> headers) {
    final map = <String, int>{};

    for (var i = 0; i < headers.length; i++) {
      final header = headers[i];
      switch (header) {
        case 'Order':
          map['order'] = i;
        case 'Order Name':
          map['orderName'] = i;
        case 'Order Date':
          map['orderDate'] = i;
        case 'Order Total':
          map['orderTotal'] = i;
        case 'Recipient Name':
          map['recipientName'] = i;
        case 'Recipient Email':
          map['recipientEmail'] = i;
        case 'Recipient Phone':
          map['recipientPhone'] = i;
        case 'Item Quantity':
          map['itemQuantity'] = i;
        case 'Item Name':
          map['itemName'] = i;
        case 'Item Variation':
          map['itemVariation'] = i;
        case 'Item Price':
          map['itemPrice'] = i;
        case 'Item Total Price':
          map['itemTotalPrice'] = i;
      }
    }

    // Validate all required headers are present
    final requiredKeys = ['order', 'recipientName', 'itemName', 'itemQuantity'];
    for (final key in requiredKeys) {
      if (!map.containsKey(key)) return null;
    }

    return map;
  }

  /// Group data rows by Order ID, preserving insertion order.
  Map<String, List<List<dynamic>>> _groupRowsByOrder(
    List<List<dynamic>> rows,
    Map<String, int> columnMap,
    List<String> warnings,
  ) {
    final groups = <String, List<List<dynamic>>>{};
    final orderCol = columnMap['order']!;

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.every((cell) => cell.toString().trim().isEmpty)) {
        continue;
      }

      if (orderCol >= row.length) {
        warnings.add('Row ${i + 1}: Missing order ID, skipping');
        continue;
      }

      final orderId = row[orderCol].toString().trim();
      if (orderId.isEmpty) continue;

      groups.putIfAbsent(orderId, () => []).add(row);
    }

    return groups;
  }

  /// Build a RawOrderData from a group of rows sharing the same Order ID.
  RawOrderData? _buildOrder(
    String rawOrderId,
    List<List<dynamic>> rows,
    Map<String, int> columnMap,
    List<String> warnings,
  ) {
    if (rows.isEmpty) return null;

    // Use the first row for order-level fields (they're the same across rows)
    final firstRow = rows.first;

    String? _getValue(List<dynamic> row, String key) {
      final index = columnMap[key];
      if (index == null || index >= row.length) return null;
      final value = row[index].toString().trim();
      return value.isEmpty || value == '""' ? null : value;
    }

    final name = _getValue(firstRow, 'recipientName');
    if (name == null) {
      warnings.add('Order "$rawOrderId": Missing recipient name, skipping');
      return null;
    }

    // Extract numeric order ID from "Square Online XXXXXXXXXX"
    final orderId = _extractOrderId(rawOrderId);

    // Normalize phone from international format (+1XXXXXXXXXX)
    final rawPhone = _getValue(firstRow, 'recipientPhone');
    final phone = rawPhone != null ? ParserUtils.normalizePhone(rawPhone) : null;

    // Parse items from each row
    final items = <ParsedOrderItemData>[];
    for (final row in rows) {
      final item = _parseItem(row, columnMap);
      if (item != null) {
        items.add(item);
      }
    }

    if (items.isEmpty) {
      warnings.add('Order "$rawOrderId" for "$name" has no parseable items');
    }

    return RawOrderData(
      name: name,
      email: _getValue(firstRow, 'recipientEmail'),
      phone: phone,
      orderId: orderId,
      orderDate: _getValue(firstRow, 'orderDate'),
      items: items,
    );
  }

  /// Parse a single item row into a ParsedOrderItemData.
  ParsedOrderItemData? _parseItem(
    List<dynamic> row,
    Map<String, int> columnMap,
  ) {
    String? getValue(String key) {
      final index = columnMap[key];
      if (index == null || index >= row.length) return null;
      final value = row[index].toString().trim();
      return value.isEmpty || value == '""' ? null : value;
    }

    final itemName = getValue('itemName');
    if (itemName == null) return null;

    final variation = getValue('itemVariation');

    // Build product name: include variation if meaningful
    final productName = _buildProductName(itemName, variation);

    // Parse quantity
    final qtyStr = getValue('itemQuantity');
    final quantity = qtyStr != null ? (double.tryParse(qtyStr)?.toInt() ?? 1) : 1;

    // Parse prices (dollars to cents)
    final unitPriceStr = getValue('itemPrice');
    final unitPriceCents = unitPriceStr != null
        ? ((double.tryParse(unitPriceStr) ?? 0) * 100).round()
        : null;

    final totalPriceStr = getValue('itemTotalPrice');
    final totalPriceCents = totalPriceStr != null
        ? ((double.tryParse(totalPriceStr) ?? 0) * 100).round()
        : null;

    return ParsedOrderItemData(
      productName: productName,
      quantity: quantity,
      unitPriceCents: unitPriceCents,
      totalPriceCents: totalPriceCents,
    );
  }

  /// Build a display-friendly product name, appending variation if meaningful.
  String _buildProductName(String itemName, String? variation) {
    if (variation == null || variation.isEmpty) return itemName;

    // Skip generic variations that don't add useful info
    final lowerVariation = variation.toLowerCase();
    if (lowerVariation == 'regular' || lowerVariation == 'default') {
      return itemName;
    }

    return '$itemName ($variation)';
  }

  /// Extract numeric ID from "Square Online XXXXXXXXXX" format.
  String _extractOrderId(String rawId) {
    final match = RegExp(r'(\d+)').firstMatch(rawId);
    return match?.group(1) ?? rawId;
  }
}
