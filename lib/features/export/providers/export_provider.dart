import 'dart:convert';
import 'dart:io';

import 'package:android_path_provider/android_path_provider.dart';
import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_fundraise/core/database/database.dart';

class ExportState {
  final bool isExporting;
  final String? error;
  final String? lastExportPath;

  const ExportState({
    this.isExporting = false,
    this.error,
    this.lastExportPath,
  });

  ExportState copyWith({
    bool? isExporting,
    String? error,
    String? lastExportPath,
  }) {
    return ExportState(
      isExporting: isExporting ?? this.isExporting,
      error: error,
      lastExportPath: lastExportPath ?? this.lastExportPath,
    );
  }
}

class ExportNotifier extends StateNotifier<ExportState> {
  final AppDatabase _db;

  ExportNotifier(this._db) : super(const ExportState());

  Future<void> exportToCsv(
    String fundraiserId, {
    bool includeCustomerDetails = true,
    bool includeItemBreakdown = true,
    bool includeTimestamps = true,
    bool includeVolunteerInitials = true,
  }) async {
    state = state.copyWith(isExporting: true, error: null);

    try {
      // Get fundraiser info
      final fundraiser = await _db.getFundraiserById(fundraiserId);
      if (fundraiser == null) {
        throw Exception('Fundraiser not found');
      }

      // Get all customers and pickup events
      final customers = await _db.getCustomersByFundraiser(fundraiserId);
      final pickupEvents = await _db.getPickupEventsByFundraiser(fundraiserId);
      final pickupMap = {for (var e in pickupEvents) e.customerId: e};

      // Build CSV rows
      final rows = <List<dynamic>>[];

      // Header row
      final headers = <String>['Name'];
      if (includeCustomerDetails) {
        headers.addAll(['Email', 'Phone', 'Buyer(s)']);
      }
      headers.addAll(['Total Items', 'Status']);
      if (includeTimestamps) {
        headers.add('Pickup Time');
      }
      if (includeVolunteerInitials) {
        headers.add('Volunteer');
      }
      if (includeItemBreakdown) {
        headers.addAll(['Item', 'Qty']);
      }
      rows.add(headers);

      // Data rows: one row per consolidated item when item breakdown is on,
      // otherwise one row per customer. Customer-level fields repeat on every
      // item row so spreadsheet sort/filter still works (Square-style).
      for (final customer in customers) {
        final pickup = pickupMap[customer.id];
        final isPickedUp = pickup?.status == 'picked_up';

        String buyersCell = '';
        if (includeCustomerDetails) {
          final orders = await _db.getOrdersByCustomer(customer.id);
          buyersCell = _formatBuyers(orders);
        }

        List<dynamic> buildBaseRow() {
          final row = <dynamic>[customer.displayName];
          if (includeCustomerDetails) {
            row.addAll([
              customer.emailNormalized ?? '',
              _formatPhone(customer.phoneNormalized),
              buyersCell,
            ]);
          }
          row.addAll([
            customer.totalBoxes,
            isPickedUp ? 'Picked Up' : 'Remaining',
          ]);
          if (includeTimestamps) {
            row.add(
              pickup?.pickedUpAt != null
                  ? _formatTimestamp(pickup!.pickedUpAt!)
                  : '',
            );
          }
          if (includeVolunteerInitials) {
            row.add(pickup?.volunteerInitials ?? '');
          }
          return row;
        }

        if (includeItemBreakdown) {
          final items =
              await _db.getOrderItemsWithProductByCustomer(customer.id);
          final consolidated = _consolidateItems(items);
          if (consolidated.isEmpty) {
            rows.add(buildBaseRow()..addAll(['', '']));
          } else {
            for (final item in consolidated) {
              rows.add(buildBaseRow()..addAll([item.displayName, item.quantity]));
            }
          }
        } else {
          rows.add(buildBaseRow());
        }
      }

      // Convert to CSV
      final csv = const ListToCsvConverter().convert(rows);

      // Save to Downloads folder (accessible via file manager and file picker)
      String dirPath;
      if (!kIsWeb && Platform.isAndroid) {
        dirPath = await AndroidPathProvider.downloadsPath;
      } else {
        final dir = await getApplicationDocumentsDirectory();
        dirPath = dir.path;
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final safeName = fundraiser.name
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(' ', '_');
      final fileName = '${safeName}_pickup_log_$timestamp.csv';
      final filePath = '$dirPath/$fileName';

      final file = File(filePath);
      await file.writeAsString(csv);

      state = state.copyWith(
        isExporting: false,
        lastExportPath: filePath,
      );

      // Don't auto-share - let the UI handle it
    } catch (e) {
      state = state.copyWith(
        isExporting: false,
        error: e.toString(),
      );
    }
  }

  String _formatPhone(String? phone) {
    if (phone == null || phone.isEmpty) return '';
    if (phone.length == 10) {
      return '(${phone.substring(0, 3)}) ${phone.substring(3, 6)}-${phone.substring(6)}';
    }
    return phone;
  }

  /// Format the Buyer(s) cell from a customer's orders.
  /// Each unique buyer appears once as "Name (XXX) XXX-XXXX", joined with "; ".
  /// For formats like Little Caesars the customer has no phone of their own,
  /// so this preserves the buyer contacts that only live on the order.
  String _formatBuyers(List<Order> orders) {
    final seen = <String>{};
    final parts = <String>[];
    for (final order in orders) {
      final entry = _formatBuyerEntry(order.buyerName, order.buyerPhone);
      if (entry.isEmpty || !seen.add(entry)) continue;
      parts.add(entry);
    }
    return parts.join('; ');
  }

  String _formatBuyerEntry(String? name, String? phone) {
    final trimmedName = name?.trim();
    final formattedPhone = _formatPhone(phone);
    final hasName = trimmedName != null && trimmedName.isNotEmpty;
    final hasPhone = formattedPhone.isNotEmpty;
    if (hasName && hasPhone) return '$trimmedName $formattedPhone';
    if (hasName) return trimmedName;
    return formattedPhone;
  }

  /// Merge items across a customer's orders by fundraiserItemId so the
  /// exported rows match the in-app pickup checklist (a scout who bought 2
  /// oranges in one order and 3 in another shows as "Oranges x5").
  List<_ConsolidatedExportItem> _consolidateItems(
    List<OrderItemWithProduct> items,
  ) {
    final map = <String, _ConsolidatedExportItem>{};
    final order = <String>[];
    for (final item in items) {
      final existing = map[item.fundraiserItemId];
      if (existing != null) {
        map[item.fundraiserItemId] = _ConsolidatedExportItem(
          displayName: existing.displayName,
          quantity: existing.quantity + item.quantity,
        );
      } else {
        map[item.fundraiserItemId] = _ConsolidatedExportItem(
          displayName: item.displayName,
          quantity: item.quantity,
        );
        order.add(item.fundraiserItemId);
      }
    }
    return [for (final id in order) map[id]!];
  }

  String _formatTimestamp(String isoTimestamp) {
    try {
      final dt = DateTime.parse(isoTimestamp);
      return DateFormat('M/d/yyyy h:mm a').format(dt);
    } catch (_) {
      return isoTimestamp;
    }
  }

  /// Share the last exported file
  Future<void> shareFile(String fundraiserName) async {
    final path = state.lastExportPath;
    if (path == null) return;

    await Share.shareXFiles(
      [XFile(path)],
      subject: '$fundraiserName - Pickup Log',
    );
  }

  /// Open the last exported file in an external app
  Future<bool> openFile() async {
    final path = state.lastExportPath;
    if (path == null) return false;

    try {
      final result = await OpenFilex.open(path, type: 'text/csv');
      return result.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }

  /// Clear the export state
  void clearExport() {
    state = const ExportState();
  }

  /// Export fundraiser data to JSON for backup/restore
  Future<void> exportToJson(String fundraiserId) async {
    state = state.copyWith(isExporting: true, error: null);

    try {
      // Get all fundraiser data
      final fundraiser = await _db.getFundraiserById(fundraiserId);
      if (fundraiser == null) {
        throw Exception('Fundraiser not found');
      }

      final customers = await _db.getCustomersByFundraiser(fundraiserId);
      final pickupEvents = await _db.getPickupEventsByFundraiser(fundraiserId);
      final fundraiserItems = await _db.getFundraiserItemsByFundraiser(fundraiserId);

      // Get orders and order items for each customer
      final ordersData = <Map<String, dynamic>>[];
      for (final customer in customers) {
        final orders = await _db.getOrdersByCustomer(customer.id);
        for (final order in orders) {
          final orderItems = await _db.getOrderItemsByOrder(order.id);
          ordersData.add({
            'id': order.id,
            'customerId': order.customerId,
            'fundraiserId': order.fundraiserId,
            'orderId': order.originalOrderId,
            'orderDate': order.orderDate,
            'paymentStatus': order.paymentStatus,
            'buyerName': order.buyerName,
            'buyerPhone': order.buyerPhone,
            'items': orderItems.map((item) => {
              'id': item.id,
              'orderId': item.orderId,
              'fundraiserItemId': item.fundraiserItemId,
              'quantity': item.quantity,
              'unitPriceCents': item.unitPriceCents,
              'totalPriceCents': item.totalPriceCents,
              'sortOrder': item.sortOrder,
            }).toList(),
          });
        }
      }

      // Build export data structure
      final exportData = {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'fundraiser': {
          'id': fundraiser.id,
          'name': fundraiser.name,
          'deliveryDate': fundraiser.deliveryDate,
          'deliveryLocation': fundraiser.deliveryLocation,
          'deliveryTime': fundraiser.deliveryTime,
          'sourceFileName': fundraiser.sourceFileName,
          'sourceType': fundraiser.sourceType,
          'importedAt': fundraiser.importedAt,
          'createdAt': fundraiser.createdAt,
        },
        'fundraiserItems': fundraiserItems.map((item) => {
          'id': item.id,
          'fundraiserId': item.fundraiserId,
          'productName': item.productName,
          'sku': item.sku,
          'verifiedAt': item.verifiedAt,
          'createdAt': item.createdAt,
        }).toList(),
        'customers': customers.map((c) => {
          'id': c.id,
          'fundraiserId': c.fundraiserId,
          'displayName': c.displayName,
          'emailNormalized': c.emailNormalized,
          'phoneNormalized': c.phoneNormalized,
          'originalNames': c.originalNames,
          'originalEmails': c.originalEmails,
          'originalPhones': c.originalPhones,
          'totalBoxes': c.totalBoxes,
          'createdAt': c.createdAt,
        }).toList(),
        'orders': ordersData,
        'pickupEvents': pickupEvents.map((p) => {
          'id': p.id,
          'customerId': p.customerId,
          'fundraiserId': p.fundraiserId,
          'status': p.status,
          'pickedUpAt': p.pickedUpAt,
          'volunteerInitials': p.volunteerInitials,
          'notes': p.notes,
          'createdAt': p.createdAt,
        }).toList(),
      };

      // Convert to JSON and compress with gzip
      final jsonString = jsonEncode(exportData);
      final jsonBytes = utf8.encode(jsonString);
      final compressedBytes = GZipEncoder().encode(jsonBytes);

      if (compressedBytes == null || compressedBytes.isEmpty) {
        throw Exception('Failed to compress backup data');
      }

      // Save to Downloads folder (accessible via file manager and file picker)
      String dirPath;
      if (!kIsWeb && Platform.isAndroid) {
        dirPath = await AndroidPathProvider.downloadsPath;
      } else {
        final dir = await getApplicationDocumentsDirectory();
        dirPath = dir.path;
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final safeName = fundraiser.name
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(' ', '_');
      final fileName = '${safeName}_backup_$timestamp.sfb';
      final filePath = '$dirPath/$fileName';

      final file = File(filePath);
      await file.writeAsBytes(compressedBytes);

      // Verify file was created
      if (!await file.exists()) {
        throw Exception('Failed to create backup file');
      }

      state = state.copyWith(
        isExporting: false,
        lastExportPath: filePath,
      );
    } catch (e) {
      state = state.copyWith(
        isExporting: false,
        error: e.toString(),
      );
    }
  }

  /// Open backup file
  Future<bool> openBackupFile() async {
    final path = state.lastExportPath;
    if (path == null) return false;

    try {
      // Use octet-stream for binary files
      final result = await OpenFilex.open(path, type: 'application/octet-stream');
      return result.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }
}

final exportProvider = StateNotifierProvider<ExportNotifier, ExportState>((ref) {
  final db = ref.watch(databaseProvider);
  return ExportNotifier(db);
});

class _ConsolidatedExportItem {
  final String displayName;
  final int quantity;
  const _ConsolidatedExportItem({
    required this.displayName,
    required this.quantity,
  });
}
