import 'package:go_fundraise/core/models/parsed_data.dart';
import 'package:go_fundraise/features/import/parsers/parser_utils.dart';
import 'package:uuid/uuid.dart';

/// Consolidates duplicate customers using deterministic rules:
/// 1. Email (normalized) -> primary key
/// 2. Phone (normalized) -> secondary
/// 3. Name (normalized) -> fallback
class CustomerConsolidator {
  final _uuid = const Uuid();

  /// If true, customers matched by name only won't be flagged for review.
  /// Useful for Little Caesars where sellers don't have contact info.
  final bool nameOnlyMatchIsOk;

  CustomerConsolidator({this.nameOnlyMatchIsOk = false});

  List<ParsedCustomerData> consolidate(List<RawOrderData> rawOrders) {
    // Group by normalized identifiers
    final byEmail = <String, List<RawOrderData>>{};
    final byPhone = <String, List<RawOrderData>>{};
    final byName = <String, List<RawOrderData>>{};
    final noIdentifier = <RawOrderData>[];

    for (final order in rawOrders) {
      final email = normalizeEmail(order.email);
      final phone = normalizePhone(order.phone);
      final name = normalizeName(order.name);

      if (email != null) {
        byEmail.putIfAbsent(email, () => []).add(order);
      } else if (phone != null) {
        byPhone.putIfAbsent(phone, () => []).add(order);
      } else if (name != null) {
        byName.putIfAbsent(name, () => []).add(order);
      } else {
        noIdentifier.add(order);
      }
    }

    // Merge phone groups into email groups where overlap exists
    _mergeBySecondaryKey(byEmail, byPhone, (order) => normalizePhone(order.phone));

    // Merge name groups into phone/email groups where overlap exists
    _mergeBySecondaryKey(byEmail, byName, (order) => normalizeName(order.name));
    _mergeBySecondaryKey(byPhone, byName, (order) => normalizeName(order.name));

    // Merge email groups that share the same normalized name
    // This handles cases like Tina Henhoeffer with different emails but same name
    _mergeGroupsBySharedName(byEmail);

    // Merge phone groups that share the same normalized name
    _mergeGroupsBySharedName(byPhone);

    // Convert groups to customers
    final customers = <ParsedCustomerData>[];

    for (final entry in byEmail.entries) {
      customers.add(_createCustomer(entry.value, entry.key, 'email'));
    }

    for (final entry in byPhone.entries) {
      customers.add(_createCustomer(entry.value, entry.key, 'phone'));
    }

    for (final entry in byName.entries) {
      customers.add(_createCustomer(entry.value, entry.key, 'name'));
    }

    for (final order in noIdentifier) {
      customers.add(_createCustomer([order], null, 'none'));
    }

    // Sort by display name
    customers.sort((a, b) => a.displayName.compareTo(b.displayName));

    return customers;
  }

  void _mergeBySecondaryKey(
    Map<String, List<RawOrderData>> primary,
    Map<String, List<RawOrderData>> secondary,
    String? Function(RawOrderData) getSecondaryKey,
  ) {
    final keysToRemove = <String>[];

    for (final entry in secondary.entries) {
      final secondaryKey = entry.key;
      final orders = entry.value;

      // Check if any order in this group has a primary key match
      for (final order in orders) {
        for (final primaryEntry in primary.entries) {
          final hasMatch = primaryEntry.value.any((o) {
            final key = getSecondaryKey(o);
            return key != null && key == secondaryKey;
          });

          if (hasMatch) {
            // Merge into primary group
            primaryEntry.value.addAll(orders);
            keysToRemove.add(secondaryKey);
            break;
          }
        }
      }
    }

    for (final key in keysToRemove) {
      secondary.remove(key);
    }
  }

  /// Merge groups within a map that share the same normalized name.
  /// This handles cases where customers have different emails/phones but same name
  /// (e.g., Tina Henhoeffer with two different email addresses).
  void _mergeGroupsBySharedName(Map<String, List<RawOrderData>> groups) {
    // Build a map of normalized name -> list of group keys
    final nameToKeys = <String, List<String>>{};

    for (final entry in groups.entries) {
      final key = entry.key;
      final orders = entry.value;

      // Get all normalized names in this group
      final names = orders
          .map((o) => normalizeName(o.name))
          .where((n) => n != null)
          .cast<String>()
          .toSet();

      for (final name in names) {
        nameToKeys.putIfAbsent(name, () => []).add(key);
      }
    }

    // Merge groups that share the same name
    final keysToRemove = <String>{};

    for (final entry in nameToKeys.entries) {
      final keys = entry.value;
      if (keys.length > 1) {
        // Multiple groups share this name - merge them into the first one
        final targetKey = keys.first;
        final targetList = groups[targetKey];
        if (targetList == null) continue;

        for (var i = 1; i < keys.length; i++) {
          final sourceKey = keys[i];
          if (keysToRemove.contains(sourceKey)) continue; // Already merged

          final sourceList = groups[sourceKey];
          if (sourceList != null) {
            targetList.addAll(sourceList);
            keysToRemove.add(sourceKey);
          }
        }
      }
    }

    // Remove merged groups
    for (final key in keysToRemove) {
      groups.remove(key);
    }
  }

  ParsedCustomerData _createCustomer(
    List<RawOrderData> orders,
    String? primaryKey,
    String keyType,
  ) {
    // Collect all unique values
    final names = <String>{};
    final emails = <String>{};
    final phones = <String>{};
    final parsedOrders = <ParsedOrderData>[];
    int totalBoxes = 0;

    for (final order in orders) {
      names.add(order.name);
      if (order.email != null) emails.add(order.email!);
      if (order.phone != null) phones.add(order.phone!);

      final parsedOrder = ParsedOrderData(
        originalOrderId: order.orderId,
        orderDate: order.orderDate,
        paymentStatus: order.paymentStatus,
        buyerName: order.buyerName,
        buyerPhone: order.buyerPhone,
        items: order.items,
        rawText: order.rawText,
      );
      parsedOrders.add(parsedOrder);

      // Count items as boxes (simplified - could be more sophisticated)
      totalBoxes += order.items.fold(0, (sum, item) => sum + item.quantity);
    }

    // Choose display name (prefer the longest/most complete one)
    final displayName = names.reduce((a, b) => a.length >= b.length ? a : b);

    // Choose primary email/phone
    final email = emails.isNotEmpty ? emails.first : null;
    final phone = phones.isNotEmpty ? phones.first : null;

    // Determine if customer needs manual review
    final warnings = <String>[];
    bool needsReview = false;

    if (names.length > 1) {
      warnings.add('Multiple name variations: ${names.join(", ")}');
    }
    if (emails.length > 1) {
      warnings.add('Multiple emails: ${emails.join(", ")}');
    }
    if (phones.length > 1) {
      warnings.add('Multiple phones: ${phones.join(", ")}');
    }
    if (keyType == 'name' && !nameOnlyMatchIsOk) {
      warnings.add('Matched by name only (no email/phone)');
      needsReview = true;
    }
    if (keyType == 'none') {
      warnings.add('No identifiable contact information');
      needsReview = true;
    }

    return ParsedCustomerData(
      id: _uuid.v4(),
      displayName: displayName,
      email: email,
      phone: phone,
      originalNames: names.toList(),
      originalEmails: emails.toList(),
      originalPhones: phones.toList(),
      orders: parsedOrders,
      totalBoxes: totalBoxes > 0 ? totalBoxes : 1, // Minimum 1 box
      warnings: warnings,
      needsReview: needsReview,
    );
  }

  /// Normalize email: lowercase, trim whitespace
  String? normalizeEmail(String? email) {
    if (email == null || email.isEmpty) return null;
    final normalized = email.toLowerCase().trim();
    // Basic email validation
    if (!RegExp(r'^[\w.+-]+@[\w.-]+\.\w+$').hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }

  /// Normalize phone: extract last 10 digits
  String? normalizePhone(String? phone) {
    if (phone == null || phone.isEmpty) return null;
    // Extract digits only
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return null;
    // Take last 10 digits (handles +1, 1-, etc.)
    return digits.substring(digits.length - 10);
  }

  /// Normalize name: lowercase, collapse whitespace, remove punctuation
  String? normalizeName(String? name) {
    if (name == null || name.isEmpty) return null;
    return name
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ') // Collapse whitespace
        .replaceAll(RegExp(r'[^\w\s]'), ''); // Remove punctuation
  }
}
