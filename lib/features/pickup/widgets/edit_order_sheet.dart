import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_fundraise/core/database/database.dart';
import 'package:go_fundraise/features/pickup/providers/pickup_provider.dart';
import 'package:go_fundraise/features/pickup/widgets/add_items_sheet.dart';

/// Bottom sheet for editing a single order's fields and line items. Edits
/// to an imported order preserve source_kind='imported' and leave the
/// imported_* snapshot untouched so "Reset to Original" still restores the
/// pre-edit state. Manual orders additionally expose a Delete button.
///
/// Line items use a 0/1/N quantity stepper — dropping to 0 marks the item
/// for deletion on save. Adding brand-new items piggy-backs on Chunk 3's
/// upsert flow (new names become reusable fundraiser items).
class EditOrderSheet extends ConsumerStatefulWidget {
  final Order order;
  final List<OrderItemWithProduct> items;
  final String customerId;

  const EditOrderSheet({
    super.key,
    required this.order,
    required this.items,
    required this.customerId,
  });

  /// Returns `true` if any edits were saved (or the order was deleted).
  static Future<bool?> show(
    BuildContext context, {
    required Order order,
    required List<OrderItemWithProduct> items,
    required String customerId,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => EditOrderSheet(
        order: order,
        items: items,
        customerId: customerId,
      ),
    );
  }

  @override
  ConsumerState<EditOrderSheet> createState() => _EditOrderSheetState();
}

class _EditOrderSheetState extends ConsumerState<EditOrderSheet> {
  late final TextEditingController _buyerNameController;
  late final TextEditingController _buyerPhoneController;
  late final TextEditingController _orderDateController;
  late final TextEditingController _orderIdController;

  /// Payment status: 'paid', 'unpaid', or null (blank).
  String? _paymentStatus;

  /// Working quantity per order_item id. 0 = mark for deletion.
  late final Map<String, int> _quantities;
  late final List<_NewItemDraft> _newItems;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _buyerNameController =
        TextEditingController(text: widget.order.buyerName ?? '');
    _buyerPhoneController =
        TextEditingController(text: widget.order.buyerPhone ?? '');
    _orderDateController =
        TextEditingController(text: widget.order.orderDate ?? '');
    _orderIdController =
        TextEditingController(text: widget.order.originalOrderId ?? '');
    _paymentStatus = widget.order.paymentStatus;
    _quantities = {
      for (final item in widget.items) item.id: item.quantity,
    };
    _newItems = [];
  }

  @override
  void dispose() {
    _buyerNameController.dispose();
    _buyerPhoneController.dispose();
    _orderDateController.dispose();
    _orderIdController.dispose();
    super.dispose();
  }

  bool get _isDirty {
    if (_buyerNameController.text.trim() !=
        (widget.order.buyerName ?? '').trim()) return true;
    if (_buyerPhoneController.text.trim() !=
        (widget.order.buyerPhone ?? '').trim()) return true;
    if (_orderDateController.text.trim() !=
        (widget.order.orderDate ?? '').trim()) return true;
    if (_orderIdController.text.trim() !=
        (widget.order.originalOrderId ?? '').trim()) return true;
    if (_paymentStatus != widget.order.paymentStatus) return true;
    for (final item in widget.items) {
      if ((_quantities[item.id] ?? 0) != item.quantity) return true;
    }
    if (_newItems.any((d) =>
        d.productName.trim().isNotEmpty && d.quantity > 0)) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isManual = !widget.order.isImported;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          _HandleBar(),
          _Header(
            order: widget.order,
            onDelete: isManual ? _confirmDelete : null,
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              children: [
                _sectionLabel(context, 'ORDER'),
                TextField(
                  controller: _orderIdController,
                  decoration: const InputDecoration(
                    labelText: 'Order ID',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _orderDateController,
                  decoration: const InputDecoration(
                    labelText: 'Order date',
                    hintText: 'e.g., 2026/04/10',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _paymentStatus,
                  decoration: const InputDecoration(
                    labelText: 'Payment status',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('— (blank)')),
                    DropdownMenuItem(value: 'paid', child: Text('Paid')),
                    DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
                  ],
                  onChanged: (v) => setState(() => _paymentStatus = v),
                ),
                const SizedBox(height: 20),
                _sectionLabel(context, 'BUYER'),
                TextField(
                  controller: _buyerNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Buyer name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _buyerPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Buyer phone',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 20),
                _sectionLabel(context, 'ITEMS'),
                for (final item in widget.items)
                  _ExistingItemRow(
                    item: item,
                    quantity: _quantities[item.id] ?? 0,
                    onChanged: (q) => setState(() => _quantities[item.id] = q),
                  ),
                for (var i = 0; i < _newItems.length; i++)
                  _NewItemRow(
                    draft: _newItems[i],
                    onChanged: (d) => setState(() => _newItems[i] = d),
                    onRemove: () => setState(() => _newItems.removeAt(i)),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => setState(
                    () => _newItems.add(const _NewItemDraft()),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add item'),
                ),
              ],
            ),
          ),
          _SaveBar(
            canSave: _isDirty && !_saving,
            onSave: _save,
            onCancel: () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final quantityUpdates = <String, int>{};
    final removedItemIds = <String>{};
    for (final item in widget.items) {
      final newQty = _quantities[item.id] ?? item.quantity;
      if (newQty == item.quantity) continue;
      if (newQty <= 0) {
        removedItemIds.add(item.id);
      } else {
        quantityUpdates[item.id] = newQty;
      }
    }

    final addedItems = <AddCustomItemInput>[];
    for (final draft in _newItems) {
      final name = draft.productName.trim();
      if (name.isEmpty || draft.quantity <= 0) continue;
      addedItems.add(AddCustomItemInput(
        productName: name,
        sku: draft.sku?.trim().isEmpty == true ? null : draft.sku?.trim(),
        quantity: draft.quantity,
      ));
    }

    // Build the updated order via copyWith so imported_* snapshot columns
    // and source_kind remain untouched.
    final updated = widget.order.copyWith(
      buyerName: Value(_emptyToNull(_buyerNameController.text)),
      buyerPhone: Value(_normalizePhone(_buyerPhoneController.text)),
      orderDate: Value(_emptyToNull(_orderDateController.text)),
      originalOrderId: Value(_emptyToNull(_orderIdController.text)),
      paymentStatus: Value(_paymentStatus),
    );

    await ref.read(pickupServiceProvider).applyOrderEdits(
          updatedOrder: updated,
          customerId: widget.customerId,
          quantityUpdates: quantityUpdates,
          removedItemIds: removedItemIds,
          addedItems: addedItems,
        );

    // Force the customer detail stream to rebuild so ITEMS / ORDER HISTORY
    // reflect the new state immediately.
    ref.invalidate(customerDetailProvider(widget.customerId));

    if (!mounted) return;
    HapticFeedback.lightImpact();
    Navigator.pop(context, true);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete order?'),
        content: const Text(
          'This manual order and all its items will be removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(pickupServiceProvider).deleteCustomerOrder(
          orderId: widget.order.id,
          customerId: widget.customerId,
        );

    ref.invalidate(customerDetailProvider(widget.customerId));

    if (!mounted) return;
    HapticFeedback.lightImpact();
    Navigator.pop(context, true);
  }

  String? _emptyToNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  String? _normalizePhone(String s) {
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    if (digits.length < 10) return digits; // keep whatever the user typed
    return digits.substring(digits.length - 10);
  }
}

class _NewItemDraft {
  final String productName;
  final String? sku;
  final int quantity;

  const _NewItemDraft({
    this.productName = '',
    this.sku,
    this.quantity = 1,
  });

  _NewItemDraft copyWith({String? productName, String? sku, int? quantity}) {
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
  final Order order;
  final VoidCallback? onDelete;

  const _Header({required this.order, this.onDelete});

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
            order.isImported
                ? Icons.download_for_offline_outlined
                : Icons.edit_note,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit order #${order.originalOrderId ?? order.id.substring(0, 8)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  order.isImported
                      ? 'Imported — reset restores the original.'
                      : 'Manually added — can be deleted outright.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Delete order',
              icon: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class _ExistingItemRow extends StatelessWidget {
  final OrderItemWithProduct item;
  final int quantity;
  final ValueChanged<int> onChanged;

  const _ExistingItemRow({
    required this.item,
    required this.quantity,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final willDelete = quantity <= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.displayName,
              style: TextStyle(
                decoration: willDelete ? TextDecoration.lineThrough : null,
                color: willDelete
                    ? Theme.of(context).colorScheme.outline
                    : null,
              ),
            ),
          ),
          _QuantityStepper(
            quantity: quantity,
            onChanged: onChanged,
          ),
        ],
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
      margin: const EdgeInsets.symmetric(vertical: 4),
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
                      labelText: 'New item name',
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
                  onChanged: (q) =>
                      widget.onChanged(widget.draft.copyWith(quantity: q)),
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
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const _SaveBar({
    required this.canSave,
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
                label: const Text('Save changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
