import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_fundraise/features/import/parsers/little_caesars_parser.dart';
import 'package:go_fundraise/features/import/parsers/parser_utils.dart';
import 'package:go_fundraise/features/import/parsers/customer_consolidator.dart';
import 'package:go_fundraise/core/models/parsed_data.dart';

/// Test suite for LittleCaesarsParser
///
/// These tests verify that the Little Caesars PDF parser correctly:
/// 1. Parses the sample PDF with expected order and box counts
/// 2. Rejects non-Little Caesars PDFs
/// 3. Extracts customer information correctly (seller = customer)
/// 4. Extracts buyer info on orders (buyer name and phone)
/// 5. Handles item parsing and quantity extraction
/// 6. Consolidates customers properly by seller name
void main() {
  late Uint8List samplePdfBytes;
  late LittleCaesarsParser parser;

  setUpAll(() {
    // Load the sample PDF fixture
    final file = File('test/fixtures/little_caesars.pdf');
    samplePdfBytes = file.readAsBytesSync();
    parser = LittleCaesarsParser();
  });

  group('LittleCaesarsParser', () {
    group('parseBytes', () {
      test('parses sample PDF with 35 orders and 97 boxes', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'little_caesars.pdf');

        // Verify no errors
        expect(result.errors, isEmpty, reason: 'Parser should not produce errors');

        // Calculate totals using the model's built-in methods
        expect(result.totalOrders, equals(35),
            reason: 'Expected 35 orders from sample PDF');
        expect(result.totalBoxes, equals(97),
            reason: 'Expected 97 boxes from sample PDF');

        // Also verify we have customers
        expect(result.customers, isNotEmpty,
            reason: 'Parser should produce customers');
      });

      test('sets correct source metadata', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'test_file.pdf');

        expect(result.sourceFileName, equals('test_file.pdf'));
        expect(result.sourceType, equals('pdf'));
        expect(result.name, contains('Little Caesars'));
      });

      test('rejects non-Little Caesars PDF', () async {
        // Create a minimal PDF that doesn't contain "Group Delivery"
        // Using JD Sweid PDF as a different format
        final jdSweidFile = File('test/fixtures/jdsweid.pdf');
        if (jdSweidFile.existsSync()) {
          final jdSweidBytes = jdSweidFile.readAsBytesSync();

          expect(
            () => parser.parseBytes(jdSweidBytes, 'jdsweid.pdf'),
            throwsA(isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('does not appear to be a Little Caesars PDF'),
            )),
          );
        }
      });

      test('extracts delivery date, location, time when present', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'little_caesars.pdf');

        // These may be null if not present in PDF, but shouldn't throw
        // Just verify the fields exist and the parser handles them
        expect(result.deliveryDate, anyOf(isNull, isA<String>()));
        expect(result.deliveryLocation, anyOf(isNull, isA<String>()));
        expect(result.deliveryTime, anyOf(isNull, isA<String>()));
      });
    });

    group('order parsing', () {
      test('extracts seller names as customer names from headers', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'little_caesars.pdf');

        // All customers should have display names (from seller field)
        for (final customer in result.customers) {
          expect(customer.displayName, isNotEmpty,
              reason: 'Every customer should have a display name (from seller)');
        }
      });

      test('extracts buyer names on orders', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'little_caesars.pdf');

        // Count orders with buyer names
        int ordersWithBuyerName = 0;
        for (final customer in result.customers) {
          for (final order in customer.orders) {
            if (order.buyerName != null && order.buyerName!.isNotEmpty) {
              ordersWithBuyerName++;
            }
          }
        }

        // Most orders should have buyer names
        expect(ordersWithBuyerName, greaterThan(result.totalOrders * 0.8),
            reason: 'Most orders should have buyer names');
      });

      test('extracts buyer phone numbers on orders', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'little_caesars.pdf');

        // Count orders with buyer phones
        int ordersWithBuyerPhone = 0;
        for (final customer in result.customers) {
          for (final order in customer.orders) {
            if (order.buyerPhone != null && order.buyerPhone!.isNotEmpty) {
              ordersWithBuyerPhone++;
              // Verify phone format (XXX-XXX-XXXX or 10 digits)
              expect(
                order.buyerPhone!.replaceAll('-', '').length,
                equals(10),
                reason: 'Buyer phone numbers should have 10 digits',
              );
            }
          }
        }

        // Some orders should have buyer phone numbers
        expect(ordersWithBuyerPhone, greaterThan(0),
            reason: 'Some orders should have buyer phone numbers');
      });

      test('extracts order IDs', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'little_caesars.pdf');

        // Count orders with order IDs
        int ordersWithIds = 0;
        for (final customer in result.customers) {
          for (final order in customer.orders) {
            if (order.originalOrderId != null && order.originalOrderId!.isNotEmpty) {
              ordersWithIds++;
            }
          }
        }

        // Most orders should have IDs (at least 80%)
        expect(ordersWithIds, greaterThan(result.totalOrders * 0.8),
            reason: 'Most orders should have order IDs');
      });

      test('customers have no phone numbers (phone belongs to buyer)', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'little_caesars.pdf');

        // In LC PDFs, phone belongs to buyer, not seller (customer)
        // So customers should not have phone numbers
        for (final customer in result.customers) {
          expect(customer.hasPhone, isFalse,
              reason: 'LC customers should not have phone (it belongs to buyer)');
        }
      });

      test('extracts payment status (paid/unpaid)', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'little_caesars.pdf');

        int ordersWithPaymentStatus = 0;
        for (final customer in result.customers) {
          for (final order in customer.orders) {
            if (order.paymentStatus != null) {
              ordersWithPaymentStatus++;
              expect(
                order.paymentStatus,
                anyOf(equals('paid'), equals('unpaid')),
                reason: 'Payment status should be "paid" or "unpaid"',
              );
            }
          }
        }

        // Most orders should have payment status
        expect(ordersWithPaymentStatus, greaterThan(result.totalOrders * 0.5),
            reason: 'Most orders should have payment status');
      });
    });

    group('item parsing', () {
      test('parses product names', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'little_caesars.pdf');

        int itemCount = 0;
        for (final customer in result.customers) {
          for (final order in customer.orders) {
            for (final item in order.items) {
              itemCount++;
              expect(item.productName, isNotEmpty,
                  reason: 'Every item should have a product name');
            }
          }
        }

        expect(itemCount, greaterThan(0), reason: 'Should have parsed items');
      });

      test('parses SKUs when present', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'little_caesars.pdf');

        int itemsWithSku = 0;
        for (final customer in result.customers) {
          for (final order in customer.orders) {
            for (final item in order.items) {
              if (item.sku != null && item.sku!.isNotEmpty) {
                itemsWithSku++;
                // LC SKUs are typically 2-4 uppercase letters
                expect(
                  item.sku,
                  matches(RegExp(r'^[A-Z]{1,4}$')),
                  reason: 'SKU should be 1-4 uppercase letters',
                );
              }
            }
          }
        }

        expect(itemsWithSku, greaterThan(0),
            reason: 'Some items should have SKUs');
      });

      test('extracts quantities correctly', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'little_caesars.pdf');

        // Total boxes should equal sum of all item quantities
        int calculatedBoxes = 0;
        for (final customer in result.customers) {
          for (final order in customer.orders) {
            for (final item in order.items) {
              expect(item.quantity, greaterThan(0),
                  reason: 'Item quantity must be positive');
              calculatedBoxes += item.quantity;
            }
          }
        }

        expect(calculatedBoxes, equals(97),
            reason: 'Sum of item quantities should equal 97 boxes');
      });

      test('parses prices when present', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'little_caesars.pdf');

        int itemsWithPrice = 0;
        for (final customer in result.customers) {
          for (final order in customer.orders) {
            for (final item in order.items) {
              if (item.unitPriceCents != null && item.unitPriceCents! > 0) {
                itemsWithPrice++;
                // Verify price is reasonable (between $1 and $100)
                expect(item.unitPriceCents, greaterThan(100),
                    reason: 'Unit price should be > 1 dollar');
                expect(item.unitPriceCents, lessThan(10000),
                    reason: 'Unit price should be < 100 dollars');
              }
            }
          }
        }

        expect(itemsWithPrice, greaterThan(0),
            reason: 'Some items should have prices');
      });
    });

    group('customer consolidation', () {
      test('consolidates orders by seller name', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'little_caesars.pdf');

        // If there are 35 orders but fewer customers, consolidation worked
        // (multiple buyers ordered from the same seller)
        expect(result.customers.length, lessThanOrEqualTo(35),
            reason: 'Customer count should be <= order count after consolidation');

        // Verify customers with multiple orders (same seller, different buyers)
        final customersWithMultipleOrders = result.customers
            .where((c) => c.orders.length > 1)
            .toList();

        // These customers should have been consolidated by seller name
        for (final customer in customersWithMultipleOrders) {
          expect(customer.orders.length, greaterThan(1),
              reason: 'Consolidated customer should have multiple orders');

          // Each order may have a different buyer
          final buyerNames = customer.orders
              .where((o) => o.buyerName != null)
              .map((o) => o.buyerName!)
              .toSet();
          // Having different buyer names is expected (multiple supporters bought from same seller)
          expect(buyerNames, isNotEmpty,
              reason: 'Consolidated orders should have buyer names');
        }
      });

      test('preserves all orders when merging', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'little_caesars.pdf');

        // Total orders across all customers should still be 35
        expect(result.totalOrders, equals(35),
            reason: 'Consolidation should preserve all 35 orders');
      });

      test('tracks original names for merged customers', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'little_caesars.pdf');

        for (final customer in result.customers) {
          expect(customer.originalNames, isNotEmpty,
              reason: 'Every customer should have at least one original name');

          // Display name should be one of the original names
          expect(
            customer.originalNames.contains(customer.displayName),
            isTrue,
            reason: 'Display name should be from original names',
          );
        }
      });
    });

    group('warnings', () {
      test('generates warnings for orders without buyer phone', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'little_caesars.pdf');

        // Count orders without buyer phone
        int ordersWithoutBuyerPhone = 0;
        for (final customer in result.customers) {
          for (final order in customer.orders) {
            if (order.buyerPhone == null || order.buyerPhone!.isEmpty) {
              ordersWithoutBuyerPhone++;
            }
          }
        }

        if (ordersWithoutBuyerPhone > 0) {
          // Should have warnings about missing buyer phone
          expect(result.warnings, isNotEmpty,
              reason: 'Should warn about orders without buyer phone');
        }
      });

      test('does not warn about customers without contact info', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'little_caesars.pdf');

        // LC customers (sellers) won't have phone numbers - this is expected
        // So there should be no warnings about "customer has no email or phone"
        final customerContactWarnings = result.warnings
            .where((w) => w.contains('has no email or phone'))
            .toList();

        expect(customerContactWarnings, isEmpty,
            reason: 'LC should not warn about customer contact info (only buyer phone matters)');
      });
    });
  });

  group('ParserUtils (shared utilities)', () {
    test('normalizePhone formats 10-digit numbers', () {
      expect(ParserUtils.normalizePhone('1234567890'), equals('123-456-7890'));
      expect(ParserUtils.normalizePhone('123-456-7890'), equals('123-456-7890'));
      expect(ParserUtils.normalizePhone('(123) 456-7890'), equals('123-456-7890'));
    });

    test('normalizePhone handles 11-digit numbers with leading 1', () {
      expect(ParserUtils.normalizePhone('11234567890'), equals('123-456-7890'));
      expect(ParserUtils.normalizePhone('+1 123-456-7890'), equals('123-456-7890'));
    });

    test('generateDefaultName includes parser type and date', () {
      final name = ParserUtils.generateDefaultName('Little Caesars');
      expect(name, startsWith('Little Caesars'));
      expect(name, contains(DateTime.now().year.toString()));
    });
  });

  group('CustomerConsolidator (shared utility)', () {
    test('consolidates by phone number', () {
      final consolidator = CustomerConsolidator();
      final orders = [
        RawOrderData(
          name: 'John Doe',
          phone: '123-456-7890',
          items: [ParsedOrderItemData(productName: 'Pizza', quantity: 2)],
        ),
        RawOrderData(
          name: 'John D',
          phone: '123-456-7890',
          items: [ParsedOrderItemData(productName: 'Breadsticks', quantity: 1)],
        ),
      ];

      final customers = consolidator.consolidate(orders);

      expect(customers.length, equals(1),
          reason: 'Same phone should merge into one customer');
      expect(customers.first.orders.length, equals(2),
          reason: 'Should have both orders');
      expect(customers.first.totalBoxes, equals(3),
          reason: 'Should have 2 + 1 = 3 boxes');
    });

    test('consolidates by normalized name when no phone/email', () {
      final consolidator = CustomerConsolidator();
      final orders = [
        RawOrderData(
          name: 'Jane Smith',
          items: [ParsedOrderItemData(productName: 'Pizza', quantity: 1)],
        ),
        RawOrderData(
          name: 'JANE SMITH',
          items: [ParsedOrderItemData(productName: 'Wings', quantity: 1)],
        ),
      ];

      final customers = consolidator.consolidate(orders);

      expect(customers.length, equals(1),
          reason: 'Same normalized name should merge');
      expect(customers.first.orders.length, equals(2));
    });

    test('passes through buyerName and buyerPhone to orders', () {
      final consolidator = CustomerConsolidator();
      final orders = [
        RawOrderData(
          name: 'Seller Scout',
          buyerName: 'Buyer One',
          buyerPhone: '111-222-3333',
          items: [ParsedOrderItemData(productName: 'Pizza', quantity: 1)],
        ),
        RawOrderData(
          name: 'Seller Scout',
          buyerName: 'Buyer Two',
          buyerPhone: '444-555-6666',
          items: [ParsedOrderItemData(productName: 'Wings', quantity: 2)],
        ),
      ];

      final customers = consolidator.consolidate(orders);

      expect(customers.length, equals(1),
          reason: 'Same seller should merge into one customer');
      expect(customers.first.displayName, equals('Seller Scout'));
      expect(customers.first.orders.length, equals(2));

      // Verify buyer info is preserved on each order
      final buyerNames = customers.first.orders.map((o) => o.buyerName).toSet();
      expect(buyerNames, containsAll(['Buyer One', 'Buyer Two']),
          reason: 'Each order should retain its buyer name');

      final buyerPhones = customers.first.orders.map((o) => o.buyerPhone).toSet();
      expect(buyerPhones, containsAll(['111-222-3333', '444-555-6666']),
          reason: 'Each order should retain its buyer phone');
    });
  });
}
