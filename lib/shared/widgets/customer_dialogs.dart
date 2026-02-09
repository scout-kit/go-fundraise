import 'package:flutter/material.dart';

/// Dialog for editing a customer's display name
class EditNameDialog extends StatefulWidget {
  final String currentName;

  const EditNameDialog({super.key, required this.currentName});

  /// Show the dialog and return the new name, or null if cancelled
  static Future<String?> show(BuildContext context, String currentName) {
    return showDialog<String>(
      context: context,
      builder: (context) => EditNameDialog(currentName: currentName),
    );
  }

  @override
  State<EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<EditNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Customer Name',
          border: OutlineInputBorder(),
        ),
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _submit() {
    final newName = _controller.text.trim();
    if (newName.isNotEmpty) {
      Navigator.pop(context, newName);
    }
  }
}

/// Data class for customer info displayed in merge picker
class MergeCustomerInfo {
  final int index;
  final String? id;
  final String displayName;
  final String? email;
  final String? phone;
  final int totalBoxes;

  const MergeCustomerInfo({
    required this.index,
    this.id,
    required this.displayName,
    this.email,
    this.phone,
    required this.totalBoxes,
  });
}

/// Bottom sheet for selecting a customer to merge into
class MergeTargetPicker extends StatefulWidget {
  final MergeCustomerInfo source;
  final List<MergeCustomerInfo> customers;

  const MergeTargetPicker({
    super.key,
    required this.source,
    required this.customers,
  });

  /// Show the picker and return the selected target, or null if cancelled
  static Future<MergeCustomerInfo?> show(
    BuildContext context, {
    required MergeCustomerInfo source,
    required List<MergeCustomerInfo> customers,
  }) {
    return showModalBottomSheet<MergeCustomerInfo>(
      context: context,
      isScrollControlled: true,
      builder: (context) => MergeTargetPicker(
        source: source,
        customers: customers,
      ),
    );
  }

  @override
  State<MergeTargetPicker> createState() => _MergeTargetPickerState();
}

class _MergeTargetPickerState extends State<MergeTargetPicker> {
  String _searchQuery = '';

  List<MergeCustomerInfo> get _filteredCustomers {
    // Exclude the source customer
    var filtered = widget.customers
        .where((c) => c.index != widget.source.index)
        .toList();

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((c) {
        return c.displayName.toLowerCase().contains(query) ||
            (c.email?.toLowerCase().contains(query) ?? false) ||
            (c.phone?.contains(query) ?? false);
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredCustomers;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
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
          // Header showing source customer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.merge_type,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Merging: ${widget.source.displayName}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        'Select a customer to merge into',
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
          // Search field
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: false,
              decoration: InputDecoration(
                hintText: 'Search customers...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          // Customer list
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No customers found',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final customer = filtered[index];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(customer.displayName),
                        subtitle: Text(
                          [customer.email, customer.phone]
                              .whereType<String>()
                              .join(' | '),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${customer.totalBoxes} box',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                          ),
                        ),
                        onTap: () => Navigator.pop(context, customer),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Confirmation dialog before merging customers
class MergeConfirmationDialog extends StatelessWidget {
  final MergeCustomerInfo source;
  final MergeCustomerInfo target;

  const MergeConfirmationDialog({
    super.key,
    required this.source,
    required this.target,
  });

  /// Show the dialog and return true if confirmed, false/null otherwise
  static Future<bool?> show(
    BuildContext context, {
    required MergeCustomerInfo source,
    required MergeCustomerInfo target,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => MergeConfirmationDialog(
        source: source,
        target: target,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final combinedBoxes = source.totalBoxes + target.totalBoxes;

    return AlertDialog(
      title: const Text('Merge Customers'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This cannot be undone',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Icon(Icons.person_outline, size: 32),
                    const SizedBox(height: 4),
                    Text(
                      source.displayName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${source.totalBoxes} box',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward, size: 24),
              Expanded(
                child: Column(
                  children: [
                    const Icon(Icons.person, size: 32),
                    const SizedBox(height: 4),
                    Text(
                      target.displayName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${target.totalBoxes} box',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'Combined: $combinedBoxes boxes',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Merge'),
        ),
      ],
    );
  }
}

/// Bottom sheet for customer options (Edit Name, Merge Into...)
class CustomerOptionsSheet extends StatelessWidget {
  final String customerName;
  final bool canMerge;

  const CustomerOptionsSheet({
    super.key,
    required this.customerName,
    required this.canMerge,
  });

  /// Show the options sheet and return the selected action
  static Future<CustomerAction?> show(
    BuildContext context, {
    required String customerName,
    required bool canMerge,
  }) {
    return showModalBottomSheet<CustomerAction>(
      context: context,
      builder: (context) => CustomerOptionsSheet(
        customerName: customerName,
        canMerge: canMerge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(child: Icon(Icons.person)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      customerName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Options
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Name'),
              onTap: () => Navigator.pop(context, CustomerAction.editName),
            ),
            ListTile(
              leading: const Icon(Icons.merge_type),
              title: const Text('Merge Into...'),
              enabled: canMerge,
              onTap: canMerge
                  ? () => Navigator.pop(context, CustomerAction.merge)
                  : null,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Actions available from the customer options sheet
enum CustomerAction { editName, merge }
