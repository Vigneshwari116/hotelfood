import 'package:flutter/material.dart';

import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/combo_only_categories.dart';
import 'package:foodstock/services/item_import_service.dart';
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
  List<Combo> _combos = [];
  Set<int?> _comboOnlyCategoryIds = {};
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
        Repository.instance.rawMaterialsForDisplay(
          search: _searchController.text.trim(),
          includeHidden: true,
        ),
        Repository.instance.categories(type: 'raw_material'),
        Repository.instance.units(),
        Repository.instance.combosWithItems(),
      ]);

      if (!mounted) return;

      for (final row in _rows) {
        row.dispose();
      }
      _rows.clear();

      final items = results[0] as List<RawMaterial>;
      _categories = results[1] as List<Category>;
      _units = results[2] as List<UnitM>;
      _combos = results[3] as List<Combo>;
      _comboOnlyCategoryIds = ComboOnlyCategories.categoryIds(
        materials: items,
        combos: _combos,
      );

      for (final item in items) {
        _rows.add(_MenuGridRow(item: item));
      }
      _MenuGridRow.linkStockSourceNames(_rows, items);
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
      if (category.id == id) {
        return _canonicalCategoryDisplayName(category.name);
      }
    }
    return 'Uncategorized';
  }

  String _canonicalCategoryDisplayName(String name) {
    return ItemImportService.displayCategoryName(name);
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
      if (ComboOnlyCategories.shouldHideStandaloneMenuItem(
        row.item,
        categoryNameFor: _rawCategoryName,
        comboOnlyCategoryIds: _comboOnlyCategoryIds,
      )) {
        continue;
      }
      final category = _categoryName(row.item.categoryId);
      grouped.putIfAbsent(category, () => []).add(row);
    }

    for (final rows in grouped.values) {
      rows.sort((a, b) {
        final subA = (a.item.subItem ?? a.item.name).toLowerCase();
        final subB = (b.item.subItem ?? b.item.name).toLowerCase();
        final bySub = subA.compareTo(subB);
        if (bySub != 0) return bySub;
        return a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase());
      });
    }

    return grouped;
  }

  List<String> get _sortedCategories {
    final keys = _groupedRows.keys.where((categoryName) {
      if (ComboOnlyCategories.isComboSaleOnlyCategoryName(categoryName)) {
        return false;
      }
      final categoryId = _categoryIdForName(categoryName);
      if (categoryId != null && _comboOnlyCategoryIds.contains(categoryId)) {
        return false;
      }
      return true;
    }).toList();
    keys.sort((a, b) {
      final byOrder = _categorySortIndex(a).compareTo(_categorySortIndex(b));
      if (byOrder != 0) return byOrder;
      return a.compareTo(b);
    });
    return keys;
  }

  int? _categoryIdForName(String name) {
    if (_canonicalCategoryDisplayName(name) == 'Uncategorized') return null;
    for (final category in _categories) {
      if (_canonicalCategoryDisplayName(category.name) == name) {
        return category.id;
      }
    }
    return null;
  }

  String? _rawCategoryName(int? id) {
    if (id == null) return null;
    for (final category in _categories) {
      if (category.id == id) return category.name;
    }
    return null;
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

  List<String> _distinctFieldValues(String Function(_MenuGridRow row) read) {
    final values = <String>{};
    for (final row in _rows) {
      final value = read(row).trim();
      if (value.isNotEmpty) values.add(value);
    }
    return values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  List<String> get _existingVariantGroups => _distinctFieldValues(
        (row) => row.variantGroup.text.isNotEmpty
            ? row.variantGroup.text
            : (row.item.variantGroup ?? ''),
      );

  List<String> get _existingVariantLabels => _distinctFieldValues(
        (row) => row.variantLabel.text.isNotEmpty
            ? row.variantLabel.text
            : (row.item.variantLabel ?? ''),
      );

  List<String> get _existingStockSourceNames => _distinctFieldValues(
        (row) => row.itemName.text,
      );

  Future<void> _addItemInCategory(String categoryName) async {
    if (_readOnly) return;

    final name = await showDialog<String>(
      context: context,
      builder: (context) => _AddItemNameDialog(categoryName: categoryName),
    );
    if (name == null || !mounted) return;

    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      _showMessage('Item name cannot be empty', isError: true);
      return;
    }

    try {
      final categoryId = _categoryIdForName(categoryName);
      final unitId = _units.isNotEmpty ? _units.first.id : null;
      final id = await Repository.instance.saveRawMaterial(
        RawMaterial(
          name: trimmed,
          subItem: trimmed,
          categoryId: categoryId,
          unitId: unitId,
          listed: true,
          createdAt: DateTime.now(),
        ),
      );
      final saved = await Repository.instance.rawMaterialById(id);
      if (saved == null || !mounted) return;
      setState(() {
        _rows.add(_MenuGridRow(item: saved));
        _MenuGridRow.linkStockSourceNames(_rows, _rows.map((r) => r.item).toList());
        _changed = true;
      });
      _showMessage('Added $trimmed');
    } catch (e) {
      _showMessage('Failed to add item: $e', isError: true);
    }
  }

  Future<void> _saveRows(List<_MenuGridRow> rows) async {
    if (_readOnly || _savingAll) return;

    final dirtyRows = rows.where((row) => row.isDirty).toList();
    if (dirtyRows.isEmpty) {
      _showMessage('No changes to save');
      return;
    }

    setState(() => _savingAll = true);

    var saved = 0;
    for (final row in dirtyRows) {
      final item = row.buildItem(_rows);
      if (item.name.trim().isEmpty) continue;

      row.saving = true;
      setState(() {});

      try {
        final savedId = await Repository.instance.saveRawMaterial(item);
        final id = item.id ?? savedId;
        final refreshed = await Repository.instance.rawMaterialById(id);
        row.commitSaved(refreshed ?? item, _rows);
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
    if (_dirtyCount == 0 && _changed) {
      setState(() => _changed = false);
    }

    if (saved > 0) {
      _showMessage('Saved');
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

  Future<void> _deleteRow(_MenuGridRow row) async {
    if (_readOnly || row.item.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text(
          'Remove "${row.item.name}" from the menu? '
          'Items with purchase or sale history will be hidden instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Repository.instance.deleteRawMaterial(row.item.id!);
      setState(() {
        _rows.remove(row);
        row.dispose();
      });
      _showMessage('Deleted ${row.item.name}');
    } catch (_) {
      await Repository.instance.hideRawMaterial(row.item.id!);
      if (!mounted) return;
      setState(() {
        _rows.remove(row);
        row.dispose();
      });
      _showMessage('Hidden ${row.item.name} (has history)');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile =
        MediaQuery.of(context).size.width < Breakpoints.mobile;

    return Scaffold(
        appBar: AppBar(
          title: const Text('Menu Items Grid'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : () => _load(),
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
                          onPressed: _loading ? null : () => _load(),
                          child: const Text('Search'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Pieces per packet is set once per item. Enter opening packets and '
                      'opening pieces; total stock = (opening packets × pieces per packet) '
                      '+ opening pieces (auto, in pieces). '
                      'Pieces sold per customer = qty per POS order. '
                      'Variant Group / Label: type a new name or pick from the list.',
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
                                  variantGroups: _existingVariantGroups,
                                  variantLabels: _existingVariantLabels,
                                  stockSourceNames: _existingStockSourceNames,
                                  readOnly: _readOnly,
                                  isMobile: isMobile,
                                  saving: _savingAll,
                                  onFieldCommitted: (_) => _markChanged(),
                                  onFieldChanged: _markChanged,
                                  onDelete: _deleteRow,
                                  onAdd: () => _addItemInCategory(category),
                                  onSave: () => _saveRows(rows),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
    );
  }
}

class _CategoryGridSection extends StatelessWidget {
  const _CategoryGridSection({
    required this.category,
    required this.rows,
    required this.variantGroups,
    required this.variantLabels,
    required this.stockSourceNames,
    required this.readOnly,
    required this.isMobile,
    required this.saving,
    required this.onFieldCommitted,
    required this.onFieldChanged,
    required this.onDelete,
    required this.onAdd,
    required this.onSave,
  });

  final String category;
  final List<_MenuGridRow> rows;
  final List<String> variantGroups;
  final List<String> variantLabels;
  final List<String> stockSourceNames;
  final bool readOnly;
  final bool isMobile;
  final bool saving;
  final ValueChanged<_MenuGridRow> onFieldCommitted;
  final VoidCallback onFieldChanged;
  final ValueChanged<_MenuGridRow> onDelete;
  final VoidCallback onAdd;
  final VoidCallback onSave;

  int get _dirtyInSection => rows.where((row) => row.isDirty).length;

  static const _headers = [
    _GridColumnSpec('Barcode', width: 72),
    _GridColumnSpec('Item name', width: 152, wrapText: true),
    _GridColumnSpec('Sub-item name', width: 152, wrapText: true),
    _GridColumnSpec(
      'Variant Group',
      width: 136,
      menuWidth: 260,
      tooltip:
          'Items with the same group appear as one POS card with a size selector',
    ),
    _GridColumnSpec(
      'Variant Label',
      width: 112,
      menuWidth: 220,
      tooltip: 'Size/portion label on the POS selector (e.g. Large, Mini Bucket)',
    ),
    _GridColumnSpec(
      'Stock source',
      width: 144,
      menuWidth: 260,
      tooltip:
          'Item that holds shared stock for this row (blank = this item owns stock)',
    ),
    _GridColumnSpec(
      'Pieces per\npacket',
      width: 72,
      tooltip: 'Pieces in one supplier purchase packet (e.g. 1 packet of buns = 12)',
    ),
    _GridColumnSpec(
      'Opening\npackets',
      width: 72,
      tooltip: 'How many purchase packets are currently in stock',
    ),
    _GridColumnSpec(
      'Opening\npieces',
      width: 72,
      tooltip: 'Loose pieces outside packets (added to total stock)',
    ),
    _GridColumnSpec(
      'Total\nstock',
      width: 64,
      tooltip: 'Auto: (opening packets × pieces per packet) + opening pieces',
    ),
    _GridColumnSpec(
      'Pieces sold\nfor customer',
      width: 76,
      tooltip: 'Pieces sold per customer order (POS quantity multiplier)',
    ),
    _GridColumnSpec('Cost (₹)', width: 60),
    _GridColumnSpec('Sell (₹)', width: 60),
    _GridColumnSpec('', width: 36),
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
                if (!readOnly) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: saving ? null : onSave,
                    icon: saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(
                      _dirtyInSection > 0
                          ? 'Save ($_dirtyInSection)'
                          : 'Save',
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add item'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
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
                            wrapText: true,
                            onChanged: onFieldChanged,
                            onCommit: () => onFieldCommitted(row),
                          ),
                          _GridTextCell(
                            controller: row.subItemName,
                            readOnly: readOnly,
                            wrapText: true,
                            onChanged: onFieldChanged,
                            onCommit: () => onFieldCommitted(row),
                          ),
                          _GridComboCell(
                            controller: row.variantGroup,
                            options: variantGroups,
                            readOnly: readOnly,
                            allowEmpty: true,
                            hintText: 'Type or pick group',
                            onChanged: onFieldChanged,
                            onCommit: () => onFieldCommitted(row),
                          ),
                          _GridComboCell(
                            controller: row.variantLabel,
                            options: variantLabels,
                            readOnly: readOnly,
                            allowEmpty: true,
                            hintText: 'Type or pick label',
                            onChanged: onFieldChanged,
                            onCommit: () => onFieldCommitted(row),
                          ),
                          _GridSelectCell(
                            controller: row.stockSourceName,
                            options: stockSourceNames
                                .where(
                                  (name) =>
                                      name.toLowerCase() !=
                                      row.itemName.text.trim().toLowerCase(),
                                )
                                .toList(),
                            readOnly: readOnly,
                            allowEmpty: true,
                            menuWidth: _headers[5].menuWidth,
                            onChanged: onFieldChanged,
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
                            controller: row.openingPieces,
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
                            readOnly: true,
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
                          Padding(
                            padding: const EdgeInsets.all(2),
                            child: IconButton(
                              tooltip: 'Delete row',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              icon: Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: readOnly
                                    ? Colors.grey
                                    : Colors.red.shade700,
                              ),
                              onPressed:
                                  readOnly ? null : () => onDelete(row),
                            ),
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
    this.menuWidth,
    this.wrapText = false,
  });

  final String label;
  final double width;
  final String? tooltip;
  final double? menuWidth;
  final bool wrapText;
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

class _GridComboCell extends StatelessWidget {
  const _GridComboCell({
    required this.controller,
    required this.options,
    required this.readOnly,
    required this.onChanged,
    required this.onCommit,
    this.allowEmpty = false,
    this.hintText,
  });

  final TextEditingController controller;
  final List<String> options;
  final bool readOnly;
  final VoidCallback onChanged;
  final VoidCallback onCommit;
  final bool allowEmpty;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    if (readOnly) {
      return _GridTextCell(
        controller: controller,
        readOnly: true,
        onChanged: onChanged,
        onCommit: onCommit,
      );
    }

    final suggestions = <String>{
      ...options.map((value) => value.trim()).where((value) => value.isNotEmpty),
    }.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Padding(
      padding: const EdgeInsets.all(2),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.done,
        style: Theme.of(context).textTheme.bodySmall,
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          suffixIcon: suggestions.isEmpty && !allowEmpty
              ? null
              : PopupMenuButton<String>(
                  tooltip: 'Pick existing',
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.arrow_drop_down, size: 20),
                  onSelected: (value) {
                    controller.text = value;
                    onChanged();
                    onCommit();
                  },
                  itemBuilder: (context) => [
                    if (allowEmpty)
                      const PopupMenuItem<String>(
                        value: '',
                        child: Text('— (none)'),
                      ),
                    for (final option in suggestions)
                      PopupMenuItem<String>(
                        value: option,
                        child: Text(
                          option,
                          overflow: TextOverflow.visible,
                          softWrap: true,
                        ),
                      ),
                  ],
                ),
        ),
        onChanged: (_) => onChanged(),
        onEditingComplete: onCommit,
        onSubmitted: (_) => onCommit(),
      ),
    );
  }
}

class _GridSelectCell extends StatelessWidget {
  const _GridSelectCell({
    required this.controller,
    required this.options,
    required this.readOnly,
    required this.onChanged,
    required this.onCommit,
    this.allowEmpty = false,
    this.menuWidth,
  });

  final TextEditingController controller;
  final List<String> options;
  final bool readOnly;
  final VoidCallback onChanged;
  final VoidCallback onCommit;
  final bool allowEmpty;
  final double? menuWidth;

  String _labelFor(String value) => value.isEmpty ? '—' : value;

  @override
  Widget build(BuildContext context) {
    if (readOnly) {
      return _GridTextCell(
        controller: controller,
        readOnly: true,
        onChanged: onChanged,
        onCommit: onCommit,
      );
    }

    final current = controller.text.trim();
    final choices = <String>{
      if (allowEmpty) '',
      ...options,
    }.toList()
      ..sort((a, b) {
        if (a.isEmpty) return -1;
        if (b.isEmpty) return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    final selected = choices.contains(current) ? current : (allowEmpty ? '' : null);
    final resolvedMenuWidth = menuWidth ??
        choices.fold<double>(
          180,
          (width, value) {
            final label = _labelFor(value);
            final estimated = label.length * 8.0 + 48;
            return estimated > width ? estimated : width;
          },
        );

    return Padding(
      padding: const EdgeInsets.all(2),
      child: DropdownButtonFormField<String>(
        key: ValueKey('${controller.hashCode}-$current-${choices.length}'),
        isExpanded: true,
        initialValue: selected,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        style: Theme.of(context).textTheme.bodySmall,
        selectedItemBuilder: (context) => choices
            .map(
              (value) => Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _labelFor(value),
                  maxLines: 2,
                  overflow: TextOverflow.visible,
                  softWrap: true,
                ),
              ),
            )
            .toList(),
        items: choices
            .map(
              (value) => DropdownMenuItem<String>(
                value: value,
                child: SizedBox(
                  width: resolvedMenuWidth,
                  child: Text(
                    _labelFor(value),
                    softWrap: true,
                  ),
                ),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value == null) return;
          controller.text = value;
          onChanged();
          onCommit();
        },
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
    this.wrapText = false,
  });

  final TextEditingController controller;
  final bool readOnly;
  final VoidCallback onChanged;
  final VoidCallback onCommit;
  final TextInputType? keyboardType;
  final bool wrapText;

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
        minLines: wrapText ? 1 : 1,
        maxLines: wrapText ? 3 : 1,
        style: Theme.of(context).textTheme.bodySmall,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        onChanged: (_) => onChanged(),
        onEditingComplete: onCommit,
        onSubmitted: (_) => onCommit(),
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
    variantGroup = TextEditingController(text: item.variantGroup ?? '');
    variantLabel = TextEditingController(text: item.variantLabel ?? '');
    stockSourceName = TextEditingController();
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
            openingPieces: item.openingPieces,
          ) ??
          '',
    );
    openingPieces = TextEditingController(
      text: item.openingPieces == 0
          ? ''
          : MenuItemEditHelpers.formatNumber(item.openingPieces),
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
  late final TextEditingController variantGroup;
  late final TextEditingController variantLabel;
  late final TextEditingController stockSourceName;
  late final TextEditingController qtyPerSale;
  late final TextEditingController packets;
  late final TextEditingController openingPieces;
  late final TextEditingController unitsPerPacket;
  late final TextEditingController stock;
  late final TextEditingController costPrice;
  late final TextEditingController sellingPrice;
  int? unitId;

  late String _snapshot;

  static void linkStockSourceNames(
    List<_MenuGridRow> rows,
    List<RawMaterial> items,
  ) {
    final nameById = {
      for (final item in items)
        if (item.id != null) item.id!: item.name,
    };
    for (final row in rows) {
      final sourceId = row.item.stockSourceId;
      if (sourceId == null) {
        row.stockSourceName.text = '';
        continue;
      }
      row.stockSourceName.text = nameById[sourceId] ?? '';
    }
  }

  String _captureSnapshot() {
    return [
      barcode.text,
      itemName.text,
      subItemName.text,
      variantGroup.text,
      variantLabel.text,
      stockSourceName.text,
      qtyPerSale.text,
      packets.text,
      openingPieces.text,
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
      openingPiecesText: openingPieces.text,
    );
    if (recalculated == null) return;

    final text = MenuItemEditHelpers.formatNumber(recalculated);
    if (stock.text.trim() == text) return;
    stock.text = text;
  }

  RawMaterial buildItem(List<_MenuGridRow> allRows) {
    final sourceName = stockSourceName.text.trim().toLowerCase();
    int? stockSourceId;
    if (sourceName.isNotEmpty) {
      for (final row in allRows) {
        if (row.item.id == item.id) continue;
        if (row.itemName.text.trim().toLowerCase() == sourceName) {
          stockSourceId = row.item.id;
          break;
        }
      }
    }

    return MenuItemEditHelpers.buildForSave(
      existing: item,
      barcodeText: barcode.text,
      itemName: itemName.text,
      subItemText: subItemName.text,
      qtyPerSaleText: qtyPerSale.text,
      packetsText: packets.text,
      unitsPerPacketText: unitsPerPacket.text,
      openingPiecesText: openingPieces.text,
      stockText: stock.text,
      costPriceText: costPrice.text,
      sellingPriceText: sellingPrice.text,
      unitId: unitId,
      variantGroupText: variantGroup.text,
      variantLabelText: variantLabel.text,
      stockSourceId: sourceName.isEmpty ? null : stockSourceId,
    );
  }

  void commitSaved(RawMaterial saved, List<_MenuGridRow> allRows) {
    item = saved;
    barcode.text = saved.barcode ?? '';
    itemName.text = saved.name;
    subItemName.text = saved.subItem ?? saved.name;
    variantGroup.text = saved.variantGroup ?? '';
    variantLabel.text = saved.variantLabel ?? '';
    qtyPerSale.text = MenuItemEditHelpers.formatNumber(saved.qtyNeeded);
    unitsPerPacket.text = saved.unitsPerPacket == null
        ? ''
        : MenuItemEditHelpers.formatNumber(saved.unitsPerPacket!);
    stock.text = MenuItemEditHelpers.formatNumber(saved.currentStock);
    packets.text = MenuItemEditHelpers.packetsTextFromStock(
          saved.currentStock,
          saved.unitsPerPacket,
          openingPieces: saved.openingPieces,
        ) ??
        '';
    openingPieces.text = saved.openingPieces == 0
        ? ''
        : MenuItemEditHelpers.formatNumber(saved.openingPieces);
    costPrice.text = saved.costPrice == null
        ? ''
        : MenuItemEditHelpers.formatNumber(saved.costPrice!);
    sellingPrice.text = saved.sellingPrice == null
        ? ''
        : MenuItemEditHelpers.formatNumber(saved.sellingPrice!);
    unitId = saved.unitId;
    stockSourceName.text = '';
    if (saved.stockSourceId != null) {
      for (final row in allRows) {
        if (row.item.id == saved.stockSourceId) {
          stockSourceName.text = row.itemName.text;
          break;
        }
      }
    }
    _snapshot = _captureSnapshot();
  }

  void dispose() {
    barcode.dispose();
    itemName.dispose();
    subItemName.dispose();
    variantGroup.dispose();
    variantLabel.dispose();
    stockSourceName.dispose();
    qtyPerSale.dispose();
    packets.dispose();
    openingPieces.dispose();
    unitsPerPacket.dispose();
    stock.dispose();
    costPrice.dispose();
    sellingPrice.dispose();
  }
}

class _AddItemNameDialog extends StatefulWidget {
  const _AddItemNameDialog({required this.categoryName});

  final String categoryName;

  @override
  State<_AddItemNameDialog> createState() => _AddItemNameDialogState();
}

class _AddItemNameDialogState extends State<_AddItemNameDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(context, _nameController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add item to ${widget.categoryName}'),
      content: TextField(
        controller: _nameController,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Item name',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
