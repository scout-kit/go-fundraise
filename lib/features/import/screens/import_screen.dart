import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:go_fundraise/core/models/parsed_data.dart';
import 'package:go_fundraise/features/import/parsers/backup_parser.dart';
import 'package:go_fundraise/features/import/providers/import_provider.dart';
import 'package:go_fundraise/shared/widgets/customer_dialogs.dart';

// Platform-specific imports
import 'import_screen_stub.dart'
    if (dart.library.io) 'import_screen_native.dart'
    if (dart.library.html) 'import_screen_web.dart' as platform;

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Reset import state when entering screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(importProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final importState = ref.watch(importProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Fundraiser'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Import Customer Data',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Select your fundraiser type to import orders.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
            const SizedBox(height: 32),
            if (importState.isLoading) ...[
              _buildLoadingState(importState.progress),
            ] else if (importState.error != null) ...[
              _buildErrorState(importState.error!),
            ] else if (importState.backupData != null) ...[
              _buildBackupPreview(importState),
            ] else if (importState.parsedData != null) ...[
              _buildParsedPreview(importState),
            ] else ...[
              _buildFileSelection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(double progress) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: CircularProgressIndicator(
                value: progress > 0 ? progress : null,
                strokeWidth: 6,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              progress > 0
                  ? 'Processing... ${(progress * 100).round()}%'
                  : 'Reading file...',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Import Failed',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => ref.read(importProvider.notifier).reset(),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileSelection() {
    return Expanded(
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),

            // 1. CSV Import (first to not get lost)
            _ImportOptionCard(
              icon: Icons.table_chart,
              title: 'CSV Import',
              subtitle: 'Import from spreadsheet format',
              onTap: () => _pickFile(ImportFormat.csv, ['csv']),
              trailing: TextButton.icon(
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Template'),
                onPressed: _downloadCsvTemplate,
              ),
            ),

            const SizedBox(height: 16),

            // 2. JD Sweid
            _ImportOptionCard(
              icon: Icons.picture_as_pdf,
              title: 'JD Sweid',
              subtitle: 'Import JD Sweid fundraiser PDF',
              onTap: () => _pickFile(ImportFormat.jdSweid, ['pdf']),
            ),

            const SizedBox(height: 16),

            // 3. Little Caesars
            _ImportOptionCard(
              icon: Icons.picture_as_pdf,
              title: 'Little Caesars',
              subtitle: 'Import Little Caesars fundraiser PDF',
              onTap: () => _pickFile(ImportFormat.littleCaesars, ['pdf']),
            ),

            const SizedBox(height: 24),

            // Divider with "or"
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'or',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),

            const SizedBox(height: 24),

            // 4. Restore from backup
            _ImportOptionCard(
              icon: Icons.restore,
              title: 'Restore Backup',
              subtitle: 'Import a previously exported backup file (.sfb)',
              onTap: _pickBackupFile,
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildParsedPreview(ImportState state) {
    final data = state.parsedData!;

    // Initialize name controller only on first load (when empty)
    // Don't overwrite user's changes if they've typed something
    if (_nameController.text.isEmpty && data.name.isNotEmpty) {
      _nameController.text = data.name;
    }

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        data.sourceType == 'pdf'
                            ? Icons.picture_as_pdf
                            : Icons.table_chart,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _nameController,
                              style: Theme.of(context).textTheme.titleMedium,
                              decoration: const InputDecoration(
                                labelText: 'Fundraiser Name',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              data.sourceFileName,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatItem(
                        label: 'Customers',
                        value: data.customers.length.toString(),
                      ),
                      _StatItem(
                        label: 'Orders',
                        value: data.totalOrders.toString(),
                      ),
                      _StatItem(
                        label: 'Total Boxes',
                        value: data.totalBoxes.toString(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (data.warnings.isNotEmpty || data.errors.isNotEmpty) ...[
            const SizedBox(height: 16),
            _WarningsCard(warnings: data.warnings, errors: data.errors),
          ],
          const SizedBox(height: 16),
          Text(
            'Customers (${data.customers.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Card(
              child: ListView.builder(
                itemCount: data.customers.length,
                itemBuilder: (context, index) {
                  final customer = data.customers[index];
                  return ListTile(
                    leading: customer.needsReview
                        ? Icon(Icons.warning,
                            color: Theme.of(context).colorScheme.error)
                        : const Icon(Icons.person),
                    title: Text(customer.displayName),
                    subtitle: Text(
                      [customer.email, customer.phone]
                          .whereType<String>()
                          .join(' | '),
                    ),
                    trailing: Text('${customer.totalBoxes} box'),
                    onTap: () => _showCustomerOptions(index, data),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => ref.read(importProvider.notifier).reset(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: data.customers.isEmpty ? null : _saveAndContinue,
                    child: const Text('Import & Continue'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupPreview(ImportState state) {
    final backup = state.backupData!;

    // Initialize name controller only on first load
    if (_nameController.text.isEmpty && backup.fundraiser.name.isNotEmpty) {
      _nameController.text = backup.fundraiser.name;
    }

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.restore,
                        color: Theme.of(context).colorScheme.primary,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _nameController,
                              style: Theme.of(context).textTheme.titleMedium,
                              decoration: const InputDecoration(
                                labelText: 'Fundraiser Name',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'File: ${backup.sourceFileName}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (backup.exportedAt != null)
                              Text(
                                'Created: ${_formatBackupDate(backup.exportedAt!)}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.outline,
                                    ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatItem(
                        label: 'Customers',
                        value: backup.customerCount.toString(),
                      ),
                      _StatItem(
                        label: 'Orders',
                        value: backup.orderCount.toString(),
                      ),
                      _StatItem(
                        label: 'Picked Up',
                        value: backup.pickedUpCount.toString(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Backup info card
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Restore includes:',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '• All customers and orders\n'
                          '• Product items and quantities\n'
                          '• Pickup status (${backup.pickedUpCount} already picked up)',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),
          Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => ref.read(importProvider.notifier).reset(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _restoreBackup,
                    icon: const Icon(Icons.restore),
                    label: const Text('Restore Backup'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatBackupDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.month}/${dt.day}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }

  Future<void> _restoreBackup() async {
    try {
      final customName = _nameController.text.trim();
      final fundraiserId = await ref.read(importProvider.notifier).saveBackupToDatabase(
            name: customName.isNotEmpty ? customName : null,
          );
      if (mounted) {
        context.go('/fundraiser/$fundraiserId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to restore: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _pickBackupFile() async {
    // Use FileType.any for backup files since Android doesn't recognize .sfb
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.single;
      final fileName = file.name;
      final Uint8List? bytes = file.bytes;

      // Validate file extension
      if (!fileName.toLowerCase().endsWith('.sfb')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please select a .sfb backup file'),
            ),
          );
        }
        return;
      }

      if (bytes != null) {
        await ref.read(importProvider.notifier).parseFileBytes(
              bytes,
              fileName,
              ImportFormat.backup,
            );
      } else if (!kIsWeb && file.path != null) {
        await ref.read(importProvider.notifier).parseFilePath(
              file.path!,
              ImportFormat.backup,
            );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read file')),
          );
        }
      }
    }
  }

  Future<void> _pickFile(ImportFormat format, List<String> extensions) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true, // Required for web to get bytes
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.single;
      final fileName = file.name;
      final Uint8List? bytes = file.bytes;

      if (bytes != null) {
        // Use bytes directly (works on all platforms)
        await ref.read(importProvider.notifier).parseFileBytes(
          bytes,
          fileName,
          format,
        );
      } else if (!kIsWeb && file.path != null) {
        // Fallback for native platforms if bytes not available
        await ref.read(importProvider.notifier).parseFilePath(
          file.path!,
          format,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read file')),
          );
        }
      }
    }
  }

  Future<void> _downloadCsvTemplate() async {
    final csvContent = '''Name,Email,Phone,Order ID,Order Date,Product,Quantity,Price,Status
John Smith,john@example.com,555-123-4567,ORD001,2026-02-01,Pepperoni Pizza Kit,2,62.00,paid
John Smith,john@example.com,555-123-4567,ORD001,2026-02-01,Cheese Pizza Kit,1,31.00,paid
Jane Doe,jane@example.com,555-987-6543,ORD002,2026-02-02,Cookie Dough,3,45.00,unpaid''';

    try {
      final filePath = await platform.downloadCsvTemplate(csvContent);

      if (mounted && filePath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Template saved to $filePath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to download template: $e')),
        );
      }
    }
  }

  Future<void> _showCustomerOptions(int index, ParsedFundraiserData data) async {
    final customer = data.customers[index];
    final canMerge = data.customers.length > 1;

    final action = await CustomerOptionsSheet.show(
      context,
      customerName: customer.displayName,
      canMerge: canMerge,
    );

    if (action == null || !mounted) return;

    switch (action) {
      case CustomerAction.editName:
        await _editCustomerName(index, customer.displayName);
        break;
      case CustomerAction.merge:
        await _mergeCustomer(index, data);
        break;
    }
  }

  Future<void> _editCustomerName(int index, String currentName) async {
    final newName = await EditNameDialog.show(context, currentName);
    if (newName != null && newName != currentName) {
      ref.read(importProvider.notifier).renameCustomer(index, newName);
    }
  }

  Future<void> _mergeCustomer(int sourceIndex, ParsedFundraiserData data) async {
    final source = data.customers[sourceIndex];

    // Build customer list for picker
    final customerInfoList = data.customers.asMap().entries.map((entry) {
      final c = entry.value;
      return MergeCustomerInfo(
        index: entry.key,
        displayName: c.displayName,
        email: c.email,
        phone: c.phone,
        totalBoxes: c.totalBoxes,
      );
    }).toList();

    final sourceInfo = customerInfoList[sourceIndex];

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

    if (confirmed == true) {
      ref.read(importProvider.notifier).mergeCustomers(sourceIndex, target.index);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Merged ${source.displayName} into ${target.displayName}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _saveAndContinue() async {
    try {
      // Use the edited name from the text field
      final customName = _nameController.text.trim();
      final fundraiserId = await ref
          .read(importProvider.notifier)
          .saveToDatabase(name: customName.isNotEmpty ? customName : null);
      if (mounted) {
        context.go('/fundraiser/$fundraiserId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

class _ImportOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  const _ImportOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              if (trailing != null) ...[
                const SizedBox(height: 12),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;

  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
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

class _WarningsCard extends StatefulWidget {
  final List<String> warnings;
  final List<String> errors;

  const _WarningsCard({required this.warnings, required this.errors});

  @override
  State<_WarningsCard> createState() => _WarningsCardState();
}

class _WarningsCardState extends State<_WarningsCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final allItems = [...widget.errors, ...widget.warnings];
    final displayItems = _isExpanded ? allItems : allItems.take(3).toList();
    final hasMore = allItems.length > 3;

    return Card(
      color: widget.errors.isNotEmpty
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.tertiaryContainer,
      child: InkWell(
        onTap: hasMore ? () => setState(() => _isExpanded = !_isExpanded) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    widget.errors.isNotEmpty ? Icons.error : Icons.warning,
                    size: 20,
                    color: widget.errors.isNotEmpty
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.tertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.errors.isNotEmpty
                          ? '${widget.errors.length} Errors'
                          : '${widget.warnings.length} Warnings',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (hasMore)
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (_isExpanded)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: displayItems
                          .map((item) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text('• $item'),
                              ))
                          .toList(),
                    ),
                  ),
                )
              else ...[
                ...displayItems.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $item'),
                    )),
                if (hasMore)
                  Text(
                    'Tap to see ${allItems.length - 3} more',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
