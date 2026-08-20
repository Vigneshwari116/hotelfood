import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:foodstock/model/models.dart';
import '../services/item_import_service.dart';
import '../services/repository.dart';
import '../widgets/barcode_field.dart';
import '../widgets/responsive_shell.dart';

class RawMaterialMasterScreen extends StatefulWidget {
  const RawMaterialMasterScreen({super.key});

  @override
  State<RawMaterialMasterScreen> createState() =>
      _RawMaterialMasterScreenState();
}

class _RawMaterialMasterScreenState
    extends State<RawMaterialMasterScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<RawMaterial> _items = [];
  List<Category> _categories = [];
  List<UnitM> _units = [];
  List<Combo> _combos = [];

  final TextEditingController _searchController =
  TextEditingController();

  bool _loading = false;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: 2,
      vsync: this,
    );

    _loadMenuFromExcelThenItems();
  }

  Future<void> _loadMenuFromExcelThenItems() async {
    try {
      await ItemImportService().importXlsxBytes(
        (await rootBundle.load(
          'assets/templates/menu_items_import.xlsx',
        ))
            .buffer
            .asUint8List(),
      );
    } catch (_) {}
    await _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // LOAD EVERYTHING
  // ============================================================

  Future<void> _loadAll() async {
    if (_loading) return;

    setState(() {
      _loading = true;
    });

    try {
      final results = await Future.wait([
        Repository.instance.rawMaterials(
          search: _searchController.text.trim(),
        ),
        Repository.instance.categories(
          type: 'raw_material',
        ),
        Repository.instance.units(),
        Repository.instance.combosWithItems(),
      ]);

      if (!mounted) return;

      setState(() {
        _items = results[0] as List<RawMaterial>;
        _categories = results[1] as List<Category>;
        _units = results[2] as List<UnitM>;
        _combos = results[3] as List<Combo>;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load data: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ============================================================
  // CATEGORY NAME
  // ============================================================

  String _categoryName(int? id) {
    if (id == null) return 'Uncategorized';

    for (final category in _categories) {
      if (category.id == id) {
        return category.name;
      }
    }

    return 'Uncategorized';
  }

  // ============================================================
  // UNIT NAME
  // ============================================================

  String _unitName(int? id) {
    if (id == null) return '-';

    for (final unit in _units) {
      if (unit.id == id) {
        return unit.shortCode;
      }
    }

    return '-';
  }

  Future<void> _saveImportTemplate() async {
    final data = await rootBundle.load(
      'assets/templates/menu_items_import.xlsx',
    );
    final bytes = data.buffer.asUint8List();
    String? path;
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save menu Excel',
        fileName: 'Shilpa_Enterprise_menu_items.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
    }
    path ??= p.join(
      (await getApplicationDocumentsDirectory()).path,
      'Shilpa_Enterprise_menu_items.xlsx',
    );
    await File(path).writeAsBytes(bytes);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Excel saved to $path')),
    );
  }

  Future<void> _importItemsFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'xls'],
      allowMultiple: false,
    );
    if (picked == null ||
        picked.files.isEmpty ||
        picked.files.first.path == null) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
        );
      },
    );

    try {
      final result = await ItemImportService().importFile(
        picked.files.first.path!,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await _loadAll();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Import complete'),
            content: Text(
              'Added ${result.created} item(s).\n'
              'Skipped ${result.skipped} existing item(s).'
              '${result.errors.isEmpty ? '' : '\n\n${result.errors.take(8).join('\n')}'}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    }
  }

  // ============================================================
  // IMAGE PICKER
  // ============================================================

  Future<String?> _pickAndSaveImage({
    String folder = 'raw_materials',
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result == null ||
        result.files.isEmpty ||
        result.files.first.path == null) {
      return null;
    }

    final sourcePath = result.files.first.path!;

    final appDir =
    await getApplicationSupportDirectory();

    final imageDir = Directory(
      p.join(appDir.path, 'images', folder),
    );

    if (!await imageDir.exists()) {
      await imageDir.create(
        recursive: true,
      );
    }

    final extension =
    p.extension(sourcePath).toLowerCase();

    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}$extension';

    final destination =
    p.join(imageDir.path, fileName);

    await File(sourcePath).copy(destination);

    return destination;
  }

  // ============================================================
  // RAW MATERIAL EDITOR
  // ============================================================

  Future<void> _openRawMaterialEditor({
    RawMaterial? existing,
  }) async {
    if (!mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) {
        return RawMaterialEditorDialog(
          existing: existing,
          categories: _categories,
          units: _units,
          onPickImage: () {
            return _pickAndSaveImage(
              folder: 'raw_materials',
            );
          },
        );
      },
    );

    if (saved == true) {
      await _loadAll();
    }
  }

  // ============================================================
  // DELETE RAW MATERIAL
  // ============================================================

  Future<void> _deleteRawMaterial(
      RawMaterial item,
      ) async {
    if (item.id == null) return;

    if (!mounted) return;

    final confirm =
    await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text(
            'Delete Item?',
          ),
          content: Text(
            'Delete "${item.name}"?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                    context,
                    false,
                  ),
              child:
              const Text('Cancel'),
            ),
            FilledButton(
              style:
              FilledButton.styleFrom(
                backgroundColor:
                Colors.red,
              ),
              onPressed: () =>
                  Navigator.pop(
                    context,
                    true,
                  ),
              child:
              const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await Repository.instance
        .deleteRawMaterial(
      item.id!,
    );

    await _loadAll();
  }

  // ============================================================
  // COMBO EDITOR
  // ============================================================

  Future<void> _openComboEditor({
    Combo? existing,
  }) async {
    if (!mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) {
        return ComboEditorDialog(
          existing: existing,
          rawMaterials: _items,
          unitName: _unitName,
          onPickImage: () {
            return _pickAndSaveImage(
              folder: 'combos',
            );
          },
        );
      },
    );

    if (saved == true) {
      await _loadAll();
    }
  }

  // ============================================================
  // DELETE COMBO
  // ============================================================

  Future<void> _deleteCombo(
      Combo combo,
      ) async {
    if (combo.id == null) return;

    final confirm =
    await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text(
            'Delete Combo?',
          ),
          content: Text(
            'Delete "${combo.name}"?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                    context,
                    false,
                  ),
              child:
              const Text('Cancel'),
            ),
            FilledButton(
              style:
              FilledButton.styleFrom(
                backgroundColor:
                Colors.red,
              ),
              onPressed: () =>
                  Navigator.pop(
                    context,
                    true,
                  ),
              child:
              const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await Repository.instance
        .deleteCombo(combo.id!);

    await _loadAll();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isMobile =
        MediaQuery.of(context)
            .size
            .width <
            Breakpoints.mobile;

    return Padding(
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
            // ==================================================
            // TABS
            // ==================================================

            Container(
              decoration:
              BoxDecoration(
                border: Border.all(
                  color: Theme.of(context)
                      .dividerColor,
                ),
                borderRadius:
                BorderRadius.circular(
                  10,
                ),
              ),
              child: TabBar(
                controller:
                _tabController,
                tabs: const [
                  Tab(
                    icon: Icon(
                      Icons.inventory_2_outlined,
                    ),
                    text: 'Items',
                  ),
                  Tab(
                    icon: Icon(
                      Icons.collections_outlined,
                    ),
                    text: 'Combos',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ==================================================
            // TAB CONTENT
            // ==================================================

            Expanded(
              child: TabBarView(
                controller:
                _tabController,
                children: [
                  _buildItemsTab(
                    isMobile,
                  ),
                  _buildCombosTab(
                    isMobile,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }

  // ============================================================
  // ITEMS TAB
  // ============================================================

  Widget _buildItemsTab(
      bool isMobile,
      ) {
    return Column(
      children: [
        // ------------------------------------------------------
        // SEARCH + ADD
        // ------------------------------------------------------

        Row(
          children: [
            Expanded(
              child: TextField(
                controller:
                _searchController,
                decoration:
                const InputDecoration(
                  prefixIcon:
                  Icon(Icons.search),
                  hintText:
                  'Search menu items...',
                  border:
                  OutlineInputBorder(),
                ),
                onChanged: (_) {
                  _loadAll();
                },
              ),
            ),

            const SizedBox(width: 8),

            IconButton(
              tooltip: 'Save Excel/CSV template',
              onPressed: _saveImportTemplate,
              icon: const Icon(Icons.download_outlined),
            ),

            OutlinedButton.icon(
              onPressed: _importItemsFile,
              icon: const Icon(Icons.upload_file),
              label: Text(isMobile ? 'Import' : 'Import CSV / Excel'),
            ),

            const SizedBox(width: 8),

            FilledButton.icon(
              onPressed: () {
                _openRawMaterialEditor();
              },
              icon: const Icon(
                Icons.add,
              ),
              label: Text(
                isMobile
                    ? 'Add'
                    : 'Add Item',
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // ------------------------------------------------------
        // ITEMS
        // ------------------------------------------------------

        Expanded(
          child: _items.isEmpty
              ? _emptyItems()
              : RefreshIndicator(
            onRefresh: _loadAll,
            child:
            _buildCategoryGroupedItems(
              isMobile,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CATEGORY GROUPED ITEMS
  // ============================================================

  Widget _buildCategoryGroupedItems(
      bool isMobile,
      ) {
    final Map<String, List<RawMaterial>>
    grouped = {};

    for (final item in _items) {
      final category =
      _categoryName(
        item.categoryId,
      );

      grouped.putIfAbsent(
        category,
            () => [],
      );

      grouped[category]!.add(item);
    }

    final categories =
    grouped.keys.toList();

    return ListView.builder(
      physics:
      const AlwaysScrollableScrollPhysics(),
      itemCount:
      categories.length,
      itemBuilder: (
          context,
          categoryIndex,
          ) {
        final category =
        categories[categoryIndex];

        final items =
        grouped[category]!;

        return Card(
          margin:
          const EdgeInsets.only(
            bottom: 12,
          ),
          clipBehavior:
          Clip.antiAlias,
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              // ------------------------------------------------
              // CATEGORY HEADER
              // ------------------------------------------------

              Container(
                width: double.infinity,
                padding:
                const EdgeInsets
                    .symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
                child: Row(
                  children: [
                    const Icon(
                      Icons.category_outlined,
                      size: 20,
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    Text(
                      category,
                      style: const TextStyle(
                        fontWeight:
                        FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${items.length}',
                      style: Theme.of(
                        context,
                      )
                          .textTheme
                          .bodySmall,
                    ),
                  ],
                ),
              ),

              // ------------------------------------------------
              // ITEMS
              // ------------------------------------------------

              ...items.map(
                    (item) {
                  return _buildRawMaterialCard(
                    item,
                    isMobile,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // RAW MATERIAL CARD
  // ============================================================

  Widget _buildRawMaterialCard(
      RawMaterial item,
      bool isMobile,
      ) {
    final lowStock =
        item.currentStock <=
            item.reorderLevel;

    return InkWell(
      onTap: () {
        _openRawMaterialEditor(
          existing: item,
        );
      },
      child: Padding(
        padding:
        const EdgeInsets.all(12),
        child: Row(
          children: [
            // --------------------------------------------------
            // IMAGE
            // --------------------------------------------------

            _ItemImage(
              path: item.imagePath,
              size: 70,
              icon:
              Icons.inventory_2_outlined,
            ),

            const SizedBox(width: 14),

            // --------------------------------------------------
            // DETAILS
            // --------------------------------------------------

            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style:
                    const TextStyle(
                      fontWeight:
                      FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),

                  if (item.trimmedSubItem !=
                      null) ...[
                    const SizedBox(
                      height: 2,
                    ),
                    Text(
                      item.trimmedSubItem!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],

                  const SizedBox(
                    height: 5,
                  ),

                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      _DetailText(
                        icon:
                        Icons.straighten,
                        text:
                        _unitName(
                          item.unitId,
                        ),
                      ),

                      _DetailText(
                        icon: Icons.pin,
                        text:
                        'Qty ${_formatNumber(item.qtyNeeded)}',
                      ),

                      if (item.barcode !=
                          null &&
                          item.barcode!
                              .isNotEmpty)
                        _DetailText(
                          icon:
                          Icons.qr_code,
                          text:
                          item.barcode!,
                        ),

                      if (item.costPrice !=
                          null)
                        _DetailText(
                          icon: Icons
                              .arrow_downward,
                          text:
                          'C.P. ₹${_formatNumber(item.costPrice!)}',
                        ),

                      if (item.sellingPrice !=
                          null)
                        _DetailText(
                          icon: Icons
                              .arrow_upward,
                          text:
                          'S.P. ₹${_formatNumber(item.sellingPrice!)}',
                        ),
                    ],
                  ),

                  if (item.unitsPerPacket !=
                      null) ...[
                    const SizedBox(
                      height: 4,
                    ),
                    Text(
                      '${_formatNumber(item.unitsPerPacket!)} ${_unitName(item.unitId)} / packet',
                      style: Theme.of(
                        context,
                      )
                          .textTheme
                          .bodySmall,
                    ),
                  ],
                ],
              ),
            ),

            // --------------------------------------------------
            // STOCK
            // --------------------------------------------------

            Column(
              crossAxisAlignment:
              CrossAxisAlignment.end,
              children: [
                Text(
                  _formatNumber(
                    item.currentStock,
                  ),
                  style: TextStyle(
                    fontWeight:
                    FontWeight.bold,
                    fontSize: 16,
                    color: lowStock
                        ? Colors.red
                        : null,
                  ),
                ),
                Text(
                  _unitName(
                    item.unitId,
                  ),
                  style: Theme.of(
                    context,
                  )
                      .textTheme
                      .bodySmall,
                ),

                if (lowStock)
                  const Text(
                    'LOW',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 11,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 8),

            // --------------------------------------------------
            // MENU
            // --------------------------------------------------

            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  _openRawMaterialEditor(
                    existing: item,
                  );
                }

                if (value == 'delete') {
                  _deleteRawMaterial(
                    item,
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading:
                    Icon(Icons.edit),
                    title:
                    Text('Edit'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                    ),
                    title:
                    Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // COMBOS TAB
  // ============================================================

  Widget _buildCombosTab(
      bool isMobile,
      ) {
    return Column(
      children: [
        // ------------------------------------------------------
        // COMBO HEADER
        // ------------------------------------------------------

        Row(
          children: [
            Expanded(
              child: Text(
                'Combos',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(
                  fontWeight:
                  FontWeight.bold,
                ),
              ),
            ),

            FilledButton.icon(
              onPressed: () {
                _openComboEditor();
              },
              icon: const Icon(
                Icons.add,
              ),
              label: Text(
                isMobile
                    ? 'Add'
                    : 'Add Combo',
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        Align(
          alignment:
          Alignment.centerLeft,
          child: Text(
            'Create combos from menu items.',
            style: Theme.of(context)
                .textTheme
                .bodySmall,
          ),
        ),

        const SizedBox(height: 16),

        // ------------------------------------------------------
        // COMBOS LIST
        // ------------------------------------------------------

        Expanded(
          child: _combos.isEmpty
              ? _emptyCombos()
              : RefreshIndicator(
            onRefresh: _loadAll,
            child: ListView.separated(
              physics:
              const AlwaysScrollableScrollPhysics(),
              itemCount:
              _combos.length,
              separatorBuilder:
                  (_, __) =>
              const SizedBox(
                height: 10,
              ),
              itemBuilder:
                  (context, index) {
                final combo =
                _combos[index];

                return _buildComboCard(
                  combo,
                  isMobile,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // COMBO CARD
  // ============================================================

  Widget _buildComboCard(
      Combo combo,
      bool isMobile,
      ) {
    return Card(
      clipBehavior:
      Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _openComboEditor(
            existing: combo,
          );
        },
        child: Padding(
          padding:
          const EdgeInsets.all(12),
          child: Row(
            children: [
              // ------------------------------------------------
              // IMAGE
              // ------------------------------------------------

              _ItemImage(
                path: combo.imagePath,
                size: 85,
                icon:
                Icons.collections_outlined,
              ),

              const SizedBox(width: 14),

              // ------------------------------------------------
              // COMBO INFO
              // ------------------------------------------------

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      combo.name,
                      style:
                      const TextStyle(
                        fontWeight:
                        FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),

                    const SizedBox(
                      height: 6,
                    ),

                    Text(
                      '₹${_formatNumber(combo.price)}',
                      style:
                      TextStyle(
                        fontWeight:
                        FontWeight.bold,
                        color: Theme.of(
                          context,
                        )
                            .colorScheme
                            .primary,
                      ),
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    if (combo.items.isEmpty)
                      const Text(
                        'No menu items added',
                        style:
                        TextStyle(
                          color: Colors.red,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children:
                        combo.items
                            .map(
                              (comboItem) {
                            final material =
                            _findRawMaterial(
                              comboItem
                                  .rawMaterialId,
                            );

                            final name =
                                material
                                    ?.name ??
                                    'Unknown';

                            return Chip(
                              avatar:
                              const Icon(
                                Icons
                                    .inventory_2_outlined,
                                size: 16,
                              ),
                              label:
                              Text(
                                '$name × ${_formatNumber(comboItem.qty)}',
                              ),
                            );
                          },
                        )
                            .toList(),
                      ),
                  ],
                ),
              ),

              // ------------------------------------------------
              // MENU
              // ------------------------------------------------

              PopupMenuButton<String>(
                onSelected:
                    (value) {
                  if (value ==
                      'edit') {
                    _openComboEditor(
                      existing:
                      combo,
                    );
                  }

                  if (value ==
                      'delete') {
                    _deleteCombo(
                      combo,
                    );
                  }
                },
                itemBuilder:
                    (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(
                        Icons.edit,
                      ),
                      title:
                      Text('Edit'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading:
                      Icon(
                        Icons
                            .delete_outline,
                      ),
                      title:
                      Text('Delete'),
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

  // ============================================================
  // FIND RAW MATERIAL
  // ============================================================

  RawMaterial? _findRawMaterial(
      int? id,
      ) {
    if (id == null) return null;

    for (final item in _items) {
      if (item.id == id) {
        return item;
      }
    }

    return null;
  }

  // ============================================================
  // EMPTY ITEMS
  // ============================================================

  Widget _emptyItems() {
    return const Center(
      child: Column(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 60,
          ),
          SizedBox(height: 12),
          Text(
            'No menu items yet',
            style: TextStyle(
              fontSize: 17,
              fontWeight:
              FontWeight.w600,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'Add your first raw material.',
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EMPTY COMBOS
  // ============================================================

  Widget _emptyCombos() {
    return const Center(
      child: Column(
        mainAxisSize:
        MainAxisSize.min,
        children: [
          Icon(
            Icons.collections_outlined,
            size: 60,
          ),
          SizedBox(height: 12),
          Text(
            'No combos yet',
            style: TextStyle(
              fontSize: 17,
              fontWeight:
              FontWeight.w600,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'Create a combo using raw materials.',
          ),
        ],
      ),
    );
  }

  // ============================================================
  // NUMBER FORMAT
  // ============================================================

  static String _formatNumber(
      double value,
      ) {
    return value % 1 == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }
}

// ============================================================================
// RAW MATERIAL EDITOR
// ============================================================================

class RawMaterialEditorDialog
    extends StatefulWidget {
  final RawMaterial? existing;
  final List<Category> categories;
  final List<UnitM> units;
  final Future<String?> Function()
  onPickImage;

  const RawMaterialEditorDialog({
    super.key,
    this.existing,
    required this.categories,
    required this.units,
    required this.onPickImage,
  });

  @override
  State<RawMaterialEditorDialog>
  createState() =>
      _RawMaterialEditorDialogState();
}

class _RawMaterialEditorDialogState
    extends State<RawMaterialEditorDialog> {
  final _nameController =
  TextEditingController();

  final _subItemController =
  TextEditingController();

  final _qtyController =
  TextEditingController(text: '1');

  final _barcodeController =
  TextEditingController();

  final _openingController =
  TextEditingController(text: '0');

  final _reorderController =
  TextEditingController(text: '0');

  final _shelfLifeController =
  TextEditingController();

  final _packetsController =
  TextEditingController();

  final _packetController =
  TextEditingController();

  final _costController =
  TextEditingController();

  final _sellingController =
  TextEditingController();

  final _pinController =
  TextEditingController();

  int? _categoryId;
  int? _unitId;

  String? _imagePath;

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final item =
        widget.existing;

    if (item != null) {
      _nameController.text =
          item.name;

      _subItemController.text =
          item.subItem ?? item.name;

      _qtyController.text =
          item.qtyNeeded.toString();

      _barcodeController.text =
          item.barcode ?? '';

      _openingController.text =
          item.currentStock.toString();

      if (item.unitsPerPacket != null &&
          item.unitsPerPacket! > 0 &&
          item.currentStock > 0) {
        final packets =
            item.currentStock / item.unitsPerPacket!;
        _packetsController.text = packets % 1 == 0
            ? packets.toStringAsFixed(0)
            : packets.toStringAsFixed(2);
      }

      _reorderController.text =
          item.reorderLevel.toString();

      _shelfLifeController.text =
          item.shelfLifeDays
              ?.toString() ??
              '';

      _packetController.text =
          item.unitsPerPacket
              ?.toString() ??
              '';

      _costController.text =
          item.costPrice
              ?.toString() ??
              '';

      _sellingController.text =
          item.sellingPrice
              ?.toString() ??
              '';

      _categoryId =
          item.categoryId;

      _unitId =
          item.unitId;

      _imagePath =
          item.imagePath;
    } else {
      if (widget.categories.isNotEmpty) {
        _categoryId =
            widget.categories.first.id;
      }

      if (widget.units.isNotEmpty) {
        _unitId =
            widget.units.first.id;
      }
    }

    _nameController.addListener(_copyNameToSubItem);
    _packetsController.addListener(_recalculateStock);
    _packetController.addListener(_recalculateStock);
  }

  void _recalculateStock() {
    final packets =
        double.tryParse(_packetsController.text.trim()) ?? 0;
    final perPacket =
        double.tryParse(_packetController.text.trim()) ?? 0;

    if (packets <= 0 || perPacket <= 0) return;

    final stock = packets * perPacket;
    final text = stock % 1 == 0
        ? stock.toStringAsFixed(0)
        : stock.toStringAsFixed(2);

    if (_openingController.text == text) return;
    _openingController.text = text;
  }

  void _copyNameToSubItem() {
    _subItemController.value = TextEditingValue(
      text: _nameController.text,
      selection: TextSelection.collapsed(
        offset: _nameController.text.length,
      ),
    );
  }

  @override
  void dispose() {
    _nameController.removeListener(_copyNameToSubItem);
    _packetsController.removeListener(_recalculateStock);
    _packetController.removeListener(_recalculateStock);
    _nameController.dispose();
    _subItemController.dispose();
    _qtyController.dispose();
    _barcodeController.dispose();
    _openingController.dispose();
    _reorderController.dispose();
    _shelfLifeController.dispose();
    _packetsController.dispose();
    _packetController.dispose();
    _costController.dispose();
    _sellingController.dispose();
    _pinController.dispose();

    super.dispose();
  }

  // ============================================================
  // PICK IMAGE
  // ============================================================

  Future<void> _pickImage() async {
    final path =
    await widget.onPickImage();

    if (path == null) return;

    setState(() {
      _imagePath = path;
    });
  }

  // ============================================================
  // SAVE
  // ============================================================

  Future<void> _save() async {
    if (_saving) return;

    final name =
    _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Enter item name',
          ),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final item =
      RawMaterial(
        id: widget.existing?.id,
        barcode:
        _barcodeController.text
            .trim()
            .isEmpty
            ? null
            : _barcodeController.text
            .trim(),
        name: name,
        subItem:
        _subItemController.text.trim().isEmpty
            ? null
            : _subItemController.text.trim(),
        qtyNeeded:
        double.tryParse(
          _qtyController.text.trim(),
        ) ??
            1,
        categoryId:
        _categoryId,
        unitId:
        _unitId,
        openingStock:
        double.tryParse(
          _openingController
              .text
              .trim(),
        ) ??
            0,
        currentStock:
        double.tryParse(
          _openingController
              .text
              .trim(),
        ) ??
            0,
        reorderLevel:
        double.tryParse(
          _reorderController
              .text
              .trim(),
        ) ??
            0,
        shelfLifeDays:
        int.tryParse(
          _shelfLifeController
              .text
              .trim(),
        ),
        unitsPerPacket:
        _packetController.text
            .trim()
            .isEmpty
            ? null
            : double.tryParse(
          _packetController
              .text
              .trim(),
        ),
        entryPasswordHash:
        widget.existing
            ?.entryPasswordHash,
        costPrice:
        _costController.text
            .trim()
            .isEmpty
            ? null
            : double.tryParse(
          _costController
              .text
              .trim(),
        ),
        sellingPrice:
        _sellingController.text
            .trim()
            .isEmpty
            ? null
            : double.tryParse(
          _sellingController
              .text
              .trim(),
        ),
        imagePath:
        _imagePath,
      );

      await Repository.instance
          .saveRawMaterial(
        item,
      );

      if (!mounted) return;

      Navigator.pop(
        context,
        true,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Failed to save: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  static const double _fieldGap = 8;

  InputDecoration _fieldDecoration(
    String label, {
    String? hint,
    IconData? prefix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      border: const OutlineInputBorder(),
      prefixIcon: prefix == null ? null : Icon(prefix, size: 18),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
    );
  }

  Widget _twoFields(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: _fieldGap),
        Expanded(child: right),
      ],
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    final width =
        MediaQuery.of(context)
            .size
            .width;

    final height =
        MediaQuery.of(context).size.height;

    final dialogWidth =
    width < Breakpoints.mobile
        ? width * .94
        : 720.0;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: dialogWidth,
        height: height * 0.9,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existing ==
                    null
                    ? 'Add Item'
                    : 'Edit Item',
                style:
                const TextStyle(
                  fontSize: 18,
                  fontWeight:
                  FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Center(
                child: Stack(
                  children: [
                    _ItemImage(
                      path: _imagePath,
                      size: 56,
                      icon: Icons.inventory_2_outlined,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: FloatingActionButton.small(
                        onPressed: _pickImage,
                        child: const Icon(Icons.camera_alt),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              DropdownButtonFormField<int>(
                value: _categoryId,
                isExpanded: true,
                isDense: true,
                decoration: _fieldDecoration('Category'),
                items: widget.categories
                    .map(
                      (category) => DropdownMenuItem<int>(
                        value: category.id,
                        child: Text(
                          category.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _categoryId = value;
                  });
                },
              ),

              const SizedBox(height: _fieldGap),

              _twoFields(
                TextField(
                  controller: _nameController,
                  decoration: _fieldDecoration(
                    'Item Name',
                    prefix: Icons.inventory_2_outlined,
                  ),
                ),
                TextField(
                  controller: _subItemController,
                  decoration: _fieldDecoration(
                    'Sub Item',
                    prefix: Icons.subdirectory_arrow_right,
                  ),
                ),
              ),

              const SizedBox(height: _fieldGap),

              BarcodeField(
                controller: _barcodeController,
                isDense: true,
              ),

              const SizedBox(height: _fieldGap),

              _twoFields(
                TextField(
                  controller: _qtyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _fieldDecoration(
                    'Qty / sale',
                    hint: '1.5',
                  ),
                ),
                TextField(
                  controller: _packetsController,
                  enabled: true,
                  readOnly: false,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _fieldDecoration('Packets'),
                ),
              ),

              const SizedBox(height: _fieldGap),

              _twoFields(
                TextField(
                  controller: _packetController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _fieldDecoration('Units / packet'),
                ),
                TextField(
                  controller: _openingController,
                  enabled: true,
                  readOnly: false,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _fieldDecoration('Stock'),
                ),
              ),

              const SizedBox(height: _fieldGap),

              _twoFields(
                TextField(
                  controller: _costController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _fieldDecoration('C.P. (₹)'),
                ),
                TextField(
                  controller: _sellingController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _fieldDecoration('S.P. (₹)'),
                ),
              ),

              const SizedBox(height: _fieldGap),

              DropdownButtonFormField<int>(
                value: _unitId,
                isExpanded: true,
                isDense: true,
                decoration: _fieldDecoration('Unit'),
                items: widget.units
                    .map(
                      (unit) => DropdownMenuItem<int>(
                        value: unit.id,
                        child: Text(
                          '${unit.name} (${unit.shortCode})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _unitId = value;
                  });
                },
              ),

              const Spacer(),

              Row(
                mainAxisAlignment:
                MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                    _saving
                        ? null
                        : () {
                      Navigator.pop(
                        context,
                      );
                    },
                    child:
                    const Text(
                      'Cancel',
                    ),
                  ),
                  const SizedBox(
                    width: 8,
                  ),
                  FilledButton.icon(
                    onPressed:
                    _saving
                        ? null
                        : _save,
                    icon: _saving
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child:
                      CircularProgressIndicator(
                        strokeWidth:
                        2,
                      ),
                    )
                        : const Icon(
                      Icons.save,
                    ),
                    label:
                    const Text(
                      'Save',
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
}

// ============================================================================
// COMBO EDITOR
// ============================================================================

class ComboEditorDialog
    extends StatefulWidget {
  final Combo? existing;
  final List<RawMaterial> rawMaterials;
  final String Function(int?) unitName;
  final Future<String?> Function()
  onPickImage;

  const ComboEditorDialog({
    super.key,
    this.existing,
    required this.rawMaterials,
    required this.unitName,
    required this.onPickImage,
  });

  @override
  State<ComboEditorDialog>
  createState() =>
      _ComboEditorDialogState();
}

class _ComboEditorDialogState
    extends State<ComboEditorDialog> {
  final _nameController =
  TextEditingController();

  final _priceController =
  TextEditingController();

  String? _imagePath;

  final List<_ComboLine>
  _lines = [];

  bool _saving = false;

  @override
  void initState() {
    super.initState();

    final combo =
        widget.existing;

    if (combo != null) {
      _nameController.text =
          combo.name;

      _priceController.text =
          combo.price.toString();

      _imagePath =
          combo.imagePath;

      for (final item
      in combo.items) {
        _lines.add(
          _ComboLine(
            rawMaterialId:
            item.rawMaterialId,
            qty: item.qty,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();

    super.dispose();
  }

  // ============================================================
  // PICK IMAGE
  // ============================================================

  Future<void> _pickImage() async {
    final path =
    await widget.onPickImage();

    if (path == null) return;

    setState(() {
      _imagePath = path;
    });
  }

  // ============================================================
  // ADD RAW MATERIAL
  // ============================================================

  void _addLine() {
    if (widget.rawMaterials.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Add raw materials first.',
          ),
        ),
      );
      return;
    }

    final available =
    widget.rawMaterials
        .where(
          (material) =>
      !_lines.any(
            (line) =>
        line.rawMaterialId ==
            material.id,
      ),
    )
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'All raw materials have already been added.',
          ),
        ),
      );
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _lines.add(
          _ComboLine(
            rawMaterialId: available.first.id,
            qty: 1,
          ),
        );
      });
    });
  }

  // ============================================================
  // REMOVE LINE
  // ============================================================

  void _removeLine(
      int index,
      ) {
    setState(() {
      _lines.removeAt(index);
    });
  }

  // ============================================================
  // SAVE COMBO
  // ============================================================

  Future<void> _save() async {
    if (_saving) return;

    final name =
    _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Enter combo name.',
          ),
        ),
      );
      return;
    }

    final price =
        double.tryParse(
          _priceController.text
              .trim(),
        ) ??
            0;

    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Add at least one raw material to the combo.',
          ),
        ),
      );
      return;
    }

    for (final line in _lines) {
      if (line.rawMaterialId ==
          null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text(
              'Select a raw material for every row.',
            ),
          ),
        );
        return;
      }

      if (line.qty <= 0) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text(
              'Quantity must be greater than zero.',
            ),
          ),
        );
        return;
      }
    }

    setState(() {
      _saving = true;
    });

    try {
      final combo = Combo(
        id: widget.existing?.id,
        name: name,
        barcode: widget.existing?.barcode,
        categoryId: widget.existing?.categoryId,
        price: price,
        imagePath: _imagePath,
        isActive: widget.existing?.isActive ?? true,
      );

      final comboRawMaterials = _lines.map((line) {
        return ComboRawMaterial(
          id: null,

          // For a NEW combo there is no ID yet.
          // saveCombo() will replace this with the actual generated ID.
          comboId: widget.existing?.id ?? 0,

          rawMaterialId: line.rawMaterialId!,
          qty: line.qty,
        );
      }).toList();

      await Repository.instance.saveCombo(
        combo,
        comboRawMaterials,
      );
      if (!mounted) return;

      Navigator.pop(
        context,
        true,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Failed to save combo: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    final width =
        MediaQuery.of(context)
            .size
            .width;

    final height =
        MediaQuery.of(context).size.height;

    final dialogWidth =
    width < Breakpoints.mobile
        ? width * .94
        : 650.0;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: dialogWidth,
        height: height * 0.9,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ==================================================
              // TITLE
              // ==================================================

              Text(
                widget.existing ==
                    null
                    ? 'Add Combo'
                    : 'Edit Combo',
                style:
                const TextStyle(
                  fontSize: 20,
                  fontWeight:
                  FontWeight.bold,
                ),
              ),

              const SizedBox(
                height: 20,
              ),

              // ==================================================
              // IMAGE
              // ==================================================

              Center(
                child: Stack(
                  children: [
                    _ItemImage(
                      path:
                      _imagePath,
                      size: 130,
                      icon: Icons
                          .collections_outlined,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child:
                      FloatingActionButton
                          .small(
                        onPressed:
                        _pickImage,
                        child:
                        const Icon(
                          Icons
                              .camera_alt,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                height: 20,
              ),

              // ==================================================
              // NAME
              // ==================================================

              TextField(
                controller:
                _nameController,
                decoration:
                const InputDecoration(
                  labelText:
                  'Combo Name',
                  border:
                  OutlineInputBorder(),
                  prefixIcon:
                  Icon(
                    Icons
                        .collections_outlined,
                  ),
                ),
              ),

              const SizedBox(
                height: 12,
              ),

              // ==================================================
              // PRICE
              // ==================================================

              TextField(
                controller:
                _priceController,
                keyboardType:
                const TextInputType
                    .numberWithOptions(
                  decimal: true,
                ),
                decoration:
                const InputDecoration(
                  labelText:
                  'Combo Price (₹)',
                  border:
                  OutlineInputBorder(),
                  prefixIcon:
                  Icon(Icons.currency_rupee),
                ),
              ),

              const SizedBox(
                height: 20,
              ),

              // ==================================================
              // RAW MATERIALS HEADER
              // ==================================================

              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Menu Items',
                      style:
                      TextStyle(
                        fontSize: 17,
                        fontWeight:
                        FontWeight.bold,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                    _addLine,
                    icon: const Icon(
                      Icons.add,
                    ),
                    label:
                    const Text(
                      'Add Item',
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: 10,
              ),

              // ==================================================
              // RAW MATERIAL LINES
              // ==================================================

              Expanded(
                child: _lines.isEmpty
                    ? Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).dividerColor,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      'No menu items added.\nTap "Add Item".',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
                    : ListView.builder(
                  itemCount: _lines.length,
                  itemBuilder: (context, index) {
                    return _buildComboLine(
                      index,
                      _lines[index],
                    );
                  },
                ),
              ),

              const SizedBox(
                height: 20,
              ),

              // ==================================================
              // BUTTONS
              // ==================================================

              Row(
                mainAxisAlignment:
                MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                    _saving
                        ? null
                        : () {
                      Navigator.pop(
                        context,
                      );
                    },
                    child:
                    const Text(
                      'Cancel',
                    ),
                  ),
                  const SizedBox(
                    width: 8,
                  ),
                  FilledButton.icon(
                    onPressed:
                    _saving
                        ? null
                        : _save,
                    icon: _saving
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child:
                      CircularProgressIndicator(
                        strokeWidth:
                        2,
                      ),
                    )
                        : const Icon(
                      Icons.save,
                    ),
                    label:
                    const Text(
                      'Save Combo',
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

  // ============================================================
  // COMBO LINE
  // ============================================================

  Widget _buildComboLine(
      int index,
      _ComboLine line,
      ) {
    return Padding(
      padding:
      const EdgeInsets.only(
        bottom: 10,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child:
            DropdownButtonFormField<
                int>(
              isExpanded: true,
              isDense: true,
              value:
              line.rawMaterialId,
              decoration:
              const InputDecoration(
                labelText:
                'Menu Item',
                isDense: true,
                border:
                OutlineInputBorder(),
              ),
              items: widget
                  .rawMaterials
                  .where(
                    (material) {
                  return !_lines.any(
                        (other) =>
                    other !=
                        line &&
                        other
                            .rawMaterialId ==
                            material
                                .id,
                  ) ||
                      material.id ==
                          line
                              .rawMaterialId;
                },
              )
                  .map(
                    (material) {
                  final sub =
                      material.trimmedSubItem;
                  return DropdownMenuItem<
                      int>(
                    value:
                    material.id,
                    child: Text(
                      sub == null
                          ? material.name
                          : '${material.name} ($sub)',
                      overflow:
                      TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  );
                },
              )
                  .toList(),
              onChanged:
                  (value) {
                setState(() {
                  line.rawMaterialId =
                      value;
                });
              },
            ),
          ),

          const SizedBox(
            width: 10,
          ),

          Expanded(
            flex: 1,
            child:
            TextFormField(
              initialValue:
              line.qty
                  .toString(),
              keyboardType:
              const TextInputType
                  .numberWithOptions(
                decimal: true,
              ),
              decoration:
              InputDecoration(
                labelText:
                'Qty',
                border:
                const OutlineInputBorder(),
                suffixText:
                line.rawMaterialId !=
                    null
                    ? widget
                    .unitName(
                  widget
                      .rawMaterials
                      .firstWhere(
                        (item) =>
                    item.id ==
                        line
                            .rawMaterialId,
                    orElse:
                        () =>
                        RawMaterial(
                          name:
                          '',
                        ),
                  )
                      .unitId,
                )
                    : null,
              ),
              onChanged:
                  (value) {
                line.qty =
                    double.tryParse(
                      value,
                    ) ??
                        0;
              },
            ),
          ),

          IconButton(
            tooltip:
            'Remove',
            icon:
            const Icon(
              Icons
                  .delete_outline,
              color:
              Colors.red,
            ),
            onPressed:
                () {
              _removeLine(
                index,
              );
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// COMBO LINE STATE
// ============================================================================

class _ComboLine {
  int? rawMaterialId;
  double qty;

  _ComboLine({
    required this.rawMaterialId,
    required this.qty,
  });
}

// ============================================================================
// IMAGE WIDGET
// ============================================================================

class _ItemImage
    extends StatelessWidget {
  final String? path;
  final double size;
  final IconData icon;

  const _ItemImage({
    required this.path,
    required this.size,
    required this.icon,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    final hasImage =
        path != null &&
            path!.trim().isNotEmpty &&
            File(path!).existsSync();

    return Container(
      width: size,
      height: size,
      decoration:
      BoxDecoration(
        borderRadius:
        BorderRadius.circular(
          10,
        ),
        border: Border.all(
          color: Theme.of(context)
              .dividerColor,
        ),
      ),
      clipBehavior:
      Clip.antiAlias,
      child: hasImage
          ? Image.file(
        File(path!),
        fit: BoxFit.cover,
      )
          : Container(
        color: Theme.of(
          context,
        )
            .colorScheme
            .surfaceContainerHighest,
        child: Icon(
          icon,
          size:
          size * .42,
        ),
      ),
    );
  }
}

// ============================================================================
// SMALL DETAIL TEXT
// ============================================================================

class _DetailText
    extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DetailText({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(
      BuildContext context,
      ) {
    return Row(
      mainAxisSize:
      MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
        ),
        const SizedBox(
          width: 3,
        ),
        Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodySmall,
        ),
      ],
    );
  }
}
