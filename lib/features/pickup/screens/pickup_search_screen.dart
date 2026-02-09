import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:go_fundraise/features/fundraiser/providers/fundraiser_provider.dart';
import 'package:go_fundraise/features/import/parsers/parser_utils.dart';
import 'package:go_fundraise/features/photo/providers/photo_provider.dart';
import 'package:go_fundraise/features/pickup/providers/pickup_provider.dart';

class PickupSearchScreen extends ConsumerStatefulWidget {
  final String fundraiserId;

  const PickupSearchScreen({super.key, required this.fundraiserId});

  @override
  ConsumerState<PickupSearchScreen> createState() => _PickupSearchScreenState();
}

class _PickupSearchScreenState extends ConsumerState<PickupSearchScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fundraiserAsync = ref.watch(fundraiserProvider(widget.fundraiserId));
    final customersAsync =
        ref.watch(customersWithPickupProvider(widget.fundraiserId));
    final searchState = ref.watch(pickupSearchProvider(widget.fundraiserId));
    final statsAsync = ref.watch(fundraiserStatsProvider(widget.fundraiserId));
    final photosAsync = ref.watch(photosProvider(widget.fundraiserId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
          tooltip: 'Back to fundraisers',
        ),
        title: fundraiserAsync.when(
          data: (f) => Text(f?.name ?? 'Pickup'),
          loading: () => const Text('Loading...'),
          error: (_, __) => const Text('Error'),
        ),
        actions: [
          photosAsync.when(
            data: (photos) => TextButton.icon(
              onPressed: () =>
                  context.push('/fundraiser/${widget.fundraiserId}/photos'),
              icon: const Icon(Icons.photo_library),
              label: Text('${photos.length}'),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.checklist),
            onPressed: () =>
                context.push('/fundraiser/${widget.fundraiserId}/items'),
            tooltip: 'Items Sheet',
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: () =>
                context.push('/fundraiser/${widget.fundraiserId}/export'),
            tooltip: 'Export',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: 'Search name, phone, or email...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(pickupSearchProvider(widget.fundraiserId)
                                  .notifier)
                              .setQuery('');
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                ref
                    .read(pickupSearchProvider(widget.fundraiserId).notifier)
                    .setQuery(value);
              },
            ),
          ),

          // Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: statsAsync.when(
              data: (stats) => Row(
                children: [
                  _FilterChip(
                    label: 'All: ${stats.totalCustomers}',
                    selected: searchState.filter == PickupFilter.all,
                    onSelected: () => ref
                        .read(
                            pickupSearchProvider(widget.fundraiserId).notifier)
                        .setFilter(PickupFilter.all),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Remaining: ${stats.remainingCount}',
                    selected: searchState.filter == PickupFilter.remaining,
                    onSelected: () => ref
                        .read(
                            pickupSearchProvider(widget.fundraiserId).notifier)
                        .setFilter(PickupFilter.remaining),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Picked Up: ${stats.pickedUpCount}',
                    selected: searchState.filter == PickupFilter.pickedUp,
                    onSelected: () => ref
                        .read(
                            pickupSearchProvider(widget.fundraiserId).notifier)
                        .setFilter(PickupFilter.pickedUp),
                  ),
                ],
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),

          const SizedBox(height: 8),

          // Customer list
          Expanded(
            child: customersAsync.when(
              data: (customers) => customers.isEmpty
                  ? _buildEmptyState(searchState)
                  : _buildCustomerList(customers),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text('Error: $error'),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _takePhoto(context),
        child: const Icon(Icons.camera_alt),
      ),
    );
  }

  Widget _buildEmptyState(PickupSearchState searchState) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            searchState.query.isNotEmpty
                ? Icons.search_off
                : Icons.check_circle_outline,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            searchState.query.isNotEmpty
                ? 'No customers found'
                : searchState.filter == PickupFilter.remaining
                    ? 'All pickups complete!'
                    : 'No customers',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerList(List<CustomerWithPickup> customers) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: customers.length,
      itemBuilder: (context, index) {
        final customer = customers[index];
        return _CustomerTile(
          customer: customer,
          onTap: () => context.push(
            '/fundraiser/${widget.fundraiserId}/customer/${customer.customer.id}',
          ),
        );
      },
    );
  }

  Future<void> _takePhoto(BuildContext context) async {
    final photoService = ref.read(photoServiceProvider);
    await photoService.takePhoto(widget.fundraiserId);
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final CustomerWithPickup customer;
  final VoidCallback onTap;

  const _CustomerTile({
    required this.customer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isPickedUp = customer.isPickedUp;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: isPickedUp ? 0.6 : 1.0,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Status indicator (read-only)
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isPickedUp
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: Border.all(
                      color: isPickedUp
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                      width: 2,
                    ),
                  ),
                  child: isPickedUp
                      ? Icon(
                          Icons.check,
                          size: 20,
                          color: Theme.of(context).colorScheme.onPrimary,
                        )
                      : null,
                ),
                const SizedBox(width: 12),

                // Customer info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.customer.displayName.toUpperCase(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              decoration:
                                  isPickedUp ? TextDecoration.lineThrough : null,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          customer.customer.emailNormalized,
                          customer.customer.phoneNormalized != null
                              ? ParserUtils.formatPhoneForDisplay(customer.customer.phoneNormalized!)
                              : null,
                        ].whereType<String>().join(' | '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Box count
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${customer.customer.totalBoxes}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.inventory_2,
                        size: 18,
                        color:
                            Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
