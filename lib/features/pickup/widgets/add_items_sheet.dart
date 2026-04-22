import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_fundraise/core/database/database.dart';
import 'package:go_fundraise/features/pickup/providers/pickup_provider.dart';

/// Bottom sheet for adding custom items (e.g., a "Thank You Crest" reward)
/// to a customer at pickup. Items added here become a synthetic order
/// marked source_kind='manual' and are removed by a later Reset to
/// Original.
///
/// Pick quantities from the fundraiser's existing product catalog, or tap
/// "+ New item" to register something brand new. Save is disabled until at
/// least one row has a positive quantity.
class AddItemsSheet extends ConsumerStatefulWidget {
  final String customerId;
  final String customerName;
  final String fundraiserId;

  const AddItemsSheet({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.fundraiserId,
  });

  /// Show and return `true` if the user saved a non-empty order.
  static Future<bool?> show(
    BuildContext context, {
    required String customerId,
    required String customerName,
    required String fundraiserId,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => AddItemsSheet(
        customerId: customerId,
        customerName: customerName,
        fundraiserId: fundraiserId,
      ),
    );
  }

  @override
  ConsumerState<AddItemsSheet> createState() => _AddItemsSheetState();
}

class _AddItemsSheetState extends ConsumerState<AddItemsSheet> {
  /// Quantities keyed by existing fundraiser item id.
  final Map<String, int> _existingQuantities = {};

  /// New items the user is registering on-the-fly.
  final List<_NewItemDraft> _newItems = [];

  bool _saving = false;

  int get _totalSelectedQty =>
      _existingQuantities.values.fold(0, (a, b) => a + b) +
      _newItems.fold<int>(0, (a, b) => a + b.quantity);

  bool get _canSave => _totalSelectedQty > 0 && !_saving;

  @override
  Widget build(BuildContext context) {
    final itemsAsync =
        ref.watch(watchFundraiserItemsProvider(widget.fundraiserId));

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          _HandleBar(),
          _Header(customerName: widget.customerName),
          Expanded(
            child: itemsAsync.when(
              data: (items) => _buildList(scrollController, items),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
          _SaveBar(
            canSave: _canSave,
            totalQty: _totalSelectedQty,
            onSave: _save,
            onCancel: () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    ScrollController controller,
    List<FundraiserItem> existing,
  ) {
    // Hide items that already have a "new item" draft by the same name, to
    // keep the picker from double-listing after the user types something
    // that matches an existing product.
    return ListView(
      controller: controller,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      children: [
        for (final item in existing)
          _ExistingItemRow(
            item: item,
            quantity: _existingQuantities[item.id] ?? 0,
            onChanged: (qty) => setState(() {
              if (qty <= 0) {
                _existingQuantities.remove(item.id);
              } else {
                _existingQuantities[item.id] = qty;
              }
            }),
          ),
        for (var i = 0; i < _newItems.length; i++)
          _NewItemRow(
            draft: _newItems[i],
            onChanged: (updated) => setState(() => _newItems[i] = updated),
            onRemove: () => setState(() => _newItems.removeAt(i)),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: () => setState(() {
              _newItems.add(const _NewItemDraft());
            }),
            icon: const Icon(Icons.add),
            label: const Text('New item'),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final existingItems = await ref.read(
      fundraiserItemsFutureProvider(widget.fundraiserId).future,
    );
    final byId = {for (final e in existingItems) e.id: e};

    final payload = <AddCustomItemInput>[];
    for (final entry in _existingQuantities.entries) {
      final source = byId[entry.key];
      if (source == null || entry.value <= 0) continue;
      payload.add(AddCustomItemInput(
        productName: source.productName,
        sku: source.sku,
        quantity: entry.value,
      ));
    }
    for (final draft in _newItems) {
      final name = draft.productName.trim();
      if (name.isEmpty || draft.quantity <= 0) continue;
      payload.add(AddCustomItemInput(
        productName: name,
        sku: draft.sku?.trim().isEmpty == true ? null : draft.sku?.trim(),
        quantity: draft.quantity,
      ));
    }

    if (payload.isEmpty) {
      setState(() => _saving = false);
      return;
    }

    await ref
        .read(pickupServiceProvider)
        .addCustomOrder(widget.customerId, items: payload);

    if (!mounted) return;
    HapticFeedback.lightImpact();
    Navigator.pop(context, true);
  }
}

/// Stream of the fundraiser's item catalog for the picker.
final watchFundraiserItemsProvider =
    StreamProvider.family<List<FundraiserItem>, String>((ref, fundraiserId) {
  final db = ref.watch(databaseProvider);
  return db.watchFundraiserItemsByFundraiser(fundraiserId);
});

final fundraiserItemsFutureProvider =
    FutureProvider.family<List<FundraiserItem>, String>((ref, fundraiserId) {
  final db = ref.watch(databaseProvider);
  return db.getFundraiserItemsByFundraiser(fundraiserId);
});

class _NewItemDraft {
  final String productName;
  final String? sku;
  final int quantity;

  const _NewItemDraft({
    this.productName = '',
    this.sku,
    this.quantity = 1,
  });

  _NewItemDraft copyWith({
    String? productName,
    String? sku,
    int? quantity,
  }) {
    return _NewItemDraft(
      productName: productName ?? this.productName,
      sku: sku ?? this.sku,
      quantity: quantity ?? this.quantity,
    );
  }
}

class _HandleBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String customerName;

  const _Header({required this.customerName});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          Icon(
            Icons.add_box_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add items for $customerName',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  'Added items show on the pickup list and count toward the total.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExistingItemRow extends StatelessWidget {
  final FundraiserItem item;
  final int quantity;
  final ValueChanged<int> onChanged;

  const _ExistingItemRow({
    required this.item,
    required this.quantity,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final display =
        item.sku != null && item.sku!.isNotEmpty
            ? '${item.productName} (${item.sku})'
            : item.productName;
    return ListTile(
      title: Text(display),
      trailing: _QuantityStepper(
        quantity: quantity,
        onChanged: onChanged,
      ),
    );
  }
}

class _NewItemRow extends StatefulWidget {
  final _NewItemDraft draft;
  final ValueChanged<_NewItemDraft> onChanged;
  final VoidCallback onRemove;

  const _NewItemRow({
    required this.draft,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_NewItemRow> createState() => _NewItemRowState();
}

class _NewItemRowState extends State<_NewItemRow> {
  late final TextEditingController _nameController;
  late final TextEditingController _skuController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.draft.productName);
    _skuController = TextEditingController(text: widget.draft.sku ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Item name',
                      hintText: 'e.g., Thank You Crest',
                      isDense: true,
                    ),
                    onChanged: (v) => widget
                        .onChanged(widget.draft.copyWith(productName: v)),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.close),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _skuController,
                    decoration: const InputDecoration(
                      labelText: 'SKU (optional)',
                      isDense: true,
                    ),
                    onChanged: (v) =>
                        widget.onChanged(widget.draft.copyWith(sku: v)),
                  ),
                ),
                const SizedBox(width: 12),
                _QuantityStepper(
                  quantity: widget.draft.quantity,
                  onChanged: (qty) => widget
                      .onChanged(widget.draft.copyWith(quantity: qty)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  final int quantity;
  final ValueChanged<int> onChanged;

  const _QuantityStepper({
    required this.quantity,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Decrease',
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: quantity <= 0 ? null : () => onChanged(quantity - 1),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          tooltip: 'Increase',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => onChanged(quantity + 1),
        ),
      ],
    );
  }
}

class _SaveBar extends StatelessWidget {
  final bool canSave;
  final int totalQty;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const _SaveBar({
    required this.canSave,
    required this.totalQty,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onCancel,
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: canSave ? onSave : null,
                icon: const Icon(Icons.check),
                label: Text(
                  totalQty == 0
                      ? 'Add items'
                      : 'Add $totalQty ${totalQty == 1 ? 'item' : 'items'}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
