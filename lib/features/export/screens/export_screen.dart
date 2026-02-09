import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_fundraise/features/export/providers/export_provider.dart';
import 'package:go_fundraise/features/fundraiser/providers/fundraiser_provider.dart';

class ExportScreen extends ConsumerStatefulWidget {
  final String fundraiserId;

  const ExportScreen({super.key, required this.fundraiserId});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  bool _includeCustomerDetails = true;
  bool _includeItemBreakdown = true;
  bool _includeTimestamps = true;
  bool _includeVolunteerInitials = true;

  @override
  Widget build(BuildContext context) {
    final fundraiserAsync = ref.watch(fundraiserProvider(widget.fundraiserId));
    final statsAsync = ref.watch(fundraiserStatsProvider(widget.fundraiserId));
    final exportState = ref.watch(exportProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Export Pickup Log'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Fundraiser info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    fundraiserAsync.when(
                      data: (f) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f?.name ?? 'Unknown',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (f?.deliveryDate != null)
                            Text(
                              'Date: ${f!.deliveryDate}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                        ],
                      ),
                      loading: () => const Text('Loading...'),
                      error: (_, __) => const Text('Error loading'),
                    ),
                    const SizedBox(height: 16),
                    statsAsync.when(
                      data: (stats) => Column(
                        children: [
                          _StatRow(
                            label: 'Total Customers',
                            value: stats.totalCustomers.toString(),
                          ),
                          _StatRow(
                            label: 'Picked Up',
                            value: stats.pickedUpCount.toString(),
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          _StatRow(
                            label: 'Remaining',
                            value: stats.remainingCount.toString(),
                            color: stats.remainingCount > 0
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: stats.progressPercent,
                              minHeight: 8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${(stats.progressPercent * 100).round()}% complete',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      loading: () => const CircularProgressIndicator(),
                      error: (_, __) => const Text('Error'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Export options
            Text(
              'Include in Export',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Customer details'),
                    subtitle: const Text('Name, email, phone'),
                    value: _includeCustomerDetails,
                    onChanged: (v) => setState(() => _includeCustomerDetails = v),
                  ),
                  SwitchListTile(
                    title: const Text('Item breakdown'),
                    subtitle: const Text('Products and quantities'),
                    value: _includeItemBreakdown,
                    onChanged: (v) => setState(() => _includeItemBreakdown = v),
                  ),
                  SwitchListTile(
                    title: const Text('Pickup timestamps'),
                    subtitle: const Text('When each order was picked up'),
                    value: _includeTimestamps,
                    onChanged: (v) => setState(() => _includeTimestamps = v),
                  ),
                  SwitchListTile(
                    title: const Text('Volunteer initials'),
                    subtitle: const Text('Who handled each pickup'),
                    value: _includeVolunteerInitials,
                    onChanged: (v) => setState(() => _includeVolunteerInitials = v),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Export buttons
            if (exportState.isExporting)
              const Center(child: CircularProgressIndicator())
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _exportCsv,
                    icon: const Icon(Icons.table_chart),
                    label: const Text('Export CSV (Spreadsheet)'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _exportJson,
                    icon: const Icon(Icons.backup),
                    label: const Text('Export Backup (Re-importable)'),
                  ),
                ],
              ),

            if (exportState.error != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          exportState.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Format info
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Export Format',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'CSV file compatible with Excel, Google Sheets, and other spreadsheet applications.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCsv() async {
    final notifier = ref.read(exportProvider.notifier);
    await notifier.exportToCsv(
          widget.fundraiserId,
          includeCustomerDetails: _includeCustomerDetails,
          includeItemBreakdown: _includeItemBreakdown,
          includeTimestamps: _includeTimestamps,
          includeVolunteerInitials: _includeVolunteerInitials,
        );

    // Check if export was successful
    final state = ref.read(exportProvider);
    if (state.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: ${state.error}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } else if (state.lastExportPath != null && mounted) {
      _showCsvSuccess(state.lastExportPath!);
    }
  }

  void _showCsvSuccess(String filePath) {
    final fileName = filePath.split('/').last;
    final fundraiserAsync = ref.read(fundraiserProvider(widget.fundraiserId));
    final fundraiserName = fundraiserAsync.valueOrNull?.name ?? 'Fundraiser';

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CSV Exported',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            fileName,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder,
                          size: 20,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Downloads/',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Open in App'),
                subtitle: const Text('Open with Sheets, Excel, etc.'),
                onTap: () {
                  Navigator.pop(context);
                  _openFile();
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Share'),
                subtitle: const Text('Send via email, messages, etc.'),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(exportProvider.notifier).shareFile(fundraiserName);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportJson() async {
    final notifier = ref.read(exportProvider.notifier);
    await notifier.exportToJson(widget.fundraiserId);

    // Check if export was successful
    final state = ref.read(exportProvider);
    if (state.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup failed: ${state.error}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } else if (state.lastExportPath != null && mounted) {
      _showBackupSuccess(state.lastExportPath!);
    }
  }

  void _showBackupSuccess(String filePath) {
    final fileName = filePath.split('/').last;
    final fundraiserAsync = ref.read(fundraiserProvider(widget.fundraiserId));
    final fundraiserName = fundraiserAsync.valueOrNull?.name ?? 'Fundraiser';

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Backup Created',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            fileName,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder,
                          size: 20,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Downloads/',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Share Backup'),
                subtitle: const Text('Send via email, save to cloud, etc.'),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(exportProvider.notifier).shareFile('$fundraiserName - Backup');
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openFile() async {
    final success = await ref.read(exportProvider.notifier).openFile();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open file. Try sharing instead.'),
        ),
      );
    }
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatRow({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
