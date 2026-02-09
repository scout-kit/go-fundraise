/// Little Caesars Fundraiser PDF Parser
///
/// This parser is specifically designed for Little Caesars Group Delivery PDFs
/// and is completely isolated from other parsers (JD Sweid, CSV).
///
/// ## PDF Format Expected:
/// - Contains "Group Delivery" header on each order page
/// - Order header format: "Name (Order #XXXXX, Seller Name: YYY)"
/// - Phone format: "Phone #: XXX-XXX-XXXX"
/// - Products listed with SKU in parentheses: "Product Name (SKU)"
/// - Price lines: "Price: $XX.XX  QTY  $XX.XX  $XX.XX  YES/NO"
/// - Pages separated by form feed characters (\f)
///
/// ## Isolation Guarantees:
/// - All LC-specific regex patterns are defined within this class
/// - No LC-specific code in shared utilities (ParserUtils, CustomerConsolidator)
/// - Format validation ("Group Delivery" check) is LC-specific
/// - Changes to this parser will not affect JD Sweid or CSV parsers
///
/// ## Shared Utilities Used (generic, not LC-specific):
/// - ParserUtils.normalizePhone() - standard phone normalization
/// - ParserUtils.extractCampaignInfo() - generic delivery info extraction
/// - ParserUtils.generateDefaultName() - generic name generation
/// - CustomerConsolidator - generic customer deduplication by email/phone/name
library;

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:go_fundraise/core/models/parsed_data.dart';
import 'package:go_fundraise/features/import/parsers/customer_consolidator.dart';
import 'package:go_fundraise/features/import/parsers/parser_utils.dart';

/// Parser for Little Caesars fundraiser PDF format.
///
/// Only the [parseBytes] method is public; all parsing logic is private.
class LittleCaesarsParser {
  /// Parse PDF from bytes (works on all platforms including web)
  Future<ParsedFundraiserData> parseBytes(Uint8List bytes, String fileName) async {
    final document = PdfDocument(inputBytes: bytes);

    final warnings = <String>[];
    final errors = <String>[];

    // Extract all text from the document
    final textExtractor = PdfTextExtractor(document);
    final fullText = textExtractor.extractText();
    document.dispose();

    // Allow browser event loop to process
    await Future.microtask(() {});

    // Validate format - check for Safari issue on web
    if (!fullText.contains('Group Delivery')) {
      if (kIsWeb && fullText.trim().isEmpty) {
        throw FormatException(
          'PDF text extraction failed. This is a known issue with Safari. '
          'Please try using Chrome or Firefox instead.'
        );
      }
      throw FormatException(
        'This file does not appear to be a Little Caesars PDF. '
        'Please select the correct import type.'
      );
    }

    // Parse campaign header info
    final campaignInfo = ParserUtils.extractCampaignInfo(fullText);

    // Allow browser event loop to process
    await Future.microtask(() {});

    // Extract order blocks
    final rawOrders = _extractLittleCaesarsBlocks(fullText, warnings);

    // Allow browser event loop to process
    await Future.microtask(() {});

    // Consolidate customers (merge duplicates by name - LC sellers don't have contact info)
    final consolidator = CustomerConsolidator(nameOnlyMatchIsOk: true);
    final customers = consolidator.consolidate(rawOrders);

    // For LC imports, check that orders have buyer phone (not customer contact info)
    // Customers (sellers) won't have phone numbers - only their orders will
    for (final customer in customers) {
      for (final order in customer.orders) {
        if (order.buyerPhone == null || order.buyerPhone!.isEmpty) {
          final orderId = order.originalOrderId ?? 'unknown';
          warnings.add(
              'Order #$orderId for "${customer.displayName}" is missing buyer phone');
        }
      }
    }

    // Generate default name based on parser type
    final defaultName = ParserUtils.generateDefaultName('Little Caesars');

    return ParsedFundraiserData(
      name: defaultName,
      deliveryDate: campaignInfo['deliveryDate'],
      deliveryLocation: campaignInfo['deliveryLocation'],
      deliveryTime: campaignInfo['deliveryTime'],
      sourceFileName: fileName,
      sourceType: 'pdf',
      customers: customers,
      warnings: warnings,
      errors: errors,
    );
  }

  /// Extract order blocks from Little Caesars PDF format
  List<RawOrderData> _extractLittleCaesarsBlocks(
      String text, List<String> warnings) {
    final orders = <RawOrderData>[];

    // First try: Split by form feed character (\f)
    var blocks = text.split(RegExp(r'\f'));

    // Filter to only blocks containing "Group Delivery"
    blocks = blocks.where((b) => b.contains('Group Delivery')).toList();

    // Fallback: If form feed didn't produce multiple blocks, split by "Group Delivery"
    // This handles cases where PDF text extraction doesn't preserve form feeds
    if (blocks.length <= 1 && text.contains('Group Delivery')) {
      // Split on "Group Delivery" at start of line using lookahead with multiLine mode
      // This keeps the delimiter ("Group Delivery") at the start of each resulting block
      blocks = text
          .split(RegExp(r'(?=^Group Delivery$)', multiLine: true))
          .where((b) => b.trim().isNotEmpty)
          .toList();
    }

    for (final block in blocks) {
      if (!block.contains('Group Delivery')) continue;

      final order = _parseLittleCaesarsBlock(block, warnings);
      if (order != null) {
        orders.add(order);
      }
    }

    if (orders.isEmpty) {
      warnings.add('Could not identify Little Caesars order blocks in PDF');
    }

    return orders;
  }

  /// Parse a single Little Caesars order block
  ///
  /// The PDF format has:
  /// - "buyer name (Order #XXXXX, Seller Name: seller)" in the header
  /// - Phone # belongs to the buyer
  ///
  /// We swap these so:
  /// - Seller name becomes the customer (who picks up)
  /// - Buyer name/phone are stored on the order (for reference)
  RawOrderData? _parseLittleCaesarsBlock(String blockText, List<String> warnings) {
    final lines = blockText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    if (lines.isEmpty) return null;

    String? sellerName;  // Will become the customer name
    String? buyerName;   // Will be stored on the order
    String? orderId;
    String? phone;       // This is the buyer's phone
    String? paymentStatus;
    final items = <ParsedOrderItemData>[];

    // Pattern for header line: "Name (Order #XXXXX, Seller Name: YYY)"
    final headerPattern = RegExp(
      r'^(.+?)\s*\(Order\s*#(\d+),\s*Seller\s*Name:\s*(.+?)\)$',
      caseSensitive: false,
    );

    // Pattern for phone: "Phone #: XXX-XXX-XXXX"
    final phonePattern = RegExp(r'Phone\s*#:\s*([\d-]+)', caseSensitive: false);

    // Pattern for product name with SKU: "Product Name (SKU)"
    final productPattern = RegExp(r'^(.+?)\s*\(([A-Z]+)\)$');

    // Pattern for price line: "Price: $XX.XX  QTY  $XX.XX  $XX.XX  YES/NO"
    // Note: The values may be spread across multiple lines in the extracted text
    final priceLinePattern = RegExp(
      r'Price:\s*\$([\d.]+)',
      caseSensitive: false,
    );

    // Track current product being parsed
    String? currentProductName;
    String? currentSku;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Skip header lines
      if (line == 'Group Delivery' ||
          line == 'PRODUCT NAME' ||
          line.contains('QTY') && line.contains('PRICE') && line.contains('SUBTOTAL')) {
        continue;
      }

      // Check for header line with name, order ID, and seller
      // Format: "buyer name (Order #XXXXX, Seller Name: seller)"
      final headerMatch = headerPattern.firstMatch(line);
      if (headerMatch != null) {
        buyerName = headerMatch.group(1)?.trim();   // Buyer (supporter)
        orderId = headerMatch.group(2);
        sellerName = headerMatch.group(3)?.trim();  // Seller (scout/parent who picks up)
        continue;
      }

      // Check for phone number
      final phoneMatch = phonePattern.firstMatch(line);
      if (phoneMatch != null) {
        phone = ParserUtils.normalizePhone(phoneMatch.group(1) ?? '');
        continue;
      }

      // Check for payment status (YES/NO) - appears at end of lines
      if (line == 'YES' || line == 'NO') {
        paymentStatus = line == 'YES' ? 'paid' : 'unpaid';
        continue;
      }

      // Check for product name with SKU
      final productMatch = productPattern.firstMatch(line);
      if (productMatch != null) {
        // If we have a pending product, we need to find its price
        currentProductName = productMatch.group(1)?.trim();
        currentSku = productMatch.group(2);
        continue;
      }

      // Handle multi-line product names (e.g., "NEW! Slices-N-Stix Kit" on one line, "(SS)" on next)
      if (line.startsWith('(') && line.endsWith(')') && currentProductName == null) {
        // This is a standalone SKU, look back for the product name
        currentSku = line.substring(1, line.length - 1);
        // Find previous non-empty line that looks like a product name
        for (var j = i - 1; j >= 0; j--) {
          final prevLine = lines[j];
          if (!prevLine.startsWith('Price:') &&
              !prevLine.contains('Phone #:') &&
              !prevLine.contains('QTY') &&
              prevLine != 'YES' &&
              prevLine != 'NO' &&
              !headerPattern.hasMatch(prevLine)) {
            currentProductName = prevLine;
            break;
          }
        }
        continue;
      }

      // Check for price line and create item
      final priceMatch = priceLinePattern.firstMatch(line);
      if (priceMatch != null && currentProductName != null) {
        final unitPrice = double.tryParse(priceMatch.group(1) ?? '0') ?? 0;

        // Look for quantity and totals in the rest of the line or following lines
        final restOfLine = line.substring(priceMatch.end);
        final numbersOnSameLine = RegExp(r'(\d+)\s+\$([\d.]+)\s+\$([\d.]+)')
            .firstMatch(restOfLine);

        int quantity = 1;
        double totalPrice = unitPrice;

        if (numbersOnSameLine != null) {
          quantity = int.tryParse(numbersOnSameLine.group(1) ?? '1') ?? 1;
          totalPrice = double.tryParse(numbersOnSameLine.group(3) ?? '0') ?? unitPrice * quantity;
        } else {
          // PDF text extraction often splits columns into separate lines
          // Look for quantity in following lines (it's usually a standalone number)
          for (var j = i + 1; j < lines.length && j < i + 5; j++) {
            final nextLine = lines[j];
            // Skip empty-ish lines and YES/NO
            if (nextLine == 'YES' || nextLine == 'NO') break;
            // Look for standalone quantity (1-3 digit number)
            final qtyMatch = RegExp(r'^(\d{1,3})$').firstMatch(nextLine);
            if (qtyMatch != null) {
              quantity = int.parse(qtyMatch.group(1)!);
              // Now look for subtotal (next price after quantity)
              for (var k = j + 1; k < lines.length && k < j + 3; k++) {
                final subtotalMatch = RegExp(r'^\$?([\d,.]+)$').firstMatch(lines[k]);
                if (subtotalMatch != null) {
                  // Skip unit price, look for subtotal
                  for (var m = k + 1; m < lines.length && m < k + 2; m++) {
                    final actualSubtotal = RegExp(r'^\$?([\d,.]+)$').firstMatch(lines[m]);
                    if (actualSubtotal != null) {
                      totalPrice = double.tryParse(actualSubtotal.group(1)?.replaceAll(',', '') ?? '0') ?? unitPrice * quantity;
                      break;
                    }
                  }
                  break;
                }
              }
              break;
            }
          }
          if (quantity == 1) {
            totalPrice = unitPrice;
          } else if (totalPrice == unitPrice) {
            totalPrice = unitPrice * quantity;
          }
        }

        items.add(ParsedOrderItemData(
          productName: _normalizeProductName(currentProductName, currentSku),
          sku: currentSku,
          quantity: quantity,
          unitPriceCents: (unitPrice * 100).round(),
          totalPriceCents: (totalPrice * 100).round(),
        ));

        currentProductName = null;
        currentSku = null;
        continue;
      }
    }

    // Use seller as customer name (they pick up the order)
    // Fall back to buyer name if no seller (shouldn't happen in valid data)
    final customerName = sellerName ?? buyerName;
    if (customerName == null) {
      warnings.add('Skipped Little Caesars block with no identifiable name');
      return null;
    }

    return RawOrderData(
      name: customerName,          // Seller is the customer who picks up
      buyerName: buyerName,        // Buyer is stored on the order
      buyerPhone: phone,           // Phone belongs to buyer, not customer
      phone: null,                 // Customer (seller) phone not in PDF
      orderId: orderId,
      paymentStatus: paymentStatus,
      items: items,
      rawText: blockText,
    );
  }

  /// Normalize product names that may have been split across lines
  String _normalizeProductName(String name, String? sku) {
    // Remove ® symbols for easier matching
    final cleanName = name.replaceAll('®', '').trim();
    final lowerName = cleanName.toLowerCase();

    // Fix known Little Caesars products that get split across lines
    // PDF has "Crazy Bread® Kit" on one line and "with Crazy Sauce® (CB)" on next
    // Parser only captures "with Crazy Sauce" - fix to full product name
    if (lowerName.startsWith('with crazy sauce') ||
        (sku == 'CB' && !lowerName.contains('crazy bread'))) {
      return 'Crazy Bread Kit with Crazy Sauce';
    }

    // "with Marinara" variations for Italian Cheese Bread
    if (lowerName.startsWith('with marinara') ||
        (sku == 'ICB' && !lowerName.contains('cheese bread'))) {
      return 'Italian Cheese Bread Kit with Marinara';
    }

    // Clean up ® symbols from the name for cleaner display
    return cleanName;
  }
}
