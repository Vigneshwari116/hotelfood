import 'package:flutter/material.dart';

import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/menu_item_edit_helpers.dart';
import 'package:foodstock/services/repository.dart';
import 'package:foodstock/widgets/responsive_shell.dart';

const _categoryDisplayOrder = [
  'Sauces',
  'Snacks',
  'Fried Items',
  'Burgers',
  'Rolls',
  'Beverages',
  'Uncategorized',
];

/// Full-screen spreadsheet-style editor for all menu items at once.
class MenuItemsGridScreen extends StatefulWidget {
  const MenuItemsGridScreen({super.key});

  @override
  State<MenuItemsGridScreen> createState() => _MenuItemsGridScreenState();
}

class _MenuItemsGridScreenState extends State<MenuItemsGridScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<Category> _categories = [];
  List<UnitM> _units = [];
  final List<_MenuGridRow> _rows = [];

  bool _loading = true;
  bool _savingAll = false;
  bool _changed = false;

  bool get _readOnly => Repository.instance.isAdmin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final results = await Future.wait([
        Repository.instance.rawMaterials(
          search: _searchController.text.trim(),
          includeHidden: true,
        ),
        Repository.instance.categories(type: 'raw_material'),
        Repository.instance.units(),
      ]);

      if (!mounted) return;

      for (final row in _rows) {
        row.dispose();
      }
      _rows.clear();

      final items = results[0] as List<RawMaterial>;
      _categories = results[1] as List<Category>;
      _units = results[2] as List<UnitM>;

      for (final item in items) {
        _rows.add(_MenuGridRow(item: item));
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage('Failed to load menu items: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _categoryName(int? id) {
    if (id == null) return 'Uncategorized';
    for (final category in _categories) {
      if (category.id == id) return category.name;
    }
    return 'Uncategorized';
  }

  int _categorySortIndex(String name) {
    final lower = name.toLowerCase();
    for (var i = 0; i < _categoryDisplayOrder.length; i++) {
      if (_categoryDisplayOrder[i].toLowerCase() == lower) return i;
    }
    return _categoryDisplayOrder.length;
  }

  Map<String, List<_MenuGridRow>> get _groupedRows {
    final grouped = <String, List<_MenuGridRow>>{};
    for (final row in _rows) {
      final category = _categoryName(row.item.categoryId);
      grouped.putIfAbsent(category, () => []).add(row);
    }

    for (final rows in grouped.values) {
      rows.sort(
        (a, b) => a.item.name.toLowerCase().compareTo(
              b.item.name.toLowerCase(),
            ),
      );
    }

    return grouped;
  }

  List<String> get _sortedCategories {
    final keys = _groupedRows.keys.toList();
    keys.sort((a, b) {
      final byOrder = _categorySortIndex(a).compareTo(_categorySortIndex(b));
      if (byOrder != 0) return byOrder;
      return a.compareTo(b);
    });
    return keys;
  }

  int get _dirtyCount => _rows.where((row) => row.isDirty).length;

  void _markChanged() {
    if (!_changed && _dirtyCount > 0) {
      setState(() => _changed = true);
    } else if (_changed && _dirtyCount == 0) {
      setState(() => _changed = false);
    } else {
      setState(() {});
    }
  }

  Future<void> _saveRow(_MenuGridRow row) async {
    if (_readOnly || row.saving || !row.isDirty) return;

    final item = row.buildItem();
    if (item.name.trim().isEmpty) {
      _showMessage('Item name cannot be empty', isError: true);
      return;
    }

    row.saving = true;
    setState(() {});

    try {
      await Repository.instance.saveRawMaterial(item);
      final refreshed =
          await Repository.instance.rawMaterialById(item.id!);
      row.commitSaved(refreshed ?? item);
      _markChanged();
      _showMessage('Saved ${item.name}');
    } catch (e) {
      _showMessage('Failed to save ${item.name}: $e', isError: true);
    } finally {
      row.saving = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveAllDirty() async {
    if (_readOnly || _savingAll) return;

    final dirtyRows = _rows.where((row) => row.isDirty).toList();
    if (dirtyRows.isEmpty) return;

    setState(() => _savingAll = true);

    var saved = 0;
    for (final row in dirtyRows) {
      final item = row.buildItem();
      if (item.name.trim().isEmpty) continue;

      row.saving = true;
      setState(() {});

      try {
        await Repository.instance.saveRawMaterial(item);
        row.commitSaved(item);
        saved++;
      } catch (e) {
        _showMessage('Failed to save ${item.name}: $e', isError: true);
      } finally {
        row.saving = false;
        if (mounted) setState(() {});
      }
    }

    setState(() => _savingAll = false);
    _markChanged();

    if (saved > 0) {
      _showMessage('Saved $saved item${saved == 1 ? '' : 's'}');
    }
  }

  void _showMessage(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }

  Future<bool> _confirmLeaveIfDirty() async {
    if (_dirtyCount == 0) return true;

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: Text(
          'You have $_dirtyCount unsaved change${_dirtyCount == 1 ? '' : 's'}. '
          'Save before leaving?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save all'),
          ),
        ],
      ),
    );

    if (action == 'cancel' || action == null) return false;
    if (action == 'save') {
      await _saveAllDirty();
      return _dirtyCount == 0;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile =
        MediaQuery.of(context).size.width < Breakpoints.mobile;

    return PopScope(
      canPop: _dirtyCount == 0,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await _confirmLeaveIfDirty();
        if (leave && context.mounted) {
          Navigator.of(context).pop(_changed);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Menu Items Grid'),
          actions: [
            if (!_readOnly && _dirtyCount > 0)
              TextButton.icon(
                onPressed: _savingAll ? null : _saveAllDirty,
                icon: _savingAll
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text('Save all ($_dirtyCount)'),
              ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_readOnly)
                    MaterialBanner(
                      content: const Text(
                        'View only. Menu edits are managed at each location.',
                      ),
                      leading: const Icon(Icons.visibility_outlined),
                      backgroundColor: Colors.blue.shade50,
                      actions: const [SizedBox.shrink()],
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search menu items...',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _load(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Search'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Qty/Sale = pieces per customer order. '
                      'Units/Packet = pieces in one supplier purchase packet. '
                      'These are different fields — do not swap them.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _rows.isEmpty
                        ? const Center(child: Text('No menu items found'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: _sortedCategories.length,
                              itemBuilder: (context, index) {
                                final category = _sortedCategories[index];
                                final rows = _groupedRows[category]!;
                                return _CategoryGridSection(
                                  category: category,
                                  rows: rows,
                                  units: _units,
                                  readOnly: _readOnly,
                                  isMobile: isMobile,
                                  onFieldCommitted: (row) {
                                    _markChanged();
                                    _saveRow(row);
                                  },
                                  onFieldChanged: _markChanged,
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CategoryGridSection extends StatelessWidget {
  const _CategoryGridSection({
    required this.category,
    required this.rows,
    required this.units,
    required this.readOnly,
    required this.isMobile,
    required this.onFieldCommitted,
    required this.onFieldChanged,
  });

  final String category;
  final List<_MenuGridRow> rows;
  final List<UnitM> units;
  final bool readOnly;
  final bool isMobile;
  final ValueChanged<_MenuGridRow> onFieldCommitted;
  final VoidCallback onFieldChanged;

  static const _headers = [
    _GridColumnSpec('Barcode', width: 120),
    _GridColumnSpec('Item name', width: 140),
    _GridColumnSpec('Sub-item name', width: 140),
    _GridColumnSpec(
      'Qty/Sale\n(per order)',
      width: 88,
      tooltip: 'Pieces sold per customer order (POS quantity multiplier)',
    ),
    _GridColumnSpec(
      'Packets',
      width: 72,
      tooltip: 'Number of supplier purchase packets currently in stock',
    ),
    _GridColumnSpec(
      'Units/Packet\n(from supplier)',
      width: 96,
      tooltip: 'Pieces contained in one purchase packet from the supplier',
    ),
    _GridColumnSpec('Stock\n(pieces)', width: 88),
    _GridColumnSpec('Cost (₹)', width: 80),
    _GridColumnSpec('Sell (₹)', width: 80),
    _GridColumnSpec('Unit', width: 88),
  ];

  @override
  Widget build(BuildContext context) {
    final tableWidth = _headers.fold<double>(
      0,
      (sum, col) => sum + col.width,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    category,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Text(
                  '${rows.length} item${rows.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: isMobile ? tableWidth : null,
                child: Table(
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  columnWidths: {
                    for (var i = 0; i < _headers.length; i++)
                      i: FixedColumnWidth(_headers[i].width),
                  },
                  border: TableBorder.all(
                    color: Theme.of(context).dividerColor,
                  ),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      children: _headers
                          .map(
                            (header) => _HeaderCell(
                              label: header.label,
                              tooltip: header.tooltip,
                            ),
                          )
                          .toList(),
                    ),
                    ...rows.map(
                      (row) => TableRow(
                        decoration: row.isDirty
                            ? BoxDecoration(
                                color: Colors.amber.shade50,
                              )
                            : null,
                        children: [
                          _GridTextCell(
                            controller: row.barcode,
                            readOnly: readOnly,
                            onChanged: onFieldChanged,
                            onCommit: () => onFieldCommitted(row),
                          ),
                          _GridTextCell(
                            controller: row.itemName,
                            readOnly: readOnly,
                            onChanged: onFieldChanged,
                            onCommit: () => onFieldCommitted(row),
                          ),
                          _GridTextCell(
                            controller: row.subItemName,
                            readOnly: readOnly,
                            onChanged: onFieldChanged,
                            onCommit: () => onFieldCommitted(row),
                          ),
                          _GridTextCell(
                            controller: row.qtyPerSale,
                            readOnly: readOnly,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: onFieldChanged,
                            onCommit: () => onFieldCommitted(row),
                          ),
                          _GridTextCell(
                            controller: row.packets,
                            readOnly: readOnly,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: () {
                              row.recalculateStockFromPackets();
                              onFieldChanged();
                            },
                            onCommit: () => onFieldCommitted(row),
                          ),
                          _GridTextCell(
                            controller: row.unitsPerPacket,
                            readOnly: readOnly,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: () {
                              row.recalculateStockFromPackets();
                              onFieldChanged();
                            },
                            onCommit: () => onFieldCommitted(row),
                          ),
                          _GridTextCell(
                            controller: row.stock,
                            readOnly: readOnly,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: onFieldChanged,
                            onCommit: () => onFieldCommitted(row),
                          ),
                          _GridTextCell(
                            controller: row.costPrice,
                            readOnly: readOnly,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: onFieldChanged,
                            onCommit: () => onFieldCommitted(row),
                          ),
                          _GridTextCell(
                            controller: row.sellingPrice,
                            readOnly: readOnly,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: onFieldChanged,
                            onCommit: () => onFieldCommitted(row),
                          ),
                          _GridUnitCell(
                            unitId: row.unitId,
                            units: units,
                            readOnly: readOnly,
                            onChanged: (value) {
                              row.unitId = value;
                              onFieldChanged();
                              onFieldCommitted(row);
                            },
                          ),
                        ],
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
}

class _GridColumnSpec {
  const _GridColumnSpec(
    this.label, {
    required this.width,
    this.tooltip,
  });

  final String label;
  final double width;
  final String? tooltip;
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    this.tooltip,
  });

  final String label;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: tooltip == null
          ? text
          : Tooltip(
              message: tooltip!,
              child: text,
            ),
    );
  }
}

class _GridTextCell extends StatelessWidget {
  const _GridTextCell({
    required this.controller,
    required this.readOnly,
    required this.onChanged,
    required this.onCommit,
    this.keyboardType,
  });

  final TextEditingController controller;
  final bool readOnly;
  final VoidCallback onChanged;
  final VoidCallback onCommit;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        enabled: !readOnly,
        keyboardType: keyboardType,
        textInputAction: TextInputAction.done,
        style: Theme.of(context).textTheme.bodySmall,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        ),
        onChanged: (_) => onChanged(),
        onEditingComplete: onCommit,
        onSubmitted: (_) => onCommit(),
      ),
    );
  }
}

class _GridUnitCell extends StatelessWidget {
  const _GridUnitCell({
    required this.unitId,
    required this.units,
    required this.readOnly,
    required this.onChanged,
  });

  final int? unitId;
  final List<UnitM> units;
  final bool readOnly;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: DropdownButtonFormField<int>(
        initialValue: unitId,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        ),
        style: Theme.of(context).textTheme.bodySmall,
        items: units
            .where((unit) => unit.id != null)
            .map(
              (unit) => DropdownMenuItem<int>(
                value: unit.id,
                child: Text(unit.shortCode),
              ),
            )
            .toList(),
        onChanged: readOnly ? null : onChanged,
      ),
    );
  }
}

class _MenuGridRow {
  _MenuGridRow({
    required RawMaterial item,
  }) : item = item {
    barcode = TextEditingController(text: item.barcode ?? '');
    itemName = TextEditingController(text: item.name);
    subItemName = TextEditingController(text: item.subItem ?? item.name);
    qtyPerSale = TextEditingController(
      text: MenuItemEditHelpers.formatNumber(item.qtyNeeded),
    );
    unitsPerPacket = TextEditingController(
      text: item.unitsPerPacket == null
          ? ''
          : MenuItemEditHelpers.formatNumber(item.unitsPerPacket!),
    );
    stock = TextEditingController(
      text: MenuItemEditHelpers.formatNumber(item.currentStock),
    );
    packets = TextEditingController(
      text: MenuItemEditHelpers.packetsTextFromStock(
            item.currentStock,
            item.unitsPerPacket,
          ) ??
          '',
    );
    costPrice = TextEditingController(
      text: item.costPrice == null
          ? ''
          : MenuItemEditHelpers.formatNumber(item.costPrice!),
    );
    sellingPrice = TextEditingController(
      text: item.sellingPrice == null
          ? ''
          : MenuItemEditHelpers.formatNumber(item.sellingPrice!),
    );
    unitId = item.unitId;

    _snapshot = _captureSnapshot();
  }

  RawMaterial item;
  bool saving = false;

  late final TextEditingController barcode;
  late final TextEditingController itemName;
  late final TextEditingController subItemName;
  late final TextEditingController qtyPerSale;
  late final TextEditingController packets;
  late final TextEditingController unitsPerPacket;
  late final TextEditingController stock;
  late final TextEditingController costPrice;
  late final TextEditingController sellingPrice;
  int? unitId;

  late String _snapshot;

  String _captureSnapshot() {
    return [
      barcode.text,
      itemName.text,
      subItemName.text,
      qtyPerSale.text,
      packets.text,
      unitsPerPacket.text,
      stock.text,
      costPrice.text,
      sellingPrice.text,
      unitId?.toString() ?? '',
    ].join('\u0001');
  }

  bool get isDirty => _snapshot != _captureSnapshot();

  void recalculateStockFromPackets() {
    final recalculated = MenuItemEditHelpers.stockFromPacketsAndUnitsPerPacket(
      packetsText: packets.text,
      unitsPerPacketText: unitsPerPacket.text,
    );
    if (recalculated == null) return;

    final text = MenuItemEditHelpers.formatNumber(recalculated);
    if (stock.text.trim() == text) return;
    stock.text = text;
  }

  RawMaterial buildItem() {
    return MenuItemEditHelpers.buildForSave(
      existing: item,
      barcodeText: barcode.text,
      itemName: itemName.text,
      subItemText: subItemName.text,
      qtyPerSaleText: qtyPerSale.text,
      packetsText: packets.text,
      unitsPerPacketText: unitsPerPacket.text,
      stockText: stock.text,
      costPriceText: costPrice.text,
      sellingPriceText: sellingPrice.text,
      unitId: unitId,
    );
  }

  void commitSaved(RawMaterial saved) {
    item = saved;
    barcode.text = saved.barcode ?? '';
    itemName.text = saved.name;
    subItemName.text = saved.subItem ?? saved.name;
    qtyPerSale.text = MenuItemEditHelpers.formatNumber(saved.qtyNeeded);
    unitsPerPacket.text = saved.unitsPerPacket == null
        ? ''
        : MenuItemEditHelpers.formatNumber(saved.unitsPerPacket!);
    stock.text = MenuItemEditHelpers.formatNumber(saved.currentStock);
    packets.text = MenuItemEditHelpers.packetsTextFromStock(
          saved.currentStock,
          saved.unitsPerPacket,
        ) ??
        '';
    costPrice.text = saved.costPrice == null
        ? ''
        : MenuItemEditHelpers.formatNumber(saved.costPrice!);
    sellingPrice.text = saved.sellingPrice == null
        ? ''
        : MenuItemEditHelpers.formatNumber(saved.sellingPrice!);
    unitId = saved.unitId;
    _snapshot = _captureSnapshot();
  }

  void dispose() {
    barcode.dispose();
    itemName.dispose();
    subItemName.dispose();
    qtyPerSale.dispose();
    packets.dispose();
    unitsPerPacket.dispose();
    stock.dispose();
    costPrice.dispose();
    sellingPrice.dispose();
  }
}
