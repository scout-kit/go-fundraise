import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_fundraise/core/database/database.dart';
import 'package:go_fundraise/features/pickup/screens/items_sheet_screen.dart';

/// Result of item picker selection
class ItemPickerResult {
  /// The fundraiser item ID (null if unlinking)
  final String? fundraiserItemId;

  /// Display name for the item (for UI feedback)
  final String displayName;

  const ItemPickerResult({
    this.fundraiserItemId,
    required this.displayName,
  });

  /// Create from an AggregatedFundraiserItem
  factory ItemPickerResult.fromAggregatedItem(AggregatedFundraiserItem item) {
    return ItemPickerResult(
      fundraiserItemId: item.id,
      displayName: item.displayName,
    );
  }

  /// Create an "unlink" result
  static const unlink = ItemPickerResult(
    fundraiserItemId: null,
    displayName: '',
  );
}

/// Shows a bottom sheet for selecting which item a photo belongs to
Future<ItemPickerResult?> showItemPickerSheet({
  required BuildContext context,
  required String fundraiserId,
  String? currentFundraiserItemId,
}) {
  return showModalBottomSheet<ItemPickerResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ItemPickerSheet(
      fundraiserId: fundraiserId,
      currentFundraiserItemId: currentFundraiserItemId,
    ),
  );
}

class _ItemPickerSheet extends ConsumerWidget {
  final String fundraiserId;
  final String? currentFundraiserItemId;

  const _ItemPickerSheet({
    required this.fundraiserId,
    this.currentFundraiserItemId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(itemsSheetProvider(fundraiserId));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.link),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Link to Item',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                // Clear association button (if currently associated)
                if (currentFundraiserItemId != null)
                  TextButton.icon(
                    onPressed: () =>
                        Navigator.pop(context, ItemPickerResult.unlink),
                    icon: const Icon(Icons.link_off),
                    label: const Text('Unlink'),
                  ),
              ],
            ),
          ),
          const Divider(),
          // Items list
          Expanded(
            child: itemsAsync.when(
              data: (items) => items.isEmpty
                  ? const Center(child: Text('No items found'))
                  : ListView.builder(
                      controller: scrollController,
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).padding.bottom,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final isSelected =
                            item.id == currentFundraiserItemId;

                        return ListTile(
                          onTap: () => Navigator.pop(
                            context,
                            ItemPickerResult.fromAggregatedItem(item),
                          ),
                          leading: Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.inventory_2_outlined,
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                          title: Text(
                            item.productName,
                            style: TextStyle(
                              fontWeight:
                                  isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: item.sku != null && item.sku!.isNotEmpty
                              ? Text('SKU: ${item.sku}')
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'x${item.totalQuantity}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.chevron_right,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Error: $error')),
            ),
          ),
        ],
      ),
    );
  }
}
