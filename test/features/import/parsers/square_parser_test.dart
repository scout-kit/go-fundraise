import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_fundraise/features/import/parsers/square_parser.dart';
import 'package:go_fundraise/features/import/parsers/parser_utils.dart';
import 'package:go_fundraise/features/import/parsers/customer_consolidator.dart';
import 'package:go_fundraise/core/models/parsed_data.dart';

/// Test suite for SquareParser
///
/// These tests verify that the Square Online CSV parser correctly:
/// 1. Parses the sample CSV with expected order, customer, and item counts
/// 2. Rejects non-Square CSV files
/// 3. Groups multi-row orders by Order ID
/// 4. Extracts customer info from Recipient columns
/// 5. Builds product names with participant variations
/// 6. Handles prices, quantities, and dates
/// 7. Consolidates customers by email
void main() {
  late Uint8List sampleCsvBytes;
  late SquareParser parser;

  setUpAll(() {
    final file = File('test/fixtures/square.csv');
    sampleCsvBytes = file.readAsBytesSync();
    parser = SquareParser();
  });

  group('SquareParser', () {
    group('parseBytes', () {
      test('parses sample CSV with 10 orders and 25 total items', () async {
        final result =
            await parser.parseBytes(sampleCsvBytes, 'square.csv');

        expect(result.errors, isEmpty, reason: 'Parser should not produce errors');

        expect(result.totalOrders, equals(10),
            reason: 'Expected 10 orders from sample CSV');
        expect(result.totalBoxes, equals(25),
            reason: 'Expected 25 total items from sample CSV');

        expect(result.customers, isNotEmpty,
            reason: 'Parser should produce customers');
      });

      test('sets correct source metadata', () async {
        final result =
            await parser.parseBytes(sampleCsvBytes, 'test_export.csv');

        expect(result.sourceFileName, equals('test_export.csv'));
        expect(result.sourceType, equals('csv'));
        expect(result.name, contains('Square'));
      });

      test('rejects non-Square CSV file', () async {
        final csvContent =
            'Name,Email,Phone\nJohn,john@test.com,555-1234\n';
        final bytes = Uint8List.fromList(csvContent.codeUnits);

        expect(
          () => parser.parseBytes(bytes, 'generic.csv'),
          throwsA(isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('does not appear to be a Square'),
          )),
        );
      });

      test('rejects empty CSV file', () async {
        final bytes = Uint8List.fromList(''.codeUnits);

        expect(
          () => parser.parseBytes(bytes, 'empty.csv'),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('order parsing', () {
      test('groups multi-row orders correctly', () async {
        final result =
            await parser.parseBytes(sampleCsvBytes, 'square.csv');

        // Orders with 3 items (e.g., Order 1321304339 has 3 rows)
        // should result in 1 order with 3 items
        for (final customer in result.customers) {
          for (final order in customer.orders) {
            expect(order.items, isNotEmpty,
                reason:
                    'Every order should have at least one item');
          }
        }
      });

      test('extracts customer names from Recipient Name', () async {
        final result =
            await parser.parseBytes(sampleCsvBytes, 'square.csv');

        for (final customer in result.customers) {
          expect(customer.displayName, isNotEmpty,
              reason: 'Every customer should have a display name');
        }
      });

      test('extracts email addresses', () async {
        final result =
            await parser.parseBytes(sampleCsvBytes, 'square.csv');

        int customersWithEmail = 0;
        for (final customer in result.customers) {
          if (customer.hasEmail) {
            customersWithEmail++;
            expect(customer.email, contains('@'),
                reason: 'Email should contain @');
          }
        }

        // All Square customers should have email
        expect(customersWithEmail, equals(result.customers.length),
            reason: 'All Square customers should have email');
      });

      test('extracts and normalizes phone numbers', () async {
        final result =
            await parser.parseBytes(sampleCsvBytes, 'square.csv');

        int customersWithPhone = 0;
        for (final customer in result.customers) {
          if (customer.hasPhone) {
            customersWithPhone++;
            // Phone should be normalized from +1XXXXXXXXXX to XXX-XXX-XXXX
            expect(
              customer.phone!.replaceAll('-', '').length,
              equals(10),
              reason: 'Phone should have 10 digits after normalization',
            );
          }
        }

        expect(customersWithPhone, greaterThan(0),
            reason: 'Some customers should have phone numbers');
      });

      test('extracts order IDs (numeric part only)', () async {
        final result =
            await parser.parseBytes(sampleCsvBytes, 'square.csv');

        for (final customer in result.customers) {
          for (final order in customer.orders) {
            if (order.originalOrderId != null) {
              // Should be just the numeric part, not "Square Online XXXX"
              expect(
                order.originalOrderId,
                matches(RegExp(r'^\d+$')),
                reason:
                    'Order ID should be numeric (extracted from "Square Online XXXX")',
              );
            }
          }
        }
      });

      test('extracts order dates', () async {
        final result =
            await parser.parseBytes(sampleCsvBytes, 'square.csv');

        int ordersWithDate = 0;
        for (final customer in result.customers) {
          for (final order in customer.orders) {
            if (order.orderDate != null && order.orderDate!.isNotEmpty) {
              ordersWithDate++;
            }
          }
        }

        expect(ordersWithDate, equals(result.totalOrders),
            reason: 'All orders should have dates');
      });
    });

    group('item parsing', () {
      test('parses product names', () async {
        final result =
            await parser.parseBytes(sampleCsvBytes, 'square.csv');

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

      test('appends participant variation to product name', () async {
        final result =
            await parser.parseBytes(sampleCsvBytes, 'square.csv');

        // Find items with non-"Regular" variations (should have parenthesized name)
        int itemsWithVariation = 0;
        for (final customer in result.customers) {
          for (final order in customer.orders) {
            for (final item in order.items) {
              if (item.productName.contains('(') &&
                  item.productName.contains(')')) {
                itemsWithVariation++;
              }
            }
          }
        }

        expect(itemsWithVariation, greaterThan(0),
            reason:
                'Some items should have participant names appended');
      });

      test('excludes "Regular" variation from product name', () async {
        final result =
            await parser.parseBytes(sampleCsvBytes, 'square.csv');

        for (final customer in result.customers) {
          for (final order in customer.orders) {
            for (final item in order.items) {
              expect(item.productName, isNot(contains('(Regular)')),
                  reason:
                      '"Regular" variation should not be appended to product name');
            }
          }
        }
      });

      test('extracts quantities correctly', () async {
        final result =
            await parser.parseBytes(sampleCsvBytes, 'square.csv');

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

        expect(calculatedBoxes, equals(25),
            reason: 'Sum of item quantities should equal 25 items');
      });

      test('parses prices in cents', () async {
        final result =
            await parser.parseBytes(sampleCsvBytes, 'square.csv');

        int itemsWithPrice = 0;
        for (final customer in result.customers) {
          for (final order in customer.orders) {
            for (final item in order.items) {
              if (item.unitPriceCents != null && item.unitPriceCents! > 0) {
                itemsWithPrice++;
                // Prices in the fixture are $4.00 or $5.00
                expect(item.unitPriceCents, greaterThanOrEqualTo(400),
                    reason: 'Unit price should be >= \$4.00');
                expect(item.unitPriceCents, lessThanOrEqualTo(500),
                    reason: 'Unit price should be <= \$5.00');
              }
            }
          }
        }

        expect(itemsWithPrice, greaterThan(0),
            reason: 'Some items should have prices');
      });
    });

    group('customer consolidation', () {
      test('consolidates orders sharing the same email', () async {
        final result =
            await parser.parseBytes(sampleCsvBytes, 'square.csv');

        // jane.smith@example.com has 2 orders (Jane Smith + Jane S)
        // These should be consolidated into 1 customer
        expect(result.customers.length, equals(9),
            reason:
                'Expected 9 unique customers (10 orders, 2 share an email)');
      });

      test('preserves all orders when merging', () async {
        final result =
            await parser.parseBytes(sampleCsvBytes, 'square.csv');

        expect(result.totalOrders, equals(10),
            reason: 'Consolidation should preserve all 10 orders');
      });

      test('tracks original names for merged customers', () async {
        final result =
            await parser.parseBytes(sampleCsvBytes, 'square.csv');

        for (final customer in result.customers) {
          expect(customer.originalNames, isNotEmpty,
              reason:
                  'Every customer should have at least one original name');
        }
      });

      test('merged customer has multiple orders', () async {
        final result =
            await parser.parseBytes(sampleCsvBytes, 'square.csv');

        // Find the consolidated customer (has 2 orders from same email)
        final mergedCustomers =
            result.customers.where((c) => c.orders.length > 1).toList();

        expect(mergedCustomers, isNotEmpty,
            reason:
                'At least one customer should have multiple orders (consolidated)');
      });
    });

    group('warnings', () {
      test('does not produce errors on valid Square CSV', () async {
        final result =
            await parser.parseBytes(sampleCsvBytes, 'square.csv');

        expect(result.errors, isEmpty,
            reason: 'Valid Square CSV should produce no errors');
      });
    });
  });

  group('ParserUtils (shared utilities)', () {
    test('normalizePhone handles international format', () {
      // Square uses +1XXXXXXXXXX format
      expect(
          ParserUtils.normalizePhone('+15551234567'), equals('555-123-4567'));
      expect(
          ParserUtils.normalizePhone('+15552345678'), equals('555-234-5678'));
    });

    test('generateDefaultName includes Square and date', () {
      final name = ParserUtils.generateDefaultName('Square');
      expect(name, startsWith('Square'));
      expect(name, contains(DateTime.now().year.toString()));
    });
  });

  group('CustomerConsolidator (shared utility)', () {
    test('consolidates Square orders by email', () {
      final consolidator = CustomerConsolidator();
      final orders = [
        RawOrderData(
          name: 'Jane Smith',
          email: 'jane.smith@example.com',
          phone: '555-123-4567',
          items: [ParsedOrderItemData(productName: 'Swimming', quantity: 1)],
        ),
        RawOrderData(
          name: 'Jane S',
          email: 'jane.smith@example.com',
          phone: '555-123-4567',
          items: [
            ParsedOrderItemData(productName: 'Swimming Scouts', quantity: 1)
          ],
        ),
      ];

      final customers = consolidator.consolidate(orders);

      expect(customers.length, equals(1),
          reason: 'Same email should merge into one customer');
      expect(customers.first.orders.length, equals(2),
          reason: 'Should have both orders');
      expect(customers.first.totalBoxes, equals(2),
          reason: 'Should have 1 + 1 = 2 boxes');
    });
  });
}
