import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:go_fundraise/core/models/parsed_data.dart';
import 'package:go_fundraise/features/import/parsers/customer_consolidator.dart';
import 'package:go_fundraise/features/import/parsers/parser_utils.dart';

/// Parser for JD Sweid fundraiser PDF format
class JdSweidParser {
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
    if (!fullText.contains('SUPPORTER')) {
      if (kIsWeb && fullText.trim().isEmpty) {
        throw FormatException(
          'PDF text extraction failed. This is a known issue with Safari. '
          'Please try using Chrome or Firefox instead.'
        );
      }
      throw FormatException(
        'This file does not appear to be a JD Sweid PDF. '
        'Please select the correct import type.'
      );
    }

    // Parse campaign header info
    final campaignInfo = ParserUtils.extractCampaignInfo(fullText);

    // Allow browser event loop to process
    await Future.microtask(() {});

    // Extract supporter blocks
    final rawOrders = _extractSupporterBlocks(fullText, warnings);

    // Allow browser event loop to process
    await Future.microtask(() {});

    // Consolidate customers (merge duplicates by email/phone/name)
    final consolidator = CustomerConsolidator();
    final customers = consolidator.consolidate(rawOrders);

    // Add warnings for customers without contact info
    for (final customer in customers) {
      if (!customer.hasContactInfo) {
        warnings.add(
            'Customer "${customer.displayName}" has no email or phone');
      }
    }

    // Generate default name based on parser type
    final defaultName = ParserUtils.generateDefaultName('JD Sweid');

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

  List<RawOrderData> _extractSupporterBlocks(
      String text, List<String> warnings) {
    final orders = <RawOrderData>[];

    // The text to parse - we'll handle the summary section during line-by-line parsing
    // Note: "SUPPORTER ORDERS SUMMARY" at the top is just the document title, not the actual
    // summary section. The real summary (if any) comes at the end after all orders.
    var textToParse = text;

    // Try multiple splitting strategies for JD Sweid format
    List<String> blocks = [];

    // Strategy 1: Split on "SUPPORTER PRODUCTS ORDERED" with flexible whitespace
    blocks = textToParse.split(RegExp(r'SUPPORTER\s+PRODUCTS\s+ORDERED', caseSensitive: false));

    // Strategy 2: If that didn't work well, try splitting on "SUPPORTER" anywhere
    if (blocks.length <= 1) {
      blocks = textToParse.split(RegExp(r'SUPPORTER', caseSensitive: false));
    }

    // Strategy 3: Try form feed characters (page breaks)
    if (blocks.length <= 1) {
      blocks = textToParse.split(RegExp(r'\f'));
      // Keep all blocks, not just those with SUPPORTER
      blocks = blocks.where((b) => b.trim().isNotEmpty).toList();
      if (blocks.isEmpty) {
        blocks = [textToParse]; // Reset to full text
      }
    }

    // Skip the first block if we have multiple (it's usually header/preamble)
    final startIndex = blocks.length > 1 ? 1 : 0;

    for (var i = startIndex; i < blocks.length; i++) {
      final blockText = blocks[i];
      // Skip blocks that are too short to be valid
      if (blockText.trim().length < 10) continue;

      final order = _parseSupporterBlock(blockText, warnings);
      if (order != null) {
        orders.add(order);
      }
    }

    // If standard parsing failed, try line-by-line parsing
    if (orders.isEmpty) {
      final lineOrders = _parseLineByLine(textToParse, warnings);
      if (lineOrders.isNotEmpty) {
        return lineOrders;
      }
    }

    if (orders.isEmpty) {
      // Try alternative parsing - look for order blocks
      final altOrders = _parseAlternativeFormat(textToParse, warnings);
      if (altOrders.isNotEmpty) {
        return altOrders;
      }

      warnings.add('Could not identify supporter blocks in PDF');
    }

    return orders;
  }

  /// Parse by scanning line by line for customer patterns
  /// Handles Syncfusion PDF extraction where columns are on separate lines
  List<RawOrderData> _parseLineByLine(String text, List<String> warnings) {
    final orders = <RawOrderData>[];
    final lines = text.split('\n');

    String? currentName;
    String? currentEmail;
    String? currentPhone;
    String? currentOrderId;
    String? currentPaymentStatus;
    final currentItems = <ParsedOrderItemData>[];
    final currentRawLines = <String>[];

    // Track pending product (name+SKU found, waiting for quantity)
    String? pendingProductName;
    String? pendingProductSku;

    // Flag to stop parsing when we hit summary section
    bool inSummarySection = false;

    void saveCurrentOrder() {
      // Save any pending product with qty=1 before closing the order
      if (pendingProductName != null) {
        currentItems.add(ParsedOrderItemData(
          productName: pendingProductName!,
          sku: pendingProductSku,
          quantity: 1,
        ));
        pendingProductName = null;
        pendingProductSku = null;
      }

      if (currentName != null && currentName!.isNotEmpty) {
        orders.add(RawOrderData(
          name: currentName!,
          email: currentEmail,
          phone: currentPhone,
          orderId: currentOrderId,
          paymentStatus: currentPaymentStatus,
          items: List.from(currentItems),
          rawText: currentRawLines.join('\n'),
        ));
      }
      currentName = null;
      currentEmail = null;
      currentPhone = null;
      currentOrderId = null;
      currentPaymentStatus = null;
      currentItems.clear();
      currentRawLines.clear();
    }

    // Pattern for box count / payment line - indicates end of a supporter block
    final boxPattern = RegExp(r'#\s*OF\s*BOXES', caseSensitive: false);
    final paidPattern = RegExp(r'\b(PAID|UNPAID)\b', caseSensitive: false);
    // Pattern for product name with SKU (but no quantity on same line)
    // Use [^\(\d] to match any character except ( and digits, allowing Unicode chars like ™
    final productSkuOnlyPattern = RegExp(r'^([A-Za-z].+?)\s*\((\d{4,})\)\s*$');
    // Pattern for standalone quantity (small number by itself)
    final standaloneQtyPattern = RegExp(r'^(\d{1,2})$');

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final upper = line.toUpperCase();

      // Detect summary sections at the end of the document
      // These re-list all products with aggregated totals
      if (upper.contains('PRODUCTS ORDERED SUMMARY') ||
          upper.contains('CAMPAIGN TOTAL') ||
          upper.contains('TOTAL # OF ORDERS') ||
          upper.contains('FUNDRAISING CAMPAIGN SUMMARY')) {
        if (_debug) {
          print('Hit end summary section, stopping parsing: "$line"');
        }
        saveCurrentOrder();
        inSummarySection = true;
        break;
      }

      // Skip if we're in summary section
      if (inSummarySection) continue;

      // Skip the document header lines (not the summary)
      if (upper.contains('SUPPORTER ORDERS SUMMARY') ||
          (upper.contains('ORGANIZER') && upper.contains('TOTAL #'))) {
        continue;
      }

      currentRawLines.add(line);

      // Check if this line indicates a new supporter block
      if (line.contains('SUPPORTER') && currentName != null) {
        saveCurrentOrder();
        continue;
      }

      // Skip header lines
      if (line.contains('SUPPORTER') ||
          (line.contains('QTY') && line.contains('PRICE')) ||
          line.contains('PRODUCTS ORDERED')) {
        continue;
      }

      // Check for box count line - signals end of order
      if (boxPattern.hasMatch(line)) {
        final paidMatch = paidPattern.firstMatch(line);
        if (paidMatch != null) {
          currentPaymentStatus = paidMatch.group(1)?.toLowerCase();
        }
        saveCurrentOrder();
        continue;
      }

      // Check if we have a pending product and this line is a standalone quantity
      if (pendingProductName != null) {
        final qtyMatch = standaloneQtyPattern.firstMatch(line);
        if (qtyMatch != null) {
          final qty = int.tryParse(qtyMatch.group(1) ?? '1') ?? 1;
          if (_debug) {
            print('Found quantity $qty for pending product: "$pendingProductName"');
          }
          currentItems.add(ParsedOrderItemData(
            productName: pendingProductName!,
            sku: pendingProductSku,
            quantity: qty,
          ));
          pendingProductName = null;
          pendingProductSku = null;
          continue;
        }

        // Try to extract quantity from a line with numbers (QTY PRICE SUBTOTAL format)
        // Look for all numbers and use first small integer as quantity
        final allNumbers = RegExp(r'[\d.]+').allMatches(line).map((m) => m.group(0)!).toList();
        if (allNumbers.isNotEmpty) {
          int? extractedQty;
          for (final num in allNumbers) {
            final intVal = int.tryParse(num);
            // First small integer (1-99, no decimal point) is likely quantity
            if (intVal != null && intVal >= 1 && intVal <= 99 && !num.contains('.')) {
              extractedQty = intVal;
              break;
            }
          }
          if (extractedQty != null) {
            if (_debug) {
              print('Extracted quantity $extractedQty from numbers $allNumbers for pending product: "$pendingProductName"');
            }
            currentItems.add(ParsedOrderItemData(
              productName: pendingProductName!,
              sku: pendingProductSku,
              quantity: extractedQty,
            ));
            pendingProductName = null;
            pendingProductSku = null;
            continue;
          }
        }

        // If the next line is a price (starts with $ or is a decimal), use qty=1
        if (line.startsWith('\$') || RegExp(r'^\d+\.\d{2}$').hasMatch(line)) {
          currentItems.add(ParsedOrderItemData(
            productName: pendingProductName!,
            sku: pendingProductSku,
            quantity: 1,
          ));
          pendingProductName = null;
          pendingProductSku = null;
          // Don't continue - let the line be processed further if needed
        }
      }

      // Check for product line with SKU only (Syncfusion extraction format)
      final productSkuMatch = productSkuOnlyPattern.firstMatch(line);
      if (productSkuMatch != null) {
        // Save any previous pending product first
        if (pendingProductName != null) {
          currentItems.add(ParsedOrderItemData(
            productName: pendingProductName!,
            sku: pendingProductSku,
            quantity: 1,
          ));
        }
        pendingProductName = productSkuMatch.group(1)?.trim();
        pendingProductSku = productSkuMatch.group(2);
        if (_debug) {
          print('Found product (waiting for qty): "$pendingProductName" SKU=$pendingProductSku');
        }
        continue;
      }

      // Check for product line - try multiple patterns (for complete lines)
      final productItem = _tryParseProductLine(line, warnings);
      if (productItem != null) {
        // Clear any pending since we got a complete product
        pendingProductName = null;
        pendingProductSku = null;
        currentItems.add(productItem);
        continue;
      }

      // Check for email
      final emailMatch = RegExp(r'[\w.+-]+@[\w.-]+\.\w+').firstMatch(line);
      if (emailMatch != null && currentEmail == null) {
        currentEmail = emailMatch.group(0);
        continue;
      }

      // Check for phone (10+ digits)
      final phoneDigits = line.replaceAll(RegExp(r'\D'), '');
      if (phoneDigits.length >= 10 && phoneDigits.length <= 11 && currentPhone == null) {
        // Make sure it's not a price or other number
        if (!line.contains('\$') && !line.contains('Order')) {
          currentPhone = line;
          continue;
        }
      }

      // Check for payment status standalone
      final standalonePaid = paidPattern.firstMatch(line);
      if (standalonePaid != null && line.length < 10) {
        currentPaymentStatus = standalonePaid.group(1)?.toLowerCase();
        continue;
      }

      // Check if this could be a name (first name-like line we encounter)
      if (currentName == null && _looksLikeNameLoose(line)) {
        currentName = line;
        continue;
      }
    }

    // Save any remaining order
    saveCurrentOrder();

    return orders;
  }

  // Debug flag - set to true to enable debug warnings
  static const _debug = false;

  /// Try to parse a product line using multiple patterns
  ParsedOrderItemData? _tryParseProductLine(String line, [List<String>? debugWarnings]) {
    // Skip obvious non-product lines
    if (line.length < 3) return null;
    final upper = line.toUpperCase();
    if (upper.contains('SUPPORTER')) return null;
    if (upper.contains('ORDER')) return null;
    if (upper.contains('SUMMARY')) return null;
    if (upper.contains('TOTAL') && !upper.contains('SUBTOTAL')) return null;
    if (upper.contains('CAMPAIGN')) return null;
    if (upper.contains('DELIVERY')) return null;
    if (upper.contains('BOXES')) return null; // "# OF BOXES" line
    if (upper.contains('PAYABLE')) return null;
    if (upper.contains('PAID') || upper.contains('UNPAID')) return null;
    if (upper.contains('QTY') && upper.contains('PRICE')) return null; // Header line
    if (line.startsWith('#')) return null; // Lines starting with # are typically metadata
    if (upper.contains('DATE:')) return null; // Date metadata lines
    if (upper.contains('START DATE') || upper.contains('END DATE')) return null;

    // Debug: Log lines that contain a SKU pattern (potential product lines)
    if (_debug && RegExp(r'\(\d{4,}\)').hasMatch(line)) {
      print('Processing potential product line: "$line"');
    }

    // Pattern 1: "ProductName (SKU) QTY $PRICE $SUBTOTAL"
    // Use [^\(\d] to match product name chars (anything except ( and digits at start)
    final pattern1 = RegExp(
      r"([A-Za-z][A-Za-z0-9\s\-&'™®©]+?)\s*\((\d+)\)\s+(\d+)\s+\$?([\d.]+)\s+\$?([\d.]+)",
    );
    var match = pattern1.firstMatch(line);
    if (match != null) {
      final qty = int.tryParse(match.group(3) ?? '1') ?? 1;
      if (_debug) {
        print('Pattern1 matched: "${match.group(1)?.trim()}" qty=$qty');
        debugWarnings?.add('Pattern1 matched: "${match.group(1)?.trim()}" qty=$qty');
      }
      return ParsedOrderItemData(
        productName: match.group(1)?.trim() ?? '',
        sku: match.group(2),
        quantity: qty,
        unitPriceCents: ((double.tryParse(match.group(4) ?? '0') ?? 0) * 100).round(),
        totalPriceCents: ((double.tryParse(match.group(5) ?? '0') ?? 0) * 100).round(),
      );
    }

    // Pattern 2: "ProductName (SKU) QTY PRICE SUBTOTAL" (no $ signs)
    final pattern2 = RegExp(
      r"([A-Za-z][A-Za-z0-9\s\-&'™®©]+?)\s*\((\d+)\)\s+(\d+)\s+([\d.]+)\s+([\d.]+)",
    );
    match = pattern2.firstMatch(line);
    if (match != null) {
      final qty = int.tryParse(match.group(3) ?? '1') ?? 1;
      if (_debug) {
        print('Pattern2 matched: "${match.group(1)?.trim()}" qty=$qty');
        debugWarnings?.add('Pattern2 matched: "${match.group(1)?.trim()}" qty=$qty');
      }
      return ParsedOrderItemData(
        productName: match.group(1)?.trim() ?? '',
        sku: match.group(2),
        quantity: qty,
        unitPriceCents: ((double.tryParse(match.group(4) ?? '0') ?? 0) * 100).round(),
        totalPriceCents: ((double.tryParse(match.group(5) ?? '0') ?? 0) * 100).round(),
      );
    }

    // Pattern 3: "ProductName    QTY    $PRICE    $SUBTOTAL" (no SKU, tab/space separated)
    // Allow single space or tab separators too
    final pattern3 = RegExp(
      r"^([A-Za-z][A-Za-z0-9\s\-&'™®©]+?)\s{2,}(\d+)\s{2,}\$?([\d.]+)\s{2,}\$?([\d.]+)",
    );
    match = pattern3.firstMatch(line);
    if (match != null) {
      return ParsedOrderItemData(
        productName: match.group(1)?.trim() ?? '',
        quantity: int.tryParse(match.group(2) ?? '1') ?? 1,
        unitPriceCents: ((double.tryParse(match.group(3) ?? '0') ?? 0) * 100).round(),
        totalPriceCents: ((double.tryParse(match.group(4) ?? '0') ?? 0) * 100).round(),
      );
    }

    // Pattern 3b: Tab-separated columns (common in PDF extraction)
    final pattern3b = RegExp(
      r"^([A-Za-z][A-Za-z0-9\s\-&'™®©]+?)\t+(\d+)\t+\$?([\d.]+)\t+\$?([\d.]+)",
    );
    match = pattern3b.firstMatch(line);
    if (match != null) {
      return ParsedOrderItemData(
        productName: match.group(1)?.trim() ?? '',
        quantity: int.tryParse(match.group(2) ?? '1') ?? 1,
        unitPriceCents: ((double.tryParse(match.group(3) ?? '0') ?? 0) * 100).round(),
        totalPriceCents: ((double.tryParse(match.group(4) ?? '0') ?? 0) * 100).round(),
      );
    }

    // Pattern 4: Line with (SKU) followed by numbers - more flexible
    // JD Sweid format: PRODUCT NAME (SKU)    QTY    UNIT_PRICE    SUBTOTAL
    final pattern4 = RegExp(r'\((\d{3,})\)');
    final skuMatch = pattern4.firstMatch(line);
    if (skuMatch != null) {
      // Found a SKU, try to extract rest
      final sku = skuMatch.group(1);
      final beforeSku = line.substring(0, skuMatch.start).trim();
      final afterSku = line.substring(skuMatch.end).trim();

      // Look for numbers after SKU - the first number should be QTY
      // Format: QTY   $PRICE   $SUBTOTAL  or  QTY   PRICE   SUBTOTAL
      final numbersPattern = RegExp(r'(\d+)\s+\$?([\d.]+)\s+\$?([\d.]+)');
      final numbersMatch = numbersPattern.firstMatch(afterSku);

      if (beforeSku.isNotEmpty && numbersMatch != null) {
        final qty = int.tryParse(numbersMatch.group(1) ?? '1') ?? 1;
        if (_debug) {
          print('Pattern4a matched: "$beforeSku" qty=$qty afterSku="$afterSku"');
          debugWarnings?.add('Pattern4a matched: "$beforeSku" qty=$qty afterSku="$afterSku"');
        }
        return ParsedOrderItemData(
          productName: beforeSku,
          sku: sku,
          quantity: qty,
          unitPriceCents: ((double.tryParse(numbersMatch.group(2) ?? '0') ?? 0) * 100).round(),
          totalPriceCents: ((double.tryParse(numbersMatch.group(3) ?? '0') ?? 0) * 100).round(),
        );
      }

      // Try: all numbers space-separated after SKU (common PDF extraction result)
      // The numbers could be: QTY PRICE SUBTOTAL or QTY UNIT_PRICE SUBTOTAL
      final allNumbers = RegExp(r'[\d.]+').allMatches(afterSku).map((m) => m.group(0)!).toList();
      if (beforeSku.isNotEmpty && allNumbers.isNotEmpty) {
        // First number that's a small integer (1-99) is likely the quantity
        int? qty;
        double? unitPrice;
        double? subtotal;

        for (int i = 0; i < allNumbers.length; i++) {
          final num = allNumbers[i];
          final intVal = int.tryParse(num);
          final doubleVal = double.tryParse(num);

          // First small integer (1-99, no decimal) is quantity
          if (qty == null && intVal != null && intVal >= 1 && intVal <= 99 && !num.contains('.')) {
            qty = intVal;
          }
          // Numbers with decimals or >= 100 are likely prices
          else if (doubleVal != null) {
            if (unitPrice == null) {
              unitPrice = doubleVal;
            } else if (subtotal == null) {
              subtotal = doubleVal;
            }
          }
        }

        if (_debug) {
          print('Pattern4b matched: "$beforeSku" qty=${qty ?? 1} numbers=$allNumbers');
          debugWarnings?.add('Pattern4b matched: "$beforeSku" qty=${qty ?? 1} numbers=$allNumbers');
        }
        return ParsedOrderItemData(
          productName: beforeSku,
          sku: sku,
          quantity: qty ?? 1,
          unitPriceCents: unitPrice != null ? (unitPrice * 100).round() : null,
          totalPriceCents: subtotal != null ? (subtotal * 100).round() : null,
        );
      }

      // Even simpler - just get first number after SKU as quantity
      final simpleQty = RegExp(r'^\s*(\d+)').firstMatch(afterSku);
      if (beforeSku.isNotEmpty && simpleQty != null) {
        final qty = int.tryParse(simpleQty.group(1) ?? '1') ?? 1;
        if (_debug) {
          print('Pattern4c matched: "$beforeSku" qty=$qty');
          debugWarnings?.add('Pattern4c matched: "$beforeSku" qty=$qty');
        }
        return ParsedOrderItemData(
          productName: beforeSku,
          sku: sku,
          quantity: qty,
        );
      }
    }

    // Pattern 5: Simple "ProductName x QTY" or "QTY x ProductName"
    final pattern5a = RegExp(r'^(.+?)\s*[xX]\s*(\d+)$');
    match = pattern5a.firstMatch(line);
    if (match != null && !_looksLikeNameLoose(match.group(1) ?? '')) {
      final name = match.group(1)?.trim() ?? '';
      if (name.length > 2 && !RegExp(r'^\d').hasMatch(name)) {
        return ParsedOrderItemData(
          productName: name,
          quantity: int.tryParse(match.group(2) ?? '1') ?? 1,
        );
      }
    }

    final pattern5b = RegExp(r'^(\d+)\s*[xX]\s*(.+)$');
    match = pattern5b.firstMatch(line);
    if (match != null) {
      final name = match.group(2)?.trim() ?? '';
      if (name.length > 2) {
        return ParsedOrderItemData(
          productName: name,
          quantity: int.tryParse(match.group(1) ?? '1') ?? 1,
        );
      }
    }

    // Pattern 6: Line with any parenthesized number that looks like SKU
    // e.g., "Chicken Breast 5kg (12345)" or "(12345) Chicken Breast"
    final skuPattern = RegExp(r'\((\d{4,})\)');
    final skuMatch2 = skuPattern.firstMatch(line);
    if (skuMatch2 != null) {
      final sku = skuMatch2.group(1);
      // Get all text after SKU (this is where QTY and prices are)
      final afterSku = line.substring(skuMatch2.end).trim();
      var productName = line.substring(0, skuMatch2.start).trim();

      if (productName.length > 2 && RegExp(r'[a-zA-Z]{2,}').hasMatch(productName)) {
        // Extract all numbers after SKU
        final numbersAfterSku = RegExp(r'[\d.]+').allMatches(afterSku).map((m) => m.group(0)!).toList();

        int? qty;
        double? unitPrice;
        double? subtotal;

        // Parse numbers: first small integer is QTY, decimals/large numbers are prices
        for (final num in numbersAfterSku) {
          final intVal = int.tryParse(num);
          final doubleVal = double.tryParse(num);

          if (qty == null && intVal != null && intVal >= 1 && intVal <= 99 && !num.contains('.')) {
            qty = intVal;
          } else if (doubleVal != null) {
            if (unitPrice == null) {
              unitPrice = doubleVal;
            } else if (subtotal == null) {
              subtotal = doubleVal;
            }
          }
        }

        return ParsedOrderItemData(
          productName: productName,
          sku: sku,
          quantity: qty ?? 1,
          unitPriceCents: unitPrice != null ? (unitPrice * 100).round() : null,
          totalPriceCents: subtotal != null ? (subtotal * 100).round() : null,
        );
      }
    }

    // Pattern 7: Line ending with numbers (QTY PRICE SUBTOTAL pattern)
    // e.g., "Chicken Breast Boneless 5kg  2  15.99  31.98"
    final endingNumbersPattern = RegExp(r'^(.+?)\s+(\d{1,2})\s+([\d.]+)\s+([\d.]+)\s*$');
    match = endingNumbersPattern.firstMatch(line);
    if (match != null) {
      final productPart = match.group(1)?.trim() ?? '';
      // Make sure product part has letters and isn't a header/name
      if (productPart.length > 2 &&
          RegExp(r'[a-zA-Z]{2,}').hasMatch(productPart) &&
          !_looksLikeNameLoose(productPart)) {
        final qty = int.tryParse(match.group(2) ?? '1') ?? 1;
        final price1 = double.tryParse(match.group(3) ?? '0') ?? 0;
        final price2 = double.tryParse(match.group(4) ?? '0') ?? 0;
        return ParsedOrderItemData(
          productName: productPart,
          quantity: qty,
          unitPriceCents: (price1 * 100).round(),
          totalPriceCents: (price2 * 100).round(),
        );
      }
    }

    // Pattern 8: Any line that looks like a product (has letters, maybe numbers, not a name)
    // This is very loose - only use if the line contains typical product indicators
    // Try to extract quantity from any numbers in the line
    if (_looksLikeProduct(line)) {
      // Try to extract numbers from the line for quantity
      final allNumbers = RegExp(r'\b(\d+)\b').allMatches(line).map((m) => m.group(1)!).toList();
      int qty = 1;
      for (final num in allNumbers) {
        final intVal = int.tryParse(num);
        // First small number (1-99) is likely quantity
        if (intVal != null && intVal >= 1 && intVal <= 99) {
          qty = intVal;
          break;
        }
      }
      final productName = line.replaceAll(RegExp(r'\s+\d+\s*$'), '').trim();
      if (_debug) {
        print('Pattern8 matched: "$productName" qty=$qty (fallback)');
        debugWarnings?.add('Pattern8 matched: "$productName" qty=$qty (fallback)');
      }
      return ParsedOrderItemData(
        productName: productName,
        quantity: qty,
      );
    }

    // Debug: Log lines with SKU that didn't match any pattern
    if (_debug && RegExp(r'\(\d{4,}\)').hasMatch(line)) {
      print('NO PATTERN MATCHED for line with SKU: "$line"');
      debugWarnings?.add('NO PATTERN MATCHED for line with SKU: "$line"');
    }

    return null;
  }

  /// Check if a line looks like a product (not a name, not a header)
  bool _looksLikeProduct(String line) {
    final upper = line.toUpperCase();

    // Must have some letters
    if (!RegExp(r'[a-zA-Z]{3,}').hasMatch(line)) return false;

    // Skip lines with SKU patterns - these should be handled by pending product mechanism
    // This prevents Pattern 8 from matching "QUIK STRIPS (6905605)" with qty=1
    if (RegExp(r'\(\d{4,}\)').hasMatch(line)) return false;

    // Skip if it looks like a name (proper case, no numbers/special chars)
    if (_looksLikeNameLoose(line)) return false;

    // Skip headers and metadata
    if (upper.contains('SUPPORTER')) return false;
    if (upper.contains('ORDER')) return false;
    if (upper.contains('SUMMARY')) return false;
    if (upper.contains('CAMPAIGN')) return false;
    if (upper.contains('DELIVERY')) return false;
    if (upper.contains('BOXES')) return false;
    if (upper.contains('PAYABLE')) return false;
    if (upper.contains('PAID')) return false;
    if (upper.contains('QTY') && upper.contains('PRICE')) return false;
    if (line.startsWith('#')) return false;
    if (upper.contains('DATE:')) return false; // Date lines
    if (upper.contains('START DATE') || upper.contains('END DATE')) return false;
    if (upper.contains('REPORT') || upper.contains('GENERATED')) return false;

    // Product indicators - contains size/weight units, or has mixed case with numbers
    final hasProductIndicators =
        RegExp(r'\d+\s*(kg|g|lb|oz|ml|l|pk|pack|box|ct|count)', caseSensitive: false).hasMatch(line) ||
        RegExp(r'(chicken|beef|pork|fish|pizza|cheese|cookie|dough|meat|breast|wing|thigh|drum)', caseSensitive: false).hasMatch(line) ||
        (RegExp(r'\d').hasMatch(line) && RegExp(r'[A-Z]').hasMatch(line) && line.length > 5);

    return hasProductIndicators;
  }

  /// Looser check for names - more permissive than _looksLikeName
  bool _looksLikeNameLoose(String line) {
    final upper = line.toUpperCase();

    // Skip lines with obvious non-name content
    if (line.contains('@')) return false;
    if (line.contains('\$')) return false;
    if (upper.contains('SUPPORTER')) return false;
    if (upper.contains('PRODUCTS')) return false;
    if (upper.contains('QTY')) return false;
    if (upper.contains('SUBTOTAL')) return false;
    if (upper.contains('UNIT PRICE')) return false;
    if (upper.contains('PAYABLE')) return false;
    if (upper.contains('BOXES')) return false;
    if (upper.contains('ORDER')) return false;
    if (upper.contains('SUMMARY')) return false;
    if (upper.contains('TOTAL')) return false;
    if (upper.contains('CAMPAIGN')) return false;
    if (upper.contains('DELIVERY')) return false;
    if (upper.contains('PICKUP')) return false;
    if (upper.contains('PICK UP')) return false;
    if (upper.contains('DATE')) return false;
    if (upper.contains('TIME')) return false;
    if (upper.contains('LOCATION')) return false;
    if (upper.contains('PAGE')) return false;
    if (upper.contains('REPORT')) return false;
    if (RegExp(r'^\d+$').hasMatch(line)) return false;
    if (RegExp(r'^\$').hasMatch(line)) return false;
    if (RegExp(r'^\(\d+\)').hasMatch(line)) return false;
    // Reject lines with SKU patterns - these are products, not names
    if (RegExp(r'\(\d{4,}\)').hasMatch(line)) return false;

    // Check length
    if (line.length < 2 || line.length > 60) return false;

    // Should have some letters
    final letterCount = line.replaceAll(RegExp(r'[^a-zA-Z]'), '').length;
    if (letterCount < 2) return false;

    // At least 40% should be letters
    if (letterCount / line.length < 0.4) return false;

    return true;
  }

  RawOrderData? _parseSupporterBlock(String blockText, List<String> warnings) {
    // Skip document header/summary blocks (not customer orders)
    final upperBlock = blockText.toUpperCase();
    if (upperBlock.contains('ORDERS SUMMARY') && upperBlock.contains('ORGANIZER')) {
      // This is the document header, not a customer order - skip silently
      return null;
    }
    if (upperBlock.contains('TOTAL # OF BOXES SOLD') ||
        upperBlock.contains('TOTAL #OF BOXES SOLD')) {
      // This is a summary section - skip silently
      return null;
    }

    // JD Sweid tabular format:
    // Syncfusion extracts columns separately, so:
    // - Product name + SKU on one line
    // - Quantity on next line (standalone number)
    // - Price on following lines

    final lines = blockText.split('\n');

    String? name;
    String? email;
    String? phone;
    String? orderId;
    String? orderDate;
    String? paymentStatus;
    final items = <ParsedOrderItemData>[];

    // Track pending product (name+SKU found, waiting for quantity)
    String? pendingProductName;
    String? pendingProductSku;

    // Pattern for box count line
    final boxCountPattern = RegExp(r'#\s*OF\s*BOXES:\s*(\d+)', caseSensitive: false);

    // Pattern for payment status
    final paidPattern = RegExp(r'\b(PAID|UNPAID)\s*$', caseSensitive: false);

    // Pattern for product name with SKU only (Syncfusion extraction format)
    // Use flexible pattern to match any characters before SKU (handles Unicode like ™)
    final productSkuOnlyPattern = RegExp(r'^([A-Za-z].+?)\s*\((\d{4,})\)\s*$');

    // Pattern for standalone quantity (small number by itself)
    final standaloneQtyPattern = RegExp(r'^(\d{1,2})$');

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final upper = line.toUpperCase();

      // Detect summary sections - stop parsing this block
      if (upper.contains('PRODUCTS ORDERED SUMMARY') ||
          upper.contains('CAMPAIGN TOTAL') ||
          upper.contains('TOTAL # OF ORDERS') ||
          upper.contains('FUNDRAISING CAMPAIGN SUMMARY')) {
        if (_debug) {
          print('Block: Hit summary section, stopping: "$line"');
        }
        break; // Stop parsing this block
      }

      // Skip column header lines
      if (line.contains('QTY') && line.contains('UNIT PRICE')) continue;
      if (line.contains('SUBTOTAL') && !line.contains('\$')) continue;

      // Check if we have a pending product and this line is a standalone quantity
      if (pendingProductName != null) {
        final qtyMatch = standaloneQtyPattern.firstMatch(line);
        if (qtyMatch != null) {
          final qty = int.tryParse(qtyMatch.group(1) ?? '1') ?? 1;
          if (_debug) {
            print('Block: Found quantity $qty for pending product: "$pendingProductName"');
          }
          items.add(ParsedOrderItemData(
            productName: pendingProductName!,
            sku: pendingProductSku,
            quantity: qty,
          ));
          pendingProductName = null;
          pendingProductSku = null;
          continue;
        }

        // Try to extract quantity from a line with numbers (QTY PRICE SUBTOTAL format)
        final allNumbers = RegExp(r'[\d.]+').allMatches(line).map((m) => m.group(0)!).toList();
        if (allNumbers.isNotEmpty) {
          int? extractedQty;
          for (final num in allNumbers) {
            final intVal = int.tryParse(num);
            // First small integer (1-99, no decimal point) is likely quantity
            if (intVal != null && intVal >= 1 && intVal <= 99 && !num.contains('.')) {
              extractedQty = intVal;
              break;
            }
          }
          if (extractedQty != null) {
            if (_debug) {
              print('Block: Extracted quantity $extractedQty from numbers $allNumbers for pending product: "$pendingProductName"');
            }
            items.add(ParsedOrderItemData(
              productName: pendingProductName!,
              sku: pendingProductSku,
              quantity: extractedQty,
            ));
            pendingProductName = null;
            pendingProductSku = null;
            continue;
          }
        }

        // If the next line is a price, save product with qty=1 and continue
        if (line.startsWith('\$') || RegExp(r'^\d+\.\d{2}$').hasMatch(line)) {
          items.add(ParsedOrderItemData(
            productName: pendingProductName!,
            sku: pendingProductSku,
            quantity: 1,
          ));
          pendingProductName = null;
          pendingProductSku = null;
        }
      }

      // Check for product line with SKU only (Syncfusion extraction format)
      final productSkuMatch = productSkuOnlyPattern.firstMatch(line);
      if (productSkuMatch != null) {
        // Save any previous pending product first
        if (pendingProductName != null) {
          items.add(ParsedOrderItemData(
            productName: pendingProductName!,
            sku: pendingProductSku,
            quantity: 1,
          ));
        }
        pendingProductName = productSkuMatch.group(1)?.trim();
        pendingProductSku = productSkuMatch.group(2);
        if (_debug) {
          print('Block: Found product (waiting for qty): "$pendingProductName"');
        }
        continue;
      }

      // Check for product line using flexible patterns (for complete lines)
      final productItem = _tryParseProductLine(line, warnings);
      if (productItem != null) {
        // Clear any pending since we got a complete product
        if (pendingProductName != null) {
          items.add(ParsedOrderItemData(
            productName: pendingProductName!,
            sku: pendingProductSku,
            quantity: 1,
          ));
          pendingProductName = null;
          pendingProductSku = null;
        }
        items.add(productItem);
        continue;
      }

      // Check for email
      final emailMatch = RegExp(r'[\w.+-]+@[\w.-]+\.\w+').firstMatch(line);
      if (emailMatch != null && email == null) {
        email = emailMatch.group(0);
        continue;
      }

      // Check for Order ID
      final orderIdMatch = RegExp(r'Order\s*ID:\s*(\d+)', caseSensitive: false).firstMatch(line);
      if (orderIdMatch != null) {
        orderId = orderIdMatch.group(1);
        continue;
      }

      // Check for Order Date
      final orderDateMatch = RegExp(r'Order\s*Date:\s*(\d{4}-\d{2}-\d{2}|\d{1,2}[/-]\d{1,2}[/-]\d{2,4})', caseSensitive: false).firstMatch(line);
      if (orderDateMatch != null) {
        orderDate = orderDateMatch.group(1);
        continue;
      }

      // Check for box count and payment status line
      final boxMatch = boxCountPattern.firstMatch(line);
      if (boxMatch != null) {
        // Save any pending product before ending block
        if (pendingProductName != null) {
          items.add(ParsedOrderItemData(
            productName: pendingProductName!,
            sku: pendingProductSku,
            quantity: 1,
          ));
          pendingProductName = null;
          pendingProductSku = null;
        }
        // This line also contains payment status
        final paidMatch = paidPattern.firstMatch(line);
        if (paidMatch != null) {
          paymentStatus = paidMatch.group(1)?.toLowerCase();
        }
        continue;
      }

      // Check for standalone phone number (10+ digits)
      final phoneDigits = line.replaceAll(RegExp(r'\D'), '');
      if (phoneDigits.length >= 10 && phoneDigits.length <= 12 && phone == null) {
        phone = line;
        continue;
      }

      // Check for customer name (first line that looks like a name)
      // Names can be various formats: "John Smith", "JOHN SMITH", "John O'Brien", etc.
      if (name == null && _looksLikeName(line)) {
        name = line;
        continue;
      }
    }

    if (name == null) {
      // Try to find name from first few non-header lines
      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.isEmpty) continue;
        if (line.contains('QTY') || line.contains('SUBTOTAL')) continue;
        if (line.contains('@') || line.contains('\$')) continue;
        if (RegExp(r'^\d+$').hasMatch(line)) continue;
        if (line.contains('SUPPORTER') || line.contains('PRODUCTS')) continue;
        if (line.contains('UNIT PRICE') || line.contains('PAYABLE')) continue;

        // First reasonable text line is likely the name
        if (line.length > 2 && line.length < 50 && _looksLikeName(line)) {
          name = line;
          break;
        }
      }
    }

    // Last resort: grab first non-header line
    if (name == null) {
      for (final rawLine in lines) {
        final line = rawLine.trim();
        final upper = line.toUpperCase();
        if (line.isEmpty) continue;
        if (upper.contains('QTY') || upper.contains('SUBTOTAL')) continue;
        if (line.contains('@') || line.contains('\$')) continue;
        if (upper.contains('SUPPORTER') || upper.contains('PRODUCTS')) continue;
        if (upper.contains('UNIT PRICE') || upper.contains('PAYABLE')) continue;
        if (upper.contains('BOXES') || upper.contains('ORDER')) continue;
        if (upper.contains('SUMMARY') || upper.contains('TOTAL')) continue;
        if (upper.contains('CAMPAIGN') || upper.contains('REPORT')) continue;
        if (upper.contains('DELIVERY') || upper.contains('PAGE')) continue;
        if (RegExp(r'^\d+$').hasMatch(line)) continue;
        if (RegExp(r'^\(?\d').hasMatch(line)) continue; // Starts with number or (number

        if (line.length > 2 && line.length < 60) {
          name = line;
          break;
        }
      }
    }

    if (name == null) {
      // Add first 100 chars of block for debugging
      final preview = blockText.trim().replaceAll(RegExp(r'\s+'), ' ');
      final shortPreview = preview.length > 100 ? preview.substring(0, 100) : preview;
      warnings.add('Skipped block with no identifiable name: "$shortPreview"');
      return null;
    }

    // Save any pending product
    if (pendingProductName != null) {
      items.add(ParsedOrderItemData(
        productName: pendingProductName!,
        sku: pendingProductSku,
        quantity: 1,
      ));
    }

    return RawOrderData(
      name: name,
      email: email,
      phone: phone,
      orderId: orderId,
      orderDate: orderDate,
      paymentStatus: paymentStatus,
      items: items,
      rawText: blockText,
    );
  }

  /// Check if a line looks like a person's name
  bool _looksLikeName(String line) {
    final upper = line.toUpperCase();

    // Skip lines with obvious non-name content
    if (line.contains('@')) return false; // Email
    if (line.contains('\$')) return false; // Price
    if (upper.contains('ORDER')) return false;
    if (upper.contains('SUMMARY')) return false;
    if (upper.contains('TOTAL')) return false;
    if (upper.contains('BOXES')) return false;
    if (upper.contains('SUPPORTER')) return false;
    if (upper.contains('PRODUCTS')) return false;
    if (upper.contains('QTY')) return false;
    if (upper.contains('SUBTOTAL')) return false;
    if (upper.contains('UNIT PRICE')) return false;
    if (upper.contains('PAYABLE')) return false;
    if (upper.contains('CAMPAIGN')) return false;
    if (upper.contains('DELIVERY')) return false;
    if (upper.contains('REPORT')) return false;
    if (upper.contains('PAGE')) return false;
    if (RegExp(r'^\d+$').hasMatch(line)) return false; // Just numbers
    if (RegExp(r'^\(?\d').hasMatch(line)) return false; // Starts with number

    // Check length - names are typically 3-50 chars
    if (line.length < 3 || line.length > 50) return false;

    // Names should contain mostly letters (allow spaces, hyphens, apostrophes)
    final letterCount = line.replaceAll(RegExp(r'[^a-zA-Z]'), '').length;
    if (letterCount < 2) return false;

    // At least 50% should be letters
    if (letterCount / line.length < 0.5) return false;

    // Should look like words (letters with spaces/punctuation between)
    // Matches: "John Smith", "JOHN SMITH", "Mary O'Brien", "Jean-Luc Picard"
    if (RegExp(r"^[A-Za-z][A-Za-z\s'\-\.]+$").hasMatch(line)) {
      return true;
    }

    return false;
  }

  List<RawOrderData> _parseAlternativeFormat(
      String text, List<String> warnings) {
    final orders = <RawOrderData>[];

    // Try parsing as a table format
    final lines = text.split('\n');

    // Look for header row
    int headerIndex = -1;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].toLowerCase();
      if (line.contains('name') &&
          (line.contains('email') || line.contains('phone') || line.contains('order'))) {
        headerIndex = i;
        break;
      }
    }

    if (headerIndex == -1) {
      return orders;
    }

    // Parse data rows after header
    for (var i = headerIndex + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // Try to extract fields from the line
      final email = RegExp(r'[\w.+-]+@[\w.-]+\.\w+').firstMatch(line)?.group(0);
      final phone = RegExp(r'(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}')
          .firstMatch(line)?.group(0);

      // Remove email and phone to get remaining text for name
      var remaining = line
          .replaceAll(RegExp(r'[\w.+-]+@[\w.-]+\.\w+'), '')
          .replaceAll(
              RegExp(r'(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}'), '')
          .trim();

      // Split remaining by common delimiters
      final parts = remaining.split(RegExp(r'\s*[|,\t]\s*'));
      final name = parts.isNotEmpty ? parts.first.trim() : null;

      if (name != null && name.isNotEmpty) {
        orders.add(RawOrderData(
          name: name,
          email: email,
          phone: phone,
          rawText: line,
        ));
      }
    }

    return orders;
  }
}
