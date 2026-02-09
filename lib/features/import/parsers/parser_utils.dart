import 'package:go_fundraise/core/models/parsed_data.dart';

/// Raw order data before consolidation
class RawOrderData {
  final String name;
  final String? email;
  final String? phone;
  final String? buyerName;     // Buyer name (for LC: the supporter who placed the order)
  final String? buyerPhone;    // Buyer's phone number
  final String? orderId;
  final String? orderDate;
  final String? paymentStatus;
  final List<ParsedOrderItemData> items;
  final String? rawText;

  RawOrderData({
    required this.name,
    this.email,
    this.phone,
    this.buyerName,
    this.buyerPhone,
    this.orderId,
    this.orderDate,
    this.paymentStatus,
    this.items = const [],
    this.rawText,
  });
}

/// Shared utilities for PDF parsers
class ParserUtils {
  /// Normalize phone number to consistent format (XXX-XXX-XXXX) for storage
  static String normalizePhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    } else if (digits.length == 11 && digits.startsWith('1')) {
      return '${digits.substring(1, 4)}-${digits.substring(4, 7)}-${digits.substring(7)}';
    }
    return phone;
  }

  /// Format phone number for display: (XXX) XXX-XXXX
  static String formatPhoneForDisplay(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) {
      return '(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6)}';
    } else if (digits.length == 11 && digits.startsWith('1')) {
      return '(${digits.substring(1, 4)}) ${digits.substring(4, 7)}-${digits.substring(7)}';
    }
    return phone;
  }

  /// Extract campaign info from PDF text (delivery details only)
  static Map<String, String?> extractCampaignInfo(String text) {
    final result = <String, String?>{
      'deliveryDate': null,
      'deliveryLocation': null,
      'deliveryTime': null,
    };

    // Extract delivery date
    final datePatterns = [
      // YYYY-MM-DD format (JD Sweid uses this)
      RegExp(r'Delivery\s+Date[:\s]+(\d{4}-\d{2}-\d{2})', caseSensitive: false),
      // MM/DD/YYYY or DD/MM/YYYY format
      RegExp(r'Delivery\s+Date[:\s]+(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})',
          caseSensitive: false),
      RegExp(r'Pick\s*up\s+Date[:\s]+(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})',
          caseSensitive: false),
      // "Month Day, Year" format
      RegExp(
          r'Date[:\s]+(\w+\s+\d{1,2},?\s+\d{4})', caseSensitive: false),
    ];

    for (final pattern in datePatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        result['deliveryDate'] = match.group(1)?.trim();
        break;
      }
    }

    // Extract delivery location
    final locationPatterns = [
      RegExp(r'Location[:\s]+([^\n]+)', caseSensitive: false),
      RegExp(r'Pick\s*up\s+Location[:\s]+([^\n]+)', caseSensitive: false),
      RegExp(r'Address[:\s]+([^\n]+)', caseSensitive: false),
    ];

    for (final pattern in locationPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        result['deliveryLocation'] = match.group(1)?.trim();
        break;
      }
    }

    // Extract delivery time
    final timePatterns = [
      RegExp(r'Time[:\s]+(\d{1,2}:\d{2}\s*(?:AM|PM)?(?:\s*-\s*\d{1,2}:\d{2}\s*(?:AM|PM)?)?)',
          caseSensitive: false),
      RegExp(r'Pick\s*up\s+Time[:\s]+([^\n]+)', caseSensitive: false),
    ];

    for (final pattern in timePatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        result['deliveryTime'] = match.group(1)?.trim();
        break;
      }
    }

    return result;
  }

  /// Generate default fundraiser name based on parser type and current date
  static String generateDefaultName(String parserType) {
    final now = DateTime.now();
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '$parserType ${months[now.month - 1]} ${now.year}';
  }
}
