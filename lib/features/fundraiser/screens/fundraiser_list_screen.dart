import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:go_fundraise/core/database/database.dart';
import 'package:go_fundraise/features/fundraiser/providers/fundraiser_provider.dart';

class FundraiserListScreen extends ConsumerWidget {
  const FundraiserListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fundraisersAsync = ref.watch(fundraisersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Go Fundraise'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelp(context),
          ),
        ],
      ),
      body: fundraisersAsync.when(
        data: (fundraisers) => fundraisers.isEmpty
            ? _buildEmptyState(context)
            : _buildFundraiserList(context, ref, fundraisers),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(fundraisersProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/import'),
        icon: const Icon(Icons.add),
        label: const Text('Import'),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 80,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 24),
          Text(
            'No Fundraisers Yet',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Import a PDF or CSV to get started',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => context.push('/import'),
            icon: const Icon(Icons.upload_file),
            label: const Text('Import Fundraiser'),
          ),
        ],
      ),
    );
  }

  Widget _buildFundraiserList(
    BuildContext context,
    WidgetRef ref,
    List<Fundraiser> fundraisers,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: fundraisers.length,
      itemBuilder: (context, index) {
        final fundraiser = fundraisers[index];
        return _FundraiserTile(
          fundraiser: fundraiser,
          onTap: () => context.push('/fundraiser/${fundraiser.id}'),
          onDelete: () => _confirmDelete(context, ref, fundraiser),
          onExport: () => context.push('/fundraiser/${fundraiser.id}/export'),
        );
      },
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, Fundraiser fundraiser) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Fundraiser?'),
        content: Text(
          'This will permanently delete "${fundraiser.name}" and all associated data including photos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(fundraiserServiceProvider)
                  .deleteFundraiser(fundraiser.id);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Go Fundraise'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('This app helps track pickups for fundraisers.'),
              SizedBox(height: 16),
              Text('How to use:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('1. Import a PDF or CSV file with customer orders'),
              Text('2. Search for customers during pickup'),
              Text('3. Mark orders as picked up'),
              Text('4. Take photos for reference'),
              Text('5. Export pickup log when done'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _FundraiserTile extends ConsumerWidget {
  final Fundraiser fundraiser;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onExport;

  const _FundraiserTile({
    required this.fundraiser,
    required this.onTap,
    required this.onDelete,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(fundraiserStatsProvider(fundraiser.id));

    return Dismissible(
      key: Key(fundraiser.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Theme.of(context).colorScheme.error,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        fundraiser.name,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.file_download_outlined),
                      onPressed: onExport,
                      tooltip: 'Export',
                    ),
                  ],
                ),
                if (fundraiser.deliveryDate != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    fundraiser.deliveryDate!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
                const SizedBox(height: 12),
                statsAsync.when(
                  data: (stats) => _buildStatsRow(context, stats),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Error loading stats'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context, FundraiserStats stats) {
    final isComplete = stats.remainingCount == 0 && stats.totalCustomers > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${stats.totalCustomers} customers',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: 8),
            Text(
              '${stats.pickedUpCount} picked up',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(width: 8),
            if (isComplete)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Complete',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                ),
              )
            else
              Text(
                '${stats.remainingCount} remaining',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: stats.progressPercent,
            minHeight: 6,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}
