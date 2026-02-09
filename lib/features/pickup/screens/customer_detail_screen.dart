import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_fundraise/core/database/database.dart';
import 'package:go_fundraise/features/fundraiser/providers/fundraiser_provider.dart';
import 'package:go_fundraise/features/import/parsers/parser_utils.dart';
import 'package:go_fundraise/features/pickup/providers/pickup_provider.dart';
import 'package:go_fundraise/features/photo/providers/photo_provider.dart';
import 'package:go_fundraise/shared/widgets/customer_dialogs.dart';

class CustomerDetailScreen extends ConsumerStatefulWidget {
  final String fundraiserId;
  final String customerId;

  const CustomerDetailScreen({
    super.key,
    required this.fundraiserId,
    required this.customerId,
  });

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  final _initialsController = TextEditingController();

  @override
  void dispose() {
    _initialsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(customerDetailProvider(widget.customerId));

    return detailAsync.when(
      data: (detail) => detail == null
          ? _buildNotFound()
          : _buildContent(context, detail),
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $error')),
      ),
    );
  }

  Widget _buildNotFound() {
    return Scaffold(
      appBar: AppBar(),
      body: const Center(
        child: Text('Customer not found'),
      ),
    );
  }

  Widget _buildContent(BuildContext context, CustomerDetail detail) {
    final isPickedUp = detail.isPickedUp;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Details'),
        actions: [
          if (isPickedUp)
            TextButton(
              onPressed: () => _undoPickup(detail),
              child: const Text('Undo Pickup'),
            ),
          PopupMenuButton<String>(
            onSelected: (value) => _handleMenuAction(value, detail),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit_name',
                child: ListTile(
                  leading: Icon(Icons.edit),
                  title: Text('Edit Name'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'merge',
                child: ListTile(
                  leading: Icon(Icons.merge_type),
                  title: Text('Merge Into...'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Customer header
            _CustomerHeader(detail: detail),

            const SizedBox(height: 24),

            // Consolidated items
            Text(
              'ITEMS',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            _ItemsList(
              items: detail.items,
              totalBoxes: detail.customer.totalBoxes,
              isPickedUp: detail.isPickedUp,
              fundraiserId: widget.fundraiserId,
            ),

            const SizedBox(height: 24),

            // Order history
            if (detail.orders.isNotEmpty) ...[
              Text(
                'ORDER HISTORY',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              _OrderHistory(orders: detail.orders, items: detail.items),
            ],

            const SizedBox(height: 100), // Space for FAB
          ],
        ),
      ),
      floatingActionButton: isPickedUp
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showPickupConfirmation(context, detail),
              icon: const Icon(Icons.check),
              label: const Text('Mark Picked Up'),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  void _showPickupConfirmation(BuildContext context, CustomerDetail detail) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).padding.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Confirm Pickup',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Text(
                'Mark ${detail.customer.displayName} as picked up?',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _initialsController,
                decoration: const InputDecoration(
                  labelText: 'Volunteer initials (optional)',
                  hintText: 'e.g., JD',
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 5,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _confirmPickup(detail);
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Confirm'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmPickup(CustomerDetail detail) async {
    final service = ref.read(pickupServiceProvider);
    await service.markPickedUp(
      detail.customer.id,
      widget.fundraiserId,
      volunteerInitials: _initialsController.text.isEmpty
          ? null
          : _initialsController.text,
    );
    HapticFeedback.mediumImpact();

    // Invalidate stats to get fresh count
    ref.invalidate(fundraiserStatsProvider(widget.fundraiserId));

    // Check if all orders are now picked up
    final stats = await ref.read(fundraiserStatsProvider(widget.fundraiserId).future);

    if (mounted) {
      if (stats.remainingCount == 0 && stats.totalCustomers > 0) {
        // All done! Show celebration
        await _showCelebration();
      }
      if (mounted) {
        context.pop();
      }
    }
  }

  Future<void> _showCelebration() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _CelebrationDialog(),
    );
  }

  Future<void> _undoPickup(CustomerDetail detail) async {
    final service = ref.read(pickupServiceProvider);
    await service.undoPickup(detail.customer.id);
    HapticFeedback.lightImpact();
  }

  void _handleMenuAction(String action, CustomerDetail detail) {
    switch (action) {
      case 'edit_name':
        _editName(detail);
        break;
      case 'merge':
        _mergeCustomer(detail);
        break;
    }
  }

  Future<void> _editName(CustomerDetail detail) async {
    final newName = await EditNameDialog.show(
      context,
      detail.customer.displayName,
    );

    if (newName != null && newName != detail.customer.displayName && mounted) {
      final service = ref.read(pickupServiceProvider);
      await service.renameCustomer(detail.customer.id, newName);

      // Invalidate the provider to refresh the UI with the new name
      ref.invalidate(customerDetailProvider(widget.customerId));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Renamed to $newName'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _mergeCustomer(CustomerDetail detail) async {
    final db = ref.read(databaseProvider);

    // Get all customers for this fundraiser
    final customers = await db.getCustomersByFundraiser(widget.fundraiserId);

    if (customers.length <= 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No other customers to merge with'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // Build customer info list for picker
    final customerInfoList = customers.asMap().entries.map((entry) {
      final c = entry.value;
      return MergeCustomerInfo(
        index: entry.key,
        id: c.id,
        displayName: c.displayName,
        email: c.emailNormalized,
        phone: c.phoneNormalized,
        totalBoxes: c.totalBoxes,
      );
    }).toList();

    // Find source customer info
    final sourceInfo = customerInfoList.firstWhere(
      (c) => c.id == detail.customer.id,
      orElse: () => MergeCustomerInfo(
        index: 0,
        id: detail.customer.id,
        displayName: detail.customer.displayName,
        email: detail.customer.emailNormalized,
        phone: detail.customer.phoneNormalized,
        totalBoxes: detail.customer.totalBoxes,
      ),
    );

    if (!mounted) return;

    // Show target picker
    final target = await MergeTargetPicker.show(
      context,
      source: sourceInfo,
      customers: customerInfoList,
    );

    if (target == null || !mounted) return;

    // Show confirmation dialog
    final confirmed = await MergeConfirmationDialog.show(
      context,
      source: sourceInfo,
      target: target,
    );

    if (confirmed == true && mounted) {
      final service = ref.read(pickupServiceProvider);
      await service.mergeCustomers(detail.customer.id, target.id!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Merged into ${target.displayName}'),
            duration: const Duration(seconds: 3),
          ),
        );
        // Navigate back since this customer no longer exists
        context.pop();
      }
    }
  }
}

class _CustomerHeader extends StatelessWidget {
  final CustomerDetail detail;

  const _CustomerHeader({required this.detail});

  @override
  Widget build(BuildContext context) {
    final customer = detail.customer;
    final isPickedUp = detail.isPickedUp;
    final emails = customer.allEmails;
    final phones = customer.allPhones;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    customer.displayName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                if (isPickedUp)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check,
                          size: 16,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Picked Up',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Display all emails
            for (final email in emails)
              _ContactRow(
                icon: Icons.email,
                value: email,
                onTap: () => _launchEmail(email),
                copyValue: email,
              ),
            // Display all phones
            for (final phone in phones)
              _ContactRow(
                icon: Icons.phone,
                value: ParserUtils.formatPhoneForDisplay(phone),
                onTap: () => _launchPhone(phone),
                copyValue: phone,
              ),
            if (detail.pickupEvent?.volunteerInitials != null)
              _ContactRow(
                icon: Icons.person,
                value: 'Picked up by: ${detail.pickupEvent!.volunteerInitials}',
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchEmail(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Silently fail if no email app available
    }
  }

  Future<void> _launchPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Silently fail if no phone app available
    }
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final VoidCallback? onTap;
  final String? copyValue;

  const _ContactRow({
    required this.icon,
    required this.value,
    this.onTap,
    this.copyValue,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: onTap != null
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap != null || copyValue != null) {
      return InkWell(
        onTap: onTap,
        onLongPress: copyValue != null
            ? () {
                Clipboard.setData(ClipboardData(text: copyValue!));
                HapticFeedback.mediumImpact();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Copied: $copyValue'),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            : null,
        borderRadius: BorderRadius.circular(4),
        child: content,
      );
    }

    return content;
  }
}

/// Consolidated item with fundraiserItemId for photo association
class _ConsolidatedItem {
  final String displayName;
  final String productName;
  final String fundraiserItemId;
  final int quantity;

  _ConsolidatedItem({
    required this.displayName,
    required this.productName,
    required this.fundraiserItemId,
    required this.quantity,
  });
}

class _ItemsList extends ConsumerStatefulWidget {
  final List<OrderItemWithProduct> items;
  final int totalBoxes;
  final bool isPickedUp;
  final String fundraiserId;

  const _ItemsList({
    required this.items,
    required this.totalBoxes,
    this.isPickedUp = false,
    required this.fundraiserId,
  });

  @override
  ConsumerState<_ItemsList> createState() => _ItemsListState();
}

class _ItemsListState extends ConsumerState<_ItemsList> {
  final Set<String> _checkedItems = {};

  /// Consolidate items by fundraiserItemId while preserving photo association
  List<_ConsolidatedItem> get _consolidatedItems {
    final map = <String, _ConsolidatedItem>{};
    for (final item in widget.items) {
      final existing = map[item.fundraiserItemId];
      if (existing != null) {
        map[item.fundraiserItemId] = _ConsolidatedItem(
          displayName: item.displayName,
          productName: item.productName,
          fundraiserItemId: item.fundraiserItemId,
          quantity: existing.quantity + item.quantity,
        );
      } else {
        map[item.fundraiserItemId] = _ConsolidatedItem(
          displayName: item.displayName,
          productName: item.productName,
          fundraiserItemId: item.fundraiserItemId,
          quantity: item.quantity,
        );
      }
    }
    return map.values.toList();
  }

  @override
  void initState() {
    super.initState();
    // Pre-check all items if order is already picked up
    if (widget.isPickedUp) {
      for (final item in widget.items) {
        _checkedItems.add(item.displayName);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _consolidatedItems;
    final allChecked =
        items.isNotEmpty && _checkedItems.length == items.length;

    // Watch photo counts for this fundraiser (keyed by fundraiserItemId)
    final photoCountsAsync =
        ref.watch(photoCountsByItemIdProvider(widget.fundraiserId));

    return Card(
      child: Column(
        children: [
          // Header with total boxes and progress
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  allChecked ? Icons.check_circle : Icons.inventory_2,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  allChecked
                      ? 'ALL ${widget.totalBoxes} BOXES VERIFIED'
                      : '${widget.totalBoxes} BOXES',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          // Item list
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No items listed'),
            )
          else
            ...items.map((item) {
              final isChecked = _checkedItems.contains(item.displayName);

              // Get photo count for this item by fundraiserItemId
              final photoCount = photoCountsAsync.whenOrNull(
                data: (counts) => counts[item.fundraiserItemId] ?? 0,
              ) ?? 0;

              return _ItemRow(
                item: item,
                isChecked: isChecked,
                photoCount: photoCount,
                fundraiserId: widget.fundraiserId,
                onTap: () {
                  setState(() {
                    if (isChecked) {
                      _checkedItems.remove(item.displayName);
                    } else {
                      _checkedItems.add(item.displayName);
                    }
                  });
                  HapticFeedback.selectionClick();
                },
                onViewPhotos: () => _showItemPhotos(context, item),
              );
            }),
        ],
      ),
    );
  }

  void _showItemPhotos(BuildContext context, _ConsolidatedItem item) {
    showDialog(
      context: context,
      builder: (context) => _ItemPhotoDialog(
        fundraiserId: widget.fundraiserId,
        fundraiserItemId: item.fundraiserItemId,
        displayName: item.displayName,
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final _ConsolidatedItem item;
  final bool isChecked;
  final int photoCount;
  final String fundraiserId;
  final VoidCallback onTap;
  final VoidCallback onViewPhotos;

  const _ItemRow({
    required this.item,
    required this.isChecked,
    required this.photoCount,
    required this.fundraiserId,
    required this.onTap,
    required this.onViewPhotos,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Checkbox
            Icon(
              isChecked ? Icons.check_box : Icons.check_box_outline_blank,
              color: isChecked ? Theme.of(context).colorScheme.primary : null,
            ),
            const SizedBox(width: 16),
            // Item name
            Expanded(
              child: Text(
                item.displayName,
                style: TextStyle(
                  decoration: isChecked ? TextDecoration.lineThrough : null,
                  color:
                      isChecked ? Theme.of(context).colorScheme.outline : null,
                ),
              ),
            ),
            // Photo icon (if photo exists) - tap to view
            if (photoCount > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: onViewPhotos,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.photo,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            // Quantity
            Text(
              'x${item.quantity}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isChecked
                        ? Theme.of(context).colorScheme.outline
                        : null,
                  ),
            ),
          ],
        ),
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

/// Displays a single photo with proper sizing for dialog
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

class _OrderHistory extends StatelessWidget {
  final List<Order> orders;
  final List<OrderItemWithProduct> items;

  const _OrderHistory({required this.orders, required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: orders.map((order) {
          // Build subtitle with buyer name and/or date
          String? subtitleText;
          if (order.buyerName != null && order.orderDate != null) {
            subtitleText = '${order.buyerName} | ${order.orderDate}';
          } else if (order.buyerName != null) {
            subtitleText = order.buyerName;
          } else if (order.orderDate != null) {
            subtitleText = order.orderDate;
          }

          return ListTile(
            leading: const Icon(Icons.receipt),
            title: Text('Order #${order.originalOrderId ?? order.id.substring(0, 8)}'),
            subtitle: subtitleText != null ? Text(subtitleText) : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (order.paymentStatus != null)
                  Chip(label: Text(order.paymentStatus!)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => _showOrderDetails(context, order),
          );
        }).toList(),
      ),
    );
  }

  void _showOrderDetails(BuildContext context, Order order) {
    // Filter items for this specific order
    final orderItems = items.where((item) => item.orderId == order.id).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
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
                  const Icon(Icons.receipt),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order #${order.originalOrderId ?? order.id.substring(0, 8)}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        if (order.orderDate != null)
                          Text(
                            order.orderDate!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  if (order.paymentStatus != null)
                    Chip(label: Text(order.paymentStatus!)),
                ],
              ),
            ),
            // Buyer info section
            if (order.buyerName != null || order.buyerPhone != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ordered by',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                            ),
                            if (order.buyerName != null)
                              Text(
                                order.buyerName!,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            if (order.buyerPhone != null)
                              _ContactRow(
                                icon: Icons.phone,
                                value: ParserUtils.formatPhoneForDisplay(order.buyerPhone!),
                                onTap: () => _launchPhone(order.buyerPhone!),
                                copyValue: order.buyerPhone,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const Divider(),
            // Items list
            Expanded(
              child: orderItems.isEmpty
                  ? const Center(child: Text('No items found for this order'))
                  : ListView.builder(
                      controller: scrollController,
                      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
                      itemCount: orderItems.length,
                      itemBuilder: (context, index) {
                        final item = orderItems[index];
                        return ListTile(
                          leading: const Icon(Icons.inventory_2_outlined),
                          title: Text(item.displayName),
                          trailing: Text(
                            'x${item.quantity}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Silently fail if no phone app available
    }
  }
}

/// Celebration dialog with confetti for when all orders are picked up
class _CelebrationDialog extends StatefulWidget {
  const _CelebrationDialog();

  @override
  State<_CelebrationDialog> createState() => _CelebrationDialogState();
}

class _CelebrationDialogState extends State<_CelebrationDialog> {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    // Start confetti immediately
    _confettiController.play();
    // Haptic feedback for celebration
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Dialog content
        AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '🎉',
                style: TextStyle(fontSize: 64),
              ),
              const SizedBox(height: 16),
              Text(
                'Congratulations!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'All orders have been picked up!',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Awesome!'),
              ),
            ],
          ),
        ),
        // Confetti from top center
        Align(
          alignment: Alignment.topCenter,
          child: ConfettiWidget(
            confettiController: _confettiController,
            blastDirection: pi / 2, // straight down
            maxBlastForce: 5,
            minBlastForce: 2,
            emissionFrequency: 0.05,
            numberOfParticles: 20,
            gravity: 0.2,
            shouldLoop: false,
            colors: const [
              Colors.green,
              Colors.blue,
              Colors.pink,
              Colors.orange,
              Colors.purple,
              Colors.yellow,
            ],
          ),
        ),
      ],
    );
  }
}
