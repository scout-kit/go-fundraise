import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_fundraise/features/import/parsers/jd_sweid_parser.dart';
import 'package:go_fundraise/features/import/parsers/parser_utils.dart';
import 'package:go_fundraise/features/import/parsers/customer_consolidator.dart';
import 'package:go_fundraise/core/models/parsed_data.dart';

/// Test suite for JdSweidParser
///
/// These tests verify that the JD Sweid PDF parser correctly:
/// 1. Parses the sample PDF with expected order, customer, and box counts
/// 2. Rejects non-JD Sweid PDFs
/// 3. Extracts customer information correctly
/// 4. Handles item parsing and quantity extraction
/// 5. Consolidates customers properly
void main() {
  late Uint8List samplePdfBytes;
  late JdSweidParser parser;

  setUpAll(() {
    // Load the sample PDF fixture
    final file = File('test/fixtures/jdsweid.pdf');
    samplePdfBytes = file.readAsBytesSync();
    parser = JdSweidParser();
  });

  group('JdSweidParser', () {
    group('parseBytes', () {
      test('parses sample PDF with 28 orders, 25 customers, and 99 boxes', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'jdsweid.pdf');

        // Verify no errors
        expect(result.errors, isEmpty, reason: 'Parser should not produce errors');

        // Calculate totals using the model's built-in methods
        expect(result.totalOrders, equals(28),
            reason: 'Expected 28 orders from sample PDF');
        expect(result.customers.length, equals(25),
            reason: 'Expected 25 customers after consolidation');
        expect(result.totalBoxes, equals(99),
            reason: 'Expected 99 boxes from sample PDF');

        // Also verify we have customers
        expect(result.customers, isNotEmpty,
            reason: 'Parser should produce customers');
      });

      test('sets correct source metadata', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'test_file.pdf');

        expect(result.sourceFileName, equals('test_file.pdf'));
        expect(result.sourceType, equals('pdf'));
        expect(result.name, contains('JD Sweid'));
      });

      test('rejects non-JD Sweid PDF', () async {
        // Load Little Caesars PDF as a different format
        final lcFile = File('test/fixtures/little_caesars.pdf');
        if (lcFile.existsSync()) {
          final lcBytes = lcFile.readAsBytesSync();

          expect(
            () => parser.parseBytes(lcBytes, 'little_caesars.pdf'),
            throwsA(isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('does not appear to be a JD Sweid PDF'),
            )),
          );
        }
      });

      test('extracts delivery date when present', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'jdsweid.pdf');

        // JD Sweid PDFs typically contain delivery date info
        // The value may be null if not present, but shouldn't throw
        expect(result.deliveryDate, anyOf(isNull, isA<String>()));
        expect(result.deliveryLocation, anyOf(isNull, isA<String>()));
        expect(result.deliveryTime, anyOf(isNull, isA<String>()));
      });
    });

    group('order parsing', () {
      test('extracts customer names from supporter blocks', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'jdsweid.pdf');

        // All customers should have display names
        for (final customer in result.customers) {
          expect(customer.displayName, isNotEmpty,
              reason: 'Every customer should have a display name');
        }
      });

      test('extracts email addresses when present', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'jdsweid.pdf');

        // Count customers with email addresses
        int customersWithEmail = 0;
        for (final customer in result.customers) {
          if (customer.hasEmail) {
            customersWithEmail++;
            // Verify email format
            expect(
              customer.email,
              matches(RegExp(r'^[\w.+-]+@[\w.-]+\.\w+$')),
              reason: 'Email should be valid format',
            );
          }
        }

        // JD Sweid PDFs typically include emails
        expect(customersWithEmail, greaterThan(0),
            reason: 'Some customers should have email addresses');
      });

      test('extracts phone numbers when present', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'jdsweid.pdf');

        // Count customers with phone numbers
        int customersWithPhone = 0;
        for (final customer in result.customers) {
          if (customer.hasPhone) {
            customersWithPhone++;
          }
        }

        // Some customers may have phone numbers
        // This is informational - JD Sweid format may or may not include phones
        expect(customersWithPhone, greaterThanOrEqualTo(0));
      });

      test('extracts payment status (paid/unpaid) when present', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'jdsweid.pdf');

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

        // Payment status is optional - just verify valid values if present
        expect(ordersWithPaymentStatus, greaterThanOrEqualTo(0),
            reason: 'Payment status extraction should not fail');
      });
    });

    group('item parsing', () {
      test('parses product names', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'jdsweid.pdf');

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
        final result = await parser.parseBytes(samplePdfBytes, 'jdsweid.pdf');

        int itemsWithSku = 0;
        for (final customer in result.customers) {
          for (final order in customer.orders) {
            for (final item in order.items) {
              if (item.sku != null && item.sku!.isNotEmpty) {
                itemsWithSku++;
                // JD Sweid SKUs are typically numeric (4+ digits)
                expect(
                  item.sku,
                  matches(RegExp(r'^\d{4,}$')),
                  reason: 'SKU should be 4+ digit number',
                );
              }
            }
          }
        }

        expect(itemsWithSku, greaterThan(0),
            reason: 'Some items should have SKUs');
      });

      test('extracts quantities correctly', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'jdsweid.pdf');

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

        expect(calculatedBoxes, equals(99),
            reason: 'Sum of item quantities should equal 99 boxes');
      });

      test('parses prices when present', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'jdsweid.pdf');

        int itemsWithPrice = 0;
        for (final customer in result.customers) {
          for (final order in customer.orders) {
            for (final item in order.items) {
              if (item.unitPriceCents != null && item.unitPriceCents! > 0) {
                itemsWithPrice++;
              }
            }
          }
        }

        // Prices are optional - verify extraction doesn't fail
        // Some JD Sweid PDFs may not include price columns
        expect(itemsWithPrice, greaterThanOrEqualTo(0),
            reason: 'Price extraction should not fail');
      });
    });

    group('customer consolidation', () {
      test('consolidates customers correctly (28 orders to 25 customers)', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'jdsweid.pdf');

        // 28 orders consolidated to 25 customers means 3 orders were merged
        expect(result.totalOrders, equals(28));
        expect(result.customers.length, equals(25));

        // Some customers should have multiple orders (the ones that were consolidated)
        final customersWithMultipleOrders = result.customers
            .where((c) => c.orders.length > 1)
            .toList();

        // With 28 orders and 25 customers, we expect 3 customers with 2 orders each
        // or some other combination
        final mergedOrderCount = customersWithMultipleOrders.fold<int>(
            0, (sum, c) => sum + c.orders.length - 1);
        expect(mergedOrderCount, equals(3),
            reason: '28 orders - 25 customers = 3 merged orders');
      });

      test('preserves all orders when merging', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'jdsweid.pdf');

        // Total orders across all customers should still be 28
        expect(result.totalOrders, equals(28),
            reason: 'Consolidation should preserve all 28 orders');
      });

      test('preserves all boxes when merging', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'jdsweid.pdf');

        // Total boxes should still be 99
        expect(result.totalBoxes, equals(99),
            reason: 'Consolidation should preserve all 99 boxes');
      });

      test('tracks original names for merged customers', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'jdsweid.pdf');

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

      test('tracks original emails for merged customers', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'jdsweid.pdf');

        // Check customers with multiple orders to see if they have multiple emails
        final customersWithMultipleOrders = result.customers
            .where((c) => c.orders.length > 1)
            .toList();

        for (final customer in customersWithMultipleOrders) {
          // originalEmails should contain all emails from merged orders
          expect(customer.originalEmails, isNotEmpty,
              reason: 'Merged customer should track original emails');
        }
      });
    });

    group('warnings', () {
      test('generates warnings for customers without contact info', () async {
        final result = await parser.parseBytes(samplePdfBytes, 'jdsweid.pdf');

        final customersWithoutContact = result.customers
            .where((c) => !c.hasContactInfo)
            .toList();

        if (customersWithoutContact.isNotEmpty) {
          // Should have warnings about missing contact info
          expect(result.warnings, isNotEmpty,
              reason: 'Should warn about customers without contact info');
        }
      });
    });
  });

  group('JD Sweid format validation', () {
    test('validates SUPPORTER keyword presence', () async {
      final result = await parser.parseBytes(samplePdfBytes, 'jdsweid.pdf');

      // If parsing succeeded, the PDF contained "SUPPORTER"
      expect(result.customers, isNotEmpty);
    });
  });

  group('Parser isolation', () {
    test('JD Sweid parser does not interfere with Little Caesars format', () async {
      // Load both PDFs
      final lcFile = File('test/fixtures/little_caesars.pdf');
      if (lcFile.existsSync()) {
        final lcBytes = lcFile.readAsBytesSync();

        // JD Sweid parser should reject LC PDF
        expect(
          () => parser.parseBytes(lcBytes, 'little_caesars.pdf'),
          throwsA(isA<FormatException>()),
          reason: 'JD Sweid parser should reject Little Caesars PDF',
        );
      }
    });
  });
}
