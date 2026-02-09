import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_fundraise/core/database/database.dart';
import 'package:go_fundraise/features/photo/providers/photo_provider.dart';

/// Provider for aggregated items with verification status
final itemsSheetProvider = FutureProvider.family<List<AggregatedFundraiserItem>, String>(
  (ref, fundraiserId) async {
    final db = ref.watch(databaseProvider);
    return db.getAggregatedItemsByFundraiser(fundraiserId);
  },
);

/// Provider to watch fundraiser items changes
final fundraiserItemsProvider = StreamProvider.family<List<FundraiserItem>, String>(
  (ref, fundraiserId) {
    final db = ref.watch(databaseProvider);
    return db.watchFundraiserItemsByFundraiser(fundraiserId);
  },
);

class ItemsSheetScreen extends ConsumerStatefulWidget {
  final String fundraiserId;

  const ItemsSheetScreen({
    super.key,
    required this.fundraiserId,
  });

  @override
  ConsumerState<ItemsSheetScreen> createState() => _ItemsSheetScreenState();
}

class _ItemsSheetScreenState extends ConsumerState<ItemsSheetScreen> {
  List<AggregatedFundraiserItem> _items = [];
  bool _isLoaded = false;

  @override
  Widget build(BuildContext context) {
    // Watch for fundraiser items changes
    final fundraiserItemsAsync = ref.watch(fundraiserItemsProvider(widget.fundraiserId));

    // Initial load of items with quantities
    final itemsAsync = ref.watch(itemsSheetProvider(widget.fundraiserId));

    return itemsAsync.when(
      data: (items) {
        // Initialize state on first load
        if (!_isLoaded) {
          _items = items;
          _isLoaded = true;
        }

        // Update items when fundraiser items change (for verification status)
        fundraiserItemsAsync.whenData((fundraiserItems) {
          // Create a map of verified status by id
          final verifiedMap = {for (var fi in fundraiserItems) fi.id: fi.verifiedAt != null};

          // Check if any verification status changed
          bool hasChanges = false;
          for (final item in _items) {
            final isNowVerified = verifiedMap[item.id] ?? false;
            if (item.isVerified != isNowVerified) {
              hasChanges = true;
              break;
            }
          }

          if (hasChanges) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                // Refresh the items
                ref.invalidate(itemsSheetProvider(widget.fundraiserId));
              }
            });
          }
        });

        return _buildContent(context);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Items Sheet')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Items Sheet')),
        body: Center(child: Text('Error: $error')),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final verifiedCount = _items.where((i) => i.isVerified).length;
    final allChecked = _items.isNotEmpty && verifiedCount == _items.length;
    final totalQuantity = _items.fold(0, (sum, item) => sum + item.totalQuantity);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Items Sheet'),
        actions: [
          if (verifiedCount > 0)
            TextButton(
              onPressed: _clearAllVerifications,
              child: const Text('Clear All'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Progress header
          Container(
            padding: const EdgeInsets.all(16),
            color: allChecked
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatColumn(
                  label: 'Verified',
                  value: '$verifiedCount/${_items.length}',
                  icon: allChecked ? Icons.check_circle : Icons.pending,
                ),
                _StatColumn(
                  label: 'Total Quantity',
                  value: totalQuantity.toString(),
                  icon: Icons.inventory_2,
                ),
              ],
            ),
          ),
          // Items list
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text('No items found'))
                : _ItemsListView(
                    items: _items,
                    fundraiserId: widget.fundraiserId,
                    onToggleVerification: _toggleVerification,
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleVerification(AggregatedFundraiserItem item) async {
    final db = ref.read(databaseProvider);

    HapticFeedback.selectionClick();

    await db.toggleFundraiserItemVerification(item.id);

    // Update local state immediately for responsiveness
    setState(() {
      final index = _items.indexWhere((i) => i.id == item.id);
      if (index >= 0) {
        _items[index] = AggregatedFundraiserItem(
          id: item.id,
          productName: item.productName,
          sku: item.sku,
          verifiedAt: item.isVerified ? null : DateTime.now().toIso8601String(),
          totalQuantity: item.totalQuantity,
        );
      }
    });
  }

  Future<void> _clearAllVerifications() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Verifications?'),
        content: const Text(
            'This will uncheck all items. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = ref.read(databaseProvider);
      await db.clearAllFundraiserItemVerifications(widget.fundraiserId);

      // Update local state
      setState(() {
        _items = _items.map((item) => AggregatedFundraiserItem(
          id: item.id,
          productName: item.productName,
          sku: item.sku,
          verifiedAt: null,
          totalQuantity: item.totalQuantity,
        )).toList();
      });

      HapticFeedback.mediumImpact();
    }
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatColumn({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Items list view with photo count indicators and camera buttons
class _ItemsListView extends ConsumerWidget {
  final List<AggregatedFundraiserItem> items;
  final String fundraiserId;
  final Function(AggregatedFundraiserItem) onToggleVerification;

  const _ItemsListView({
    required this.items,
    required this.fundraiserId,
    required this.onToggleVerification,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch photo counts for this fundraiser (keyed by fundraiserItemId)
    final photoCountsAsync = ref.watch(photoCountsByItemIdProvider(fundraiserId));

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];

        // Get photo count for this item by its ID
        final photoCount = photoCountsAsync.whenOrNull(
          data: (counts) => counts[item.id] ?? 0,
        ) ?? 0;

        return InkWell(
          onTap: () => onToggleVerification(item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Checkbox
                Icon(
                  item.isVerified ? Icons.check_box : Icons.check_box_outline_blank,
                  color: item.isVerified ? Theme.of(context).colorScheme.primary : null,
                ),
                const SizedBox(width: 16),
                // Item name
                Expanded(
                  child: Text(
                    item.displayName,
                    style: TextStyle(
                      decoration: item.isVerified ? TextDecoration.lineThrough : null,
                      color: item.isVerified ? Theme.of(context).colorScheme.outline : null,
                    ),
                  ),
                ),
                // Photo indicator (tap to view photo)
                if (photoCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: IconButton(
                      onPressed: () => _viewPhoto(context, ref, item),
                      icon: Icon(
                        Icons.photo,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'View reference photo',
                    ),
                  ),
                // Camera button (takes new photo, replaces existing)
                IconButton(
                  onPressed: () => _takePhotoForItem(context, ref, item, photoCount > 0),
                  icon: Icon(
                    photoCount > 0 ? Icons.camera_alt : Icons.camera_alt_outlined,
                  ),
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  tooltip: photoCount > 0 ? 'Replace photo' : 'Take reference photo',
                ),
                // Quantity
                Text(
                  'x${item.totalQuantity}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: item.isVerified
                            ? Theme.of(context).colorScheme.outline
                            : null,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _takePhotoForItem(
    BuildContext context,
    WidgetRef ref,
    AggregatedFundraiserItem item,
    bool hasExisting,
  ) async {
    // If photo exists, confirm replacement
    if (hasExisting) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace Photo?'),
          content: Text(
            'This will replace the existing reference photo for "${item.productName}".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    final photoService = ref.read(photoServiceProvider);
    await photoService.replacePhotoForItem(fundraiserId, item.id);
    // Invalidate photo counts to refresh
    ref.invalidate(photoCountsByItemIdProvider(fundraiserId));
  }

  void _viewPhoto(
    BuildContext context,
    WidgetRef ref,
    AggregatedFundraiserItem item,
  ) {
    showDialog(
      context: context,
      builder: (context) => _ItemPhotoDialog(
        fundraiserId: fundraiserId,
        fundraiserItemId: item.id,
        displayName: item.displayName,
      ),
    );
  }
}

/// Dialog to view a single item's reference photo
class _ItemPhotoDialog extends ConsumerWidget {
  final String fundraiserId;
  final String fundraiserItemId;
  final String displayName;

  const _ItemPhotoDialog({
    required this.fundraiserId,
    required this.fundraiserItemId,
    required this.displayName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoAsync = ref.watch(photoByItemIdProvider(fundraiserItemId));

    return Dialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          // Photo
          photoAsync.when(
            data: (photo) {
              if (photo == null) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No photo available'),
                );
              }
              return _PhotoDisplay(
                photo: photo,
                fundraiserId: fundraiserId,
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(32),
              child: Text('Error: $error'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays a single photo with proper sizing
class _PhotoDisplay extends ConsumerWidget {
  final Photo photo;
  final String fundraiserId;

  const _PhotoDisplay({
    required this.photo,
    required this.fundraiserId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoService = ref.read(photoServiceProvider);

    return FutureBuilder<String>(
      future: photoService.getPhotoPath(fundraiserId, photo.filePath),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          );
        }

        final path = snapshot.data!;
        final isDataUrl = photoService.isDataUrl(path);

        Widget imageWidget;
        if (isDataUrl) {
          final base64Data = path.split(',').last;
          final bytes = base64Decode(base64Data);
          imageWidget = Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image,
              size: 64,
            ),
          );
        } else {
          imageWidget = Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image,
              size: 64,
            ),
          );
        }

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
            child: imageWidget,
          ),
        );
      },
    );
  }
}
