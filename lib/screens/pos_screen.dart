import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/combo_only_categories.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/printer_service.dart';
import 'package:foodstock/services/repository.dart';
import 'package:foodstock/services/variant_helpers.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final Repository _repo = Repository.instance;

  final TextEditingController _searchController =
  TextEditingController();

  final TextEditingController _taxController =
  TextEditingController(text: '0');

  final TextEditingController _discountController =
  TextEditingController(text: '0');

  final TextEditingController _barcodeController =
  TextEditingController();

  final TextEditingController _customerNameController =
  TextEditingController();

  final TextEditingController _customerPhoneController =
  TextEditingController();

  final ScrollController _cartScrollController =
  ScrollController();

  static const int _uncategorizedFilter = -1;

  List<RawMaterial> _materials = [];
  List<Combo> _combos = [];
  List<Category> _categories = [];
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _pendingOrders = [];
  int? _adminLocationId;
  int? _categoryId;
  int? _activePendingId;

  final List<CartLine> _cart = [];

  String _paymentType = 'Cash';

  bool _loading = true;
  bool _saving = false;
  bool _cartSheetOpen = false;
  int _lastAddTapMs = 0;

  /// Selected variant raw_material id per [VariantGroup.key].
  final Map<String, int> _selectedVariantIdByGroup = {};

  Set<int?> _comboOnlyCategoryIds = {};

  bool get _adminViewOnly => _repo.isAdmin;

  Map<int, RawMaterial> get _materialsById {
    return {
      for (final material in _materials)
        if (material.id != null) material.id!: material,
    };
  }

  void Function(VoidCallback)? _sheetSetState;

  void _refreshUi() {
    if (mounted) setState(() {});
    _sheetSetState?.call(() {});
  }

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _loadData();

    _searchController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _searchController.dispose();
    _taxController.dispose();
    _discountController.dispose();
    _barcodeController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _cartScrollController.dispose();

    super.dispose();
  }

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      await _repo.refreshVariantLinks();
      final materials = await _repo.rawMaterials();
      final combos = await _repo.combosWithItems(activeOnly: true);
      final categories = await _repo.categories(type: 'raw_material');
      List<Map<String, dynamic>> locations = [];

      if (_repo.isAdmin) {
        locations = await _repo.locations();
        if (locations.isNotEmpty) {
          _adminLocationId ??= locations.first['id'] as int;
          _repo.setAdminSaleLocation(_adminLocationId);
        }
      }

      if (!mounted) return;

      setState(() {
        _materials = materials;
        _combos = combos;
        _categories = categories;
        _locations = locations;
        _loading = false;
        _comboOnlyCategoryIds = ComboOnlyCategories.categoryIds(
          materials: materials,
          combos: combos,
        );
        _seedDefaultVariantSelections(materials);
        if (_categoryId != null &&
            !_categoryIdsWithItems.contains(_categoryId)) {
          _categoryId = null;
        }
      });

      await _loadPendingOrders();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      _showError(
        'Failed to load POS data: $e',
      );
    }
  }

  Future<void> _refreshStock() async {
    try {
      final materials = await _repo.rawMaterials();
      final combos = await _repo.combosWithItems(activeOnly: true);

      if (!mounted) return;

      setState(() {
        _materials = materials;
        _combos = combos;
        _comboOnlyCategoryIds = ComboOnlyCategories.categoryIds(
          materials: materials,
          combos: combos,
        );
      });
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Failed to refresh stock: $e',
      );
    }
  }

  // ============================================================
  // SEARCH
  // ============================================================

  String get _search =>
      _searchController.text.trim().toLowerCase();

  String? _categoryName(int? categoryId) {
    if (categoryId == null) return null;
    for (final category in _categories) {
      if (category.id == categoryId) {
        return category.name;
      }
    }
    return null;
  }

  bool _isComboOnlyCategory(int? categoryId) {
    return _comboOnlyCategoryIds.contains(categoryId);
  }

  bool _isDirectSaleMaterial(RawMaterial material) {
    return ComboOnlyCategories.isDirectSaleMaterial(
      material,
      comboOnlyCategoryIds: _comboOnlyCategoryIds,
    );
  }

  List<RawMaterial> get _allMaterials => _materials;

  List<Combo> get _activeCombos => _combos
      .where(
        (combo) =>
            combo.isActive && combo.id != null && combo.items.isNotEmpty,
      )
      .toList();

  Set<int?> get _categoryIdsWithItems {
    final ids = {
      for (final material in _allMaterials)
        if (_isDirectSaleMaterial(material)) material.categoryId,
    };
    for (final combo in _activeCombos) {
      ids.add(combo.categoryId);
    }
    ids.removeWhere((id) => _isComboOnlyCategory(id));
    return ids;
  }

  List<Category> get _categoriesWithItems {
    final ids = _categoryIdsWithItems;
    final seen = <String>{};
    final result = <Category>[];
    for (final category in _categories) {
      if (!ids.contains(category.id)) continue;
      final label = _categoryLabel(category.name).toLowerCase();
      if (seen.contains(label)) continue;
      seen.add(label);
      result.add(category);
    }
    return result;
  }

  List<RawMaterial> get _filteredMaterials {
    var list = _allMaterials.where(_isDirectSaleMaterial).toList();
    if (_categoryId == _uncategorizedFilter) {
      list = list.where((material) => material.categoryId == null).toList();
    } else if (_categoryId != null) {
      list = list
          .where((material) => material.categoryId == _categoryId)
          .toList();
    }
    if (_search.isEmpty) {
      return list;
    }

    return list.where((material) {
      final name = material.name.toLowerCase();
      final subItem = material.trimmedSubItem?.toLowerCase() ?? '';
      final barcode = material.barcode?.toLowerCase() ?? '';
      final variantGroup = material.variantGroup?.toLowerCase() ?? '';
      final variantLabel = material.variantLabel?.toLowerCase() ?? '';
      return name.contains(_search) ||
          subItem.contains(_search) ||
          barcode.contains(_search) ||
          variantGroup.contains(_search) ||
          variantLabel.contains(_search);
    }).toList();
  }

  List<Combo> get _filteredCombos {
    if (_categoryId == _uncategorizedFilter) {
      return const [];
    }

    var list = _activeCombos;
    if (_categoryId != null) {
      list = list
          .where((combo) => combo.categoryId == _categoryId)
          .toList();
    }

    if (_search.isEmpty) {
      return list;
    }

    return list.where(_comboMatchesSearch).toList();
  }

  bool _comboMatchesSearch(Combo combo) {
    final name = combo.name.toLowerCase();
    final barcode = combo.barcode?.toLowerCase() ?? '';
    if (name.contains(_search) || barcode.contains(_search)) {
      return true;
    }

    for (final item in combo.items) {
      final itemName = item.materialName?.toLowerCase() ?? '';
      final subItem = item.materialSubItem?.toLowerCase() ?? '';
      if (itemName.contains(_search) || subItem.contains(_search)) {
        return true;
      }
    }
    return false;
  }

  bool _guardRapidTap() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastAddTapMs < 400) {
      return false;
    }
    _lastAddTapMs = now;
    return true;
  }

  List<String> _componentLabelsForCombo(Combo combo) {
    return combo.items
        .map((item) => item.itemNameLabel)
        .where((label) => label.isNotEmpty)
        .toList();
  }

  Future<void> _loadPendingOrders() async {
    try {
      final rows = await _repo.pendingOrders();
      if (!mounted) return;
      setState(() {
        _pendingOrders = rows;
      });
    } catch (_) {}
  }

  Future<void> _persistActivePending() async {
    if (_activePendingId == null) return;
    await _repo.savePendingOrder(
      pendingOrderId: _activePendingId!,
      lines: _cart,
      tax: _tax,
      discount: _discount,
      customerName: _customerNameController.text.trim().isEmpty
          ? null
          : _customerNameController.text.trim(),
      customerPhone: _customerPhoneController.text.trim().isEmpty
          ? null
          : _customerPhoneController.text.trim(),
    );
    await _loadPendingOrders();
  }

  Future<void> _createNewToken() async {
    if (_adminViewOnly) return;
    await _persistActivePending();
    final id = await _repo.createPendingOrder();
    if (!mounted) return;
    setState(() {
      _activePendingId = id;
      _cart.clear();
      _taxController.text = '0';
      _discountController.text = '0';
      _customerNameController.clear();
      _customerPhoneController.clear();
    });
    await _loadPendingOrders();
  }

  Future<void> _selectPendingOrder(int pendingId) async {
    if (_adminViewOnly) return;
    await _persistActivePending();
    final header = await _repo.pendingOrderById(pendingId);
    final lines = await _repo.pendingOrderLines(pendingId);
    if (!mounted || header == null) return;
    setState(() {
      _activePendingId = pendingId;
      _cart
        ..clear()
        ..addAll(lines);
      _taxController.text =
          ((header['tax'] as num?)?.toDouble() ?? 0).toStringAsFixed(0);
      _discountController.text =
          ((header['discount'] as num?)?.toDouble() ?? 0).toStringAsFixed(0);
      _customerNameController.text =
          header['customer_name']?.toString() ?? '';
      _customerPhoneController.text =
          header['customer_phone']?.toString() ?? '';
    });
    _refreshUi();
  }

  Future<void> _showPendingTokensSheet() async {
    await _loadPendingOrders();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Pending Tokens',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _createNewToken();
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New Token'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _pendingOrders.isEmpty
                    ? const Center(child: Text('No pending tokens'))
                    : ListView.separated(
                        itemCount: _pendingOrders.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final row = _pendingOrders[index];
                          final id = row['id'] as int;
                          final token = row['token_number'] as int;
                          final total =
                              (row['running_total'] as num?)?.toDouble() ?? 0;
                          final selected = _activePendingId == id;
                          return ListTile(
                            selected: selected,
                            title: Text('Token $token'),
                            subtitle: Text(
                              '₹${total.toStringAsFixed(2)}',
                            ),
                            trailing: selected
                                ? const Icon(Icons.check_circle)
                                : null,
                            onTap: () async {
                              Navigator.pop(ctx);
                              await _selectPendingOrder(id);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<({String title, List<_PosGridEntry> entries, List<Combo> combos})>
      get _productSections {
    final items = _filteredMaterials;
    final combos = _filteredCombos;

    if (items.isEmpty && combos.isEmpty) {
      return const [];
    }

    List<_PosGridEntry> entriesFor(List<RawMaterial> materials) {
      final partition = VariantHelpers.partitionForPos(materials);
      return [
        ...partition.groups.map(_PosGridEntry.variant),
        ...partition.singles.map(_PosGridEntry.material),
      ];
    }

    if (_categoryId != null) {
      final title = _categoryId == _uncategorizedFilter
          ? 'Other'
          : _categoryName(_categoryId!) ?? 'Category';
      return [
        (
          title: title,
          entries: entriesFor(items),
          combos: combos,
        ),
      ];
    }

    final materialGroups = <int?, List<RawMaterial>>{};
    for (final material in items) {
      materialGroups.putIfAbsent(material.categoryId, () => []).add(material);
    }

    final comboGroups = <int?, List<Combo>>{};
    for (final combo in combos) {
      comboGroups.putIfAbsent(combo.categoryId, () => []).add(combo);
    }

    final sections =
        <({String title, List<_PosGridEntry> entries, List<Combo> combos})>[];
    for (final category in _categories) {
      final materials = materialGroups.remove(category.id) ?? const [];
      final categoryCombos = comboGroups.remove(category.id) ?? const [];
      if (materials.isEmpty && categoryCombos.isEmpty) continue;
      sections.add((
        title: _categoryLabel(category.name),
        entries: entriesFor(materials),
        combos: categoryCombos,
      ));
    }

    final uncategorizedMaterials = materialGroups.remove(null) ?? const [];
    final uncategorizedCombos = comboGroups.remove(null) ?? const [];
    if (uncategorizedMaterials.isNotEmpty || uncategorizedCombos.isNotEmpty) {
      sections.add((
        title: 'Other',
        entries: entriesFor(uncategorizedMaterials),
        combos: uncategorizedCombos,
      ));
    }

    for (final entry in materialGroups.entries) {
      final materials = entry.value;
      final categoryCombos = comboGroups.remove(entry.key) ?? const [];
      if (materials.isEmpty && categoryCombos.isEmpty) continue;
      sections.add((
        title: _categoryName(entry.key) ?? 'Other',
        entries: entriesFor(materials),
        combos: categoryCombos,
      ));
    }

    for (final entry in comboGroups.entries) {
      if (entry.value.isEmpty) continue;
      sections.add((
        title: _categoryName(entry.key) ?? 'Other',
        entries: const [],
        combos: entry.value,
      ));
    }

    return sections;
  }

  // ============================================================
  // BARCODE
  // ============================================================

  Future<void> _handleBarcode(
      String value,
      ) async {
    final barcode = value.trim();

    if (barcode.isEmpty) {
      return;
    }

    _barcodeController.clear();

    try {
      final material =
      await _repo.rawMaterialByBarcode(
        barcode,
      );

      if (material == null) {
        final combo = await _repo.comboByBarcode(barcode);
        if (combo == null) {
          _showError(
            'No item found for barcode "$barcode".',
          );
          return;
        }
        _addCombo(combo);
        return;
      }

      if (!_isDirectSaleMaterial(material)) {
        final categoryName = _categoryName(material.categoryId) ?? 'this category';
        _showError(
          'Items in $categoryName are sold through combos only. Select a combo instead.',
        );
        return;
      }

      _addRawMaterial(material);
    } catch (e) {
      _showError(
        'Barcode lookup failed: $e',
      );
    }
  }

  // ============================================================
  // STOCK
  // ============================================================

  double _stockForMaterial(
      RawMaterial material,
      ) {
    return VariantHelpers.stockCount(material, _materialsById);
  }

  RawMaterial _selectedVariant(VariantGroup group) {
    final selectedId = _selectedVariantIdByGroup[group.key];
    if (selectedId != null) {
      for (final variant in group.variants) {
        if (variant.id == selectedId) return variant;
      }
    }

    return _defaultVariantForGroup(group);
  }

  double _cartQtyForVariantGroup(VariantGroup group) {
    var total = 0.0;
    for (final variant in group.variants) {
      if (variant.id == null) continue;
      total += _cartQtyForRaw(variant.id!);
    }
    return total;
  }

  // ============================================================
  // CART HELPERS
  // ============================================================

  int _cartIndexForRawMaterial(RawMaterial material) {
    if (material.id == null) return -1;
    final label = _variantLabelFor(material);
    return _cart.indexWhere(
      (line) =>
          line.rawMaterialId == material.id &&
          (line.variantLabel ?? '') == label,
    );
  }

  int _cartIndexForRaw(
      int id,
      ) {
    return _cart.indexWhere(
          (line) => line.rawMaterialId == id,
    );
  }

  int _cartIndexForCombo(
      int id,
      ) {
    return _cart.indexWhere(
          (line) => line.comboId == id,
    );
  }

  double _cartQtyForCombo(
      int id,
      ) {
    final index = _cartIndexForCombo(id);
    if (index == -1) {
      return 0;
    }
    return _cart[index].qty;
  }

  double _cartQtyForRawMaterial(RawMaterial material) {
    final index = _cartIndexForRawMaterial(material);
    if (index == -1) return 0;
    return _cart[index].qty;
  }

  double _cartQtyForRaw(
      int id,
      ) {
    final index =
    _cartIndexForRaw(id);

    if (index == -1) {
      return 0;
    }

    return _cart[index].qty;
  }

  String _variantLabelFor(RawMaterial material) {
    return VariantHelpers.variantSelectorLabel(material);
  }

  void _onVariantTapped(VariantGroup group, RawMaterial variant) {
    final id = variant.id;
    if (id == null) return;

    final alreadySelected = _selectedVariantIdByGroup[group.key] == id;
    setState(() => _selectedVariantIdByGroup[group.key] = id);
    if (alreadySelected) {
      _addRawMaterial(variant);
    } else {
      _addRawMaterial(variant, replaceQty: false);
    }
  }

  void _seedDefaultVariantSelections(List<RawMaterial> materials) {
    final partition = VariantHelpers.partitionForPos(materials);
    for (final group in partition.groups) {
      final defaultVariant = _defaultVariantForGroup(group);
      if (defaultVariant.id == null) continue;
      _selectedVariantIdByGroup.putIfAbsent(
        group.key,
        () => defaultVariant.id!,
      );
    }
  }

  RawMaterial _defaultVariantForGroup(VariantGroup group) {
    for (final variant in group.variants) {
      if (variant.sellingPrice != null && variant.id != null) {
        return variant;
      }
    }
    return group.variants.first;
  }

  // ============================================================
  // ADD RAW MATERIAL
  // ============================================================

  void _addRawMaterial(
      RawMaterial material, {
      double qty = 1,
      bool replaceQty = false,
      }) {
    if (material.id == null) {
      return;
    }

    if (material.sellingPrice == null) {
      _showError(
        'Set a selling price for "${material.name}" in Menu Items before selling it.',
      );
      return;
    }

    if (qty <= 0) {
      return;
    }

    final variantLabel = _variantLabelFor(material);
    final index = _cartIndexForRawMaterial(material);

    if (index == -1) {
      _cart.add(
        CartLine(
          rawMaterialId: material.id,
          name: material.name,
          subItem: material.trimmedSubItem,
          variantLabel: variantLabel,
          qty: qty,
          price: material.sellingPrice ?? 0,
        ),
      );
      _refreshUi();
      unawaited(_persistActivePending());
      return;
    }

    final old = _cart[index];
    _cart[index] = CartLine(
      rawMaterialId: old.rawMaterialId,
      comboId: old.comboId,
      name: old.name,
      subItem: old.subItem,
      variantLabel: old.variantLabel,
      componentLabels: old.componentLabels,
      qty: replaceQty ? qty : old.qty + qty,
      price: old.price,
    );
    _refreshUi();
    unawaited(_persistActivePending());
  }

  void _addCombo(
      Combo combo,
      ) {
    if (!_guardRapidTap()) return;

    if (combo.id == null) {
      return;
    }

    if (combo.items.isEmpty) {
      _showError(
        'This combo has no component items yet.',
      );
      return;
    }

    final index = _cartIndexForCombo(combo.id!);
    final labels = _componentLabelsForCombo(combo);

    if (index == -1) {
      _cart.add(
        CartLine(
          comboId: combo.id,
          name: combo.name,
          componentLabels: labels,
          qty: 1,
          price: combo.price,
        ),
      );
      _refreshUi();
      unawaited(_persistActivePending());
      return;
    }

    final old = _cart[index];
    _cart[index] = CartLine(
      rawMaterialId: old.rawMaterialId,
      comboId: old.comboId,
      name: old.name,
      subItem: old.subItem,
      componentLabels: old.componentLabels,
      qty: old.qty + 1,
      price: old.price,
    );
    _refreshUi();
    unawaited(_persistActivePending());
  }

  // ============================================================
  // CHANGE QUANTITY
  // ============================================================

  void _changeQuantity(
      int index,
      double newQty,
      ) {
    if (index < 0 ||
        index >= _cart.length) {
      return;
    }

    // Remove line.
    if (newQty <= 0) {
      _cart.removeAt(index);
      _refreshUi();
      unawaited(_persistActivePending());
      return;
    }

    final line =
    _cart[index];

    if (line.rawMaterialId == null && line.comboId == null) {
      return;
    }

    _cart[index] = CartLine(
      rawMaterialId: line.rawMaterialId,
      comboId: line.comboId,
      name: line.name,
      subItem: line.subItem,
      variantLabel: line.variantLabel,
      componentLabels: line.componentLabels,
      qty: newQty,
      price: line.price,
    );
    _refreshUi();
    unawaited(_persistActivePending());
  }

  // ============================================================
  // REMOVE CART LINE
  // ============================================================

  void _removeLine(
      int index,
      ) {
    if (index < 0 ||
        index >= _cart.length) {
      return;
    }

    _cart.removeAt(index);
    _refreshUi();
    unawaited(_persistActivePending());
  }

  void _clearCart() {
    if (_cart.isEmpty) {
      return;
    }

    _cart.clear();
    _refreshUi();
    unawaited(_persistActivePending());
  }

  double get _subtotal {
    return _cart.fold<double>(
      0,
          (sum, line) =>
      sum + line.amount,
    );
  }

  double get _tax {
    return double.tryParse(
      _taxController.text.trim(),
    ) ??
        0;
  }

  double get _discount {
    return double.tryParse(
      _discountController.text.trim(),
    ) ??
        0;
  }

  double get _total {
    final value =
        _subtotal +
            _tax -
            _discount;

    return value < 0
        ? 0
        : value;
  }

  // ============================================================
  // CHECKOUT
  // ============================================================

  Future<void> _checkout() async {
    if (_saving) return;

    if (_adminViewOnly) {
      _showError(
        'Admin accounts are view-only for sales.',
      );
      return;
    }

    if (_cart.isEmpty) {
      _showError(
        'Cart is empty.',
      );
      return;
    }

    final customerPhone = _customerPhoneController.text.trim();

    final tax = _tax;
    final discount =
        _discount;

    if (tax < 0) {
      _showError(
        'Tax cannot be negative.',
      );
      return;
    }

    if (discount < 0) {
      _showError(
        'Discount cannot be negative.',
      );
      return;
    }

    if (_subtotal +
        tax -
        discount <
        0) {
      _showError(
        'Discount cannot be greater than subtotal plus tax.',
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final soldLines = await _repo.normalizeCheckoutLines(_cart);
      final subtotal = soldLines.fold<double>(
        0,
        (sum, line) => sum + line.amount,
      );
      final grandTotal = subtotal + tax - discount;

      final customerName = _customerNameController.text.trim();

      final saleId =
      await _repo.recordSale(
        customerId: null,
        lines: soldLines,
        tax: tax,
        discount: discount,
        paymentType:
        _paymentType,
        customerName:
            customerName.isEmpty ? null : customerName,
        customerPhone:
            customerPhone.isEmpty ? null : customerPhone,
      );

      if (!mounted) return;

      final pendingId = _activePendingId;
      if (pendingId != null) {
        await _repo.deletePendingOrder(pendingId);
        _activePendingId = null;
        await _loadPendingOrders();
      }

      setState(() {
        _cart.clear();
        _saving = false;
      });

      _taxController.text =
      '0';

      _discountController.text =
      '0';

      _customerNameController.clear();
      _customerPhoneController.clear();

      await _refreshStock();

      if (!mounted) return;

      if (_cartSheetOpen && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReceiptScreen(
            saleId: saleId,
            lines: soldLines,
            paymentType: _paymentType,
            subtotal: subtotal,
            tax: tax,
            discount: discount,
            grandTotal: grandTotal,
            customerName:
                customerName.isEmpty ? null : customerName,
            customerPhone:
                customerPhone.isEmpty ? null : customerPhone,
          ),
        ),
      );
    } on InsufficientStockException catch (
    e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _showError(
        e.toString(),
      );

      await _refreshStock();
    } on InvalidInventoryException catch (
    e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _showError(
        e.toString(),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      _showError(
        'Unable to complete sale: $e',
      );
    }
  }

  // ============================================================
  // IMAGE
  // ============================================================

  Widget _image(
      String? path, {
        double height = 100,
      }) {
    if (path == null ||
        path.trim().isEmpty) {
      return Container(
        height: height,
        width:
        double.infinity,
        color: Theme.of(
          context,
        )
            .colorScheme
            .surfaceContainerHighest,
        child:
        const Icon(
          Icons
              .image_not_supported_outlined,
          size: 38,
        ),
      );
    }

    final file =
    File(path);

    if (!file.existsSync()) {
      return Container(
        height: height,
        width:
        double.infinity,
        color: Theme.of(
          context,
        )
            .colorScheme
            .surfaceContainerHighest,
        child:
        const Icon(
          Icons
              .broken_image_outlined,
          size: 38,
        ),
      );
    }

    return Image.file(
      file,
      height: height,
      width:
      double.infinity,
      fit: BoxFit.cover,
      errorBuilder:
          (
          _,
          __,
          ___,
          ) {
        return Container(
          height: height,
          width:
          double.infinity,
          color: Theme.of(
            context,
          )
              .colorScheme
              .surfaceContainerHighest,
          child:
          const Icon(
            Icons
                .broken_image_outlined,
            size: 38,
          ),
        );
      },
    );
  }

  // ============================================================
  // MATERIAL CARD
  // ============================================================

  Widget _materialCard(
      RawMaterial material,
      ) {
    final stock =
    _stockForMaterial(
      material,
    );

    final cartQty =
    material.id == null
        ? 0.0
        : _cartQtyForRaw(
      material.id!,
    );

    final unit =
    _unitForMaterial(
      material,
    );

    return Card(
      clipBehavior:
      Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _addRawMaterial(material),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment
              .start,
          children: [
            _image(
              material.imagePath,
              height: 100,
            ),

            Expanded(
              child: Padding(
                padding:
                const EdgeInsets.all(
                  10,
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Text(
                      material.salesLabel,
                      maxLines: 2,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      style:
                      const TextStyle(
                        fontWeight:
                        FontWeight
                            .bold,
                        fontSize: 14,
                      ),
                    ),

                    const SizedBox(
                      height: 5,
                    ),

                    Text(
                      material.sellingPrice == null
                          ? 'No price'
                          : '₹${material.sellingPrice!.toStringAsFixed(2)}',
                      style:
                      TextStyle(
                        fontWeight:
                        FontWeight
                            .w600,
                        fontSize: 14,
                        color: material.sellingPrice == null
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                    ),
                    Text(
                      _formatStockLabel(stock),
                      style: TextStyle(
                        fontSize: 11,
                        color: stock < 0
                            ? Colors.red.shade700
                            : Colors.grey.shade700,
                      ),
                    ),

                    const Spacer(),

                    Row(
                      children: [
                        const Spacer(),

                        if (cartQty >
                            0)
                          CircleAvatar(
                            radius:
                            11,
                            child:
                            Text(
                              _formatQty(
                                cartQty,
                              ),
                              style:
                              const TextStyle(
                                fontSize:
                                10,
                              ),
                            ),
                          ),
                      ],
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

  static const double _variantCardHeight = 330;

  Widget _variantGroupCard(VariantGroup group) {
    final selected = _selectedVariant(group);
    final stock = VariantHelpers.sellableUnits(selected, _materialsById);
    final cartQty = _cartQtyForRawMaterial(selected);
    final imagePath = selected.imagePath ?? group.stockSource.imagePath;
    final useColumnSelector = group.variants.length >= 2;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _addRawMaterial(selected),
            child: _image(imagePath, height: 72),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.posTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: _variantSelector(
                        group,
                        selected,
                        useColumn: useColumnSelector,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => _addRawMaterial(selected),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selected.sellingPrice == null
                                ? 'No price'
                                : '₹${selected.sellingPrice!.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: selected.sellingPrice == null
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                          ),
                          Text(
                            _formatStockLabel(stock),
                            style: TextStyle(
                              fontSize: 11,
                              color: stock < 0
                                  ? Colors.red.shade700
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (cartQty > 0)
                    Align(
                      alignment: Alignment.centerRight,
                      child: CircleAvatar(
                        radius: 11,
                        child: Text(
                          _formatQty(cartQty),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _variantSelector(
    VariantGroup group,
    RawMaterial selected, {
    required bool useColumn,
  }) {
    return Material(
      color: Colors.transparent,
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: useColumn
            ? _variantSelectorColumn(group, selected)
            : _variantSelectorRow(group, selected),
      ),
    );
  }

  Widget _variantSelectorRow(VariantGroup group, RawMaterial selected) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: WrapAlignment.start,
      children: group.variants.map((variant) {
        final id = variant.id;
        if (id == null) return const SizedBox.shrink();
        final label = VariantHelpers.variantSelectorLabel(variant);
        final isSelected = selected.id == id;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ActionChip(
              label: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              backgroundColor: isSelected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              side: isSelected
                  ? BorderSide(color: Theme.of(context).colorScheme.primary)
                  : null,
              avatar: isSelected
                  ? Icon(
                      Icons.check,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onPressed: () => _onVariantTapped(group, variant),
            ),
            _VariantQtyField(
              onQtyCommitted: (qty) {
                setState(() => _selectedVariantIdByGroup[group.key] = id);
                _addRawMaterial(variant, qty: qty, replaceQty: true);
              },
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _variantSelectorColumn(VariantGroup group, RawMaterial selected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: group.variants.map((variant) {
        final id = variant.id;
        if (id == null) return const SizedBox.shrink();
        final isSelected = selected.id == id;
        final label = VariantHelpers.variantSelectorLabel(variant);
        return InkWell(
          onTap: () => _onVariantTapped(group, variant),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 18,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                _VariantQtyField(
                  onQtyCommitted: (qty) {
                    setState(() => _selectedVariantIdByGroup[group.key] = id);
                    _addRawMaterial(variant, qty: qty);
                  },
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _comboCard(
      Combo combo,
      ) {
    final cartQty =
    combo.id == null
        ? 0.0
        : _cartQtyForCombo(
      combo.id!,
    );

    return Card(
      clipBehavior:
      Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _addCombo(combo),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment
              .start,
          children: [
            _image(
              combo.imagePath,
              height: 100,
            ),
            Expanded(
              child: Padding(
                padding:
                const EdgeInsets.all(
                  10,
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Text(
                      combo.name,
                      maxLines: 2,
                      overflow:
                      TextOverflow
                          .ellipsis,
                      style:
                      const TextStyle(
                        fontWeight:
                        FontWeight
                            .bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Combo',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${combo.price.toStringAsFixed(2)}',
                      style:
                      const TextStyle(
                        fontWeight:
                        FontWeight
                            .w600,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        const Spacer(),
                        if (cartQty >
                            0)
                          CircleAvatar(
                            radius:
                            11,
                            child:
                            Text(
                              _formatQty(
                                cartQty,
                              ),
                              style:
                              const TextStyle(
                                fontSize:
                                10,
                              ),
                            ),
                          ),
                      ],
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

  // ============================================================
  // CART VIEW
  // ============================================================

  Widget _cartView() {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final checkoutMax = (constraints.maxHeight * 0.52).clamp(220.0, 420.0);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_cart_outlined, size: 21),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _activePendingId == null
                            ? 'Current Sale'
                            : 'Token ${_pendingTokenLabel()} · Current Sale',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                    if (_cart.isNotEmpty)
                      TextButton(
                        onPressed: _clearCart,
                        child: const Text('Clear'),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _cart.isEmpty
                    ? const SingleChildScrollView(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.remove_shopping_cart_outlined, size: 42),
                            SizedBox(height: 8),
                            Text(
                              'Cart is empty',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            SizedBox(height: 3),
                            Text('Tap an item to add it'),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _cartScrollController,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _cart.length,
                        itemBuilder: (context, index) {
                          return _cartLine(index, _cart[index]);
                        },
                      ),
              ),
              const Divider(height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: checkoutMax),
                child: _checkoutPanel(),
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // CART LINE
  // ============================================================

  Widget _cartLine(
      int index,
      CartLine line,
      ) {
    return Padding(
      padding:
      const EdgeInsets
          .symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 17,
            child:
            Icon(
              line.isCombo
                  ? Icons.local_offer_outlined
                  : Icons.inventory_2_outlined,
              size: 17,
            ),
          ),

          const SizedBox(
            width: 8,
          ),

          Expanded(
            child: Column(
              mainAxisSize:
              MainAxisSize
                  .min,
              crossAxisAlignment:
              CrossAxisAlignment
                  .start,
              children: [
                Text(
                  line.displayLabel,
                  maxLines: 2,
                  overflow:
                  TextOverflow
                      .ellipsis,
                  style:
                  const TextStyle(
                    fontWeight:
                    FontWeight
                        .w600,
                    fontSize: 13,
                  ),
                ),
                if (line.isCombo && line.componentLabels.isNotEmpty)
                  Text(
                    line.componentLabels.join(' • '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                    ),
                  ),
                Text(
                  '₹${line.price.toStringAsFixed(2)} × '
                      '${_formatQty(line.qty)}',
                  style:
                  const TextStyle(
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          IconButton(
            visualDensity:
            VisualDensity
                .compact,
            tooltip:
            'Decrease',
            icon:
            const Icon(
              Icons
                  .remove_circle_outline,
              size: 20,
            ),
            onPressed:
                () {
              _changeQuantity(
                index,
                line.qty - 1,
              );
            },
          ),

          _CartQtyField(
            qty: line.qty,
            formatQty: _formatQty,
            onQtyCommitted: (newQty) {
              _changeQuantity(index, newQty);
            },
          ),

          IconButton(
            visualDensity:
            VisualDensity
                .compact,
            tooltip:
            'Increase',
            icon:
            const Icon(
              Icons
                  .add_circle_outline,
              size: 20,
            ),
            onPressed: () {
              _changeQuantity(index, line.qty + 1);
            },
          ),

          SizedBox(
            width: 70,
            child:
            Text(
              '₹${line.amount.toStringAsFixed(2)}',
              textAlign:
              TextAlign
                  .right,
              style:
              const TextStyle(
                fontWeight:
                FontWeight
                    .bold,
                fontSize: 13,
              ),
            ),
          ),

          IconButton(
            visualDensity:
            VisualDensity
                .compact,
            tooltip:
            'Remove',
            icon:
            const Icon(
              Icons
                  .delete_outline,
              color:
              Colors.red,
              size: 20,
            ),
            onPressed:
                () =>
                _removeLine(
                  index,
                ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // CHECKOUT PANEL
  // ============================================================

  Widget _checkoutPanel() {
    return SingleChildScrollView(
      padding:
      const EdgeInsets.fromLTRB(
        10,
        8,
        10,
        8,
      ),
      child: Column(
        mainAxisSize:
        MainAxisSize.min,
        crossAxisAlignment:
        CrossAxisAlignment
            .stretch,
        children: [
          if (_adminViewOnly) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border.all(color: Colors.orange.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Admin accounts are view-only for sales. Switch to a location '
                'staff account to complete a sale.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
          TextField(
            controller: _customerNameController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Customer name (optional)',
              border: OutlineInputBorder(),
              isDense: true,
              prefixIcon: Icon(Icons.person_outline),
            ),
            onChanged: (_) => _refreshUi(),
          ),

          const SizedBox(height: 8),

          TextField(
            controller: _customerPhoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Mobile number (optional)',
              border: OutlineInputBorder(),
              isDense: true,
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            onChanged: (_) => _refreshUi(),
          ),

          const SizedBox(height: 8),

          // ------------------------------------------------------
          // PAYMENT
          // ------------------------------------------------------

          DropdownButtonFormField<
              String>(
            value:
            _paymentType,
            isDense:
            true,
            decoration:
            const InputDecoration(
              labelText:
              'Payment Type',
              border:
              OutlineInputBorder(),
              prefixIcon:
              Icon(
                Icons
                    .payments_outlined,
              ),
            ),
            items: const [
              DropdownMenuItem(
                value:
                'Cash',
                child:
                Text(
                  'Cash',
                ),
              ),
              DropdownMenuItem(
                value:
                'UPI',
                child:
                Text(
                  'UPI',
                ),
              ),
              DropdownMenuItem(
                value:
                'Card',
                child:
                Text(
                  'Card',
                ),
              ),
            ],
            onChanged:
                (value) {
              if (value ==
                  null) {
                return;
              }

              _paymentType = value;
              _refreshUi();
            },
          ),

          const SizedBox(
            height: 8,
          ),

          // ------------------------------------------------------
          // TAX / DISCOUNT
          // ------------------------------------------------------

          Row(
            children: [
              Expanded(
                child:
                TextField(
                  controller:
                  _taxController,
                  keyboardType:
                  const TextInputType
                      .numberWithOptions(
                    decimal:
                    true,
                  ),
                  decoration:
                  const InputDecoration(
                    labelText:
                    'Tax',
                    prefixText:
                    '₹ ',
                    border:
                    OutlineInputBorder(),
                    isDense:
                    true,
                  ),
                  onChanged:
                      (_) {
                    setState(
                          () {},
                    );
                  },
                ),
              ),

              const SizedBox(
                width: 8,
              ),

              Expanded(
                child:
                TextField(
                  controller:
                  _discountController,
                  keyboardType:
                  const TextInputType
                      .numberWithOptions(
                    decimal:
                    true,
                  ),
                  decoration:
                  const InputDecoration(
                    labelText:
                    'Discount',
                    prefixText:
                    '₹ ',
                    border:
                    OutlineInputBorder(),
                    isDense:
                    true,
                  ),
                  onChanged:
                      (_) {
                    setState(
                          () {},
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 8,
          ),

          // ------------------------------------------------------
          // TOTALS
          // ------------------------------------------------------

          _summaryRow(
            'Subtotal',
            _subtotal,
          ),

          const SizedBox(
            height: 2,
          ),

          _summaryRow(
            'Tax',
            _tax,
          ),

          const SizedBox(
            height: 2,
          ),

          _summaryRow(
            'Discount',
            -_discount,
          ),

          const Divider(
            height: 14,
          ),

          _summaryRow(
            'TOTAL',
            _total,
            large:
            true,
          ),

          const SizedBox(
            height: 6,
          ),

          // ------------------------------------------------------
          // COMPLETE SALE
          // ------------------------------------------------------

          SizedBox(
            height: 46,
            child:
            FilledButton
                .icon(
              onPressed:
              _saving ||
                  _cart.isEmpty ||
                  _adminViewOnly
                  ? null
                  : _checkout,
              icon: _saving
                  ? const SizedBox(
                height:
                18,
                width:
                18,
                child:
                CircularProgressIndicator(
                  strokeWidth:
                  2,
                ),
              )
                  : const Icon(
                Icons
                    .check_circle_outline,
              ),
              label:
              Text(
                _adminViewOnly
                    ? 'View Only'
                    : _saving
                        ? 'Processing...'
                        : 'Complete Sale',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SUMMARY ROW
  // ============================================================

  Widget _summaryRow(
      String label,
      double value, {
        bool large =
        false,
      }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style:
            TextStyle(
              fontSize:
              large
                  ? 17
                  : 13,
              fontWeight:
              large
                  ? FontWeight
                  .bold
                  : FontWeight
                  .normal,
            ),
          ),
        ),
        Text(
          '${value < 0 ? '-' : ''}'
              '₹${value.abs().toStringAsFixed(2)}',
          style:
          TextStyle(
            fontSize:
            large
                ? 19
                : 13,
            fontWeight:
            large
                ? FontWeight
                .bold
                : FontWeight
                .w600,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================

  @override
  Widget build(
      BuildContext context,
      ) {
    final phone = MediaQuery.sizeOf(context).width < 900;

    return Scaffold(
      body: _loading
          ? const Center(
        child:
        CircularProgressIndicator(),
      )
          : Column(
        children: [
          _topBar(),

          Expanded(
            child:
            _buildResponsiveBody(),
          ),
        ],
      ),
      floatingActionButton: _loading || !phone
          ? null
          : _mobileCartButton(),
    );
  }

  Widget _mobileCartButton() {
    final count = _cart.fold<double>(0, (sum, line) => sum + line.qty);
    final label = count == count.roundToDouble()
        ? '${count.round()}'
        : count.toStringAsFixed(1);
    return FloatingActionButton.extended(
      onPressed: _openMobileCart,
      icon: Badge(
        isLabelVisible: _cart.isNotEmpty,
        label: Text(label),
        child: const Icon(Icons.shopping_cart),
      ),
      label: Text(
        _cart.isEmpty ? 'View bill' : '₹${_total.toStringAsFixed(2)}',
      ),
    );
  }

  Future<void> _openMobileCart() async {
    _cartSheetOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            _sheetSetState = setModal;
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(ctx).height * 0.78,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: _cartView(),
                ),
              ),
            );
          },
        );
      },
    );
    _sheetSetState = null;
    if (mounted) {
      setState(() {
        _cartSheetOpen = false;
      });
    }
  }

  String _pendingTokenLabel() {
    for (final row in _pendingOrders) {
      if (row['id'] == _activePendingId) {
        return '${row['token_number']}';
      }
    }
    return '?';
  }

  // ============================================================
  // TOP BAR
  // ============================================================

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        children: [
          if (_repo.isAdmin && _locations.isNotEmpty) ...[
            DropdownButtonFormField<int>(
              value: _adminLocationId,
              decoration: const InputDecoration(
                labelText: 'Active location',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
              items: _locations.map((location) {
                final id = location['id'] as int;
                final name = location['name']?.toString() ?? 'Location';
                return DropdownMenuItem<int>(
                  value: id,
                  child: Text(name),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _adminLocationId = value;
                });
                _repo.setAdminSaleLocation(value);
              },
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search items',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.clear),
                    ),
              border: const OutlineInputBorder(),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _barcodeController,
                  onSubmitted: _handleBarcode,
                  decoration: const InputDecoration(
                    hintText: 'Barcode',
                    prefixIcon: Icon(Icons.qr_code_scanner),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh prices and stock',
                onPressed: _loading ? null : _loadData,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (!_adminViewOnly) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _showPendingTokensSheet,
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: Text(
                      _activePendingId == null
                          ? 'Tokens (${_pendingOrders.length})'
                          : 'Token ${_pendingTokenLabel()}',
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_activePendingId != null)
                    OutlinedButton.icon(
                      onPressed: _createNewToken,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New Token'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // RESPONSIVE BODY
  // ============================================================

  Widget _buildResponsiveBody() {
    final width =
        MediaQuery.of(
          context,
        ).size.width;

    if (width < 900) {
      return _mobileBody();
    }

    final cartWidth = width < 1100 ? 320.0 : (width < 1300 ? 360.0 : 400.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRect(
            child: _productArea(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: cartWidth,
          child: Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 8),
            child: _cartView(),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // MOBILE BODY
  // ============================================================

  Widget _mobileBody() {
    return _productArea();
  }

  // ============================================================
  // PRODUCT AREA
  // ============================================================

  Widget _productArea() {
    return Column(
      children: [
        // --------------------------------------------------------
        // ITEMS HEADER
        //
        // No TabBar here because there is currently only one tab.
        // This completely removes the TabController error.
        // --------------------------------------------------------

        Container(
          height: 48,
          margin:
          const EdgeInsets
              .symmetric(
            horizontal: 8,
          ),
          padding:
          const EdgeInsets
              .symmetric(
            horizontal: 14,
          ),
          decoration:
          BoxDecoration(
            border:
            Border(
              bottom:
              BorderSide(
                color: Theme.of(
                  context,
                ).dividerColor,
              ),
            ),
          ),
          child:
          Row(
            children: [
              Icon(
                Icons
                    .inventory_2_outlined,
                size: 20,
                color: Theme.of(
                  context,
                )
                    .colorScheme
                    .primary,
              ),

              const SizedBox(
                width: 8,
              ),

              Text(
                'Menu items',
                style: Theme.of(
                  context,
                )
                    .textTheme
                    .titleSmall
                    ?.copyWith(
                  fontWeight:
                  FontWeight
                      .bold,
                ),
              ),
            ],
          ),
        ),

        _categoryChips(),

        Expanded(
          child:
          _materialsGrid(),
        ),
      ],
    );
  }

  // ============================================================
  // MATERIAL GRID
  // ============================================================

  String _categoryLabel(String name) {
    return ItemImportService.canonicalMenuCategory(name) ?? name;
  }

  bool _hasOthersCategory() {
    return _categoriesWithItems.any((category) {
      final key = category.name.trim().toLowerCase();
      return key == 'others' || key == 'other';
    });
  }

  Widget _categoryChips() {
    final hasOther =
        _categoryIdsWithItems.contains(null) && !_hasOthersCategory();
    if (_categoriesWithItems.isEmpty && !hasOther) {
      return const SizedBox.shrink();
    }

    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          chip(
            label: 'All',
            selected: _categoryId == null,
            onTap: () => setState(() => _categoryId = null),
          ),
          for (final category in _categoriesWithItems)
            chip(
              label: _categoryLabel(category.name),
              selected: _categoryId == category.id,
              onTap: () => setState(() => _categoryId = category.id),
            ),
          if (hasOther)
            chip(
              label: 'Others',
              selected: _categoryId == _uncategorizedFilter,
              onTap: () => setState(() => _categoryId = _uncategorizedFilter),
            ),
        ],
      ),
    );
  }

  Widget _materialsGrid() {
    final sections = _productSections;

    if (sections.isEmpty) {
      return _emptyProducts(
        icon:
        Icons
            .inventory_2_outlined,
        title:
        _search.isNotEmpty
            ? 'No items match this search'
            : _categoryId == null
                ? 'No menu items found'
                : 'No items in this category',
      );
    }

    return CustomScrollView(
      slivers: [
        for (final section in sections) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Text(
                section.title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
            sliver: SliverGrid(
              gridDelegate:
                  SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisExtent: _variantCardHeight,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final entryCount = section.entries.length;
                  if (index < entryCount) {
                    final entry = section.entries[index];
                    if (entry.variantGroup != null) {
                      return _variantGroupCard(entry.variantGroup!);
                    }
                    if (entry.material != null) {
                      return _materialCard(entry.material!);
                    }
                    return const SizedBox.shrink();
                  }
                  return _comboCard(
                    section.combos[index - entryCount],
                  );
                },
                childCount: section.entries.length + section.combos.length,
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(
          child: SizedBox(height: 88),
        ),
      ],
    );
  }

  // ============================================================
  // EMPTY PRODUCTS
  // ============================================================

  Widget _emptyProducts({
    required IconData icon,
    required String title,
  }) {
    return Center(
      child:
      Column(
        mainAxisSize:
        MainAxisSize
            .min,
        children: [
          Icon(
            icon,
            size: 55,
            color:
            Colors.grey,
          ),

          const SizedBox(
            height: 10,
          ),

          Text(
            title,
            style:
            const TextStyle(
              fontSize: 17,
              fontWeight:
              FontWeight
                  .bold,
            ),
          ),

          if (_search
              .isNotEmpty) ...[
            const SizedBox(
              height: 5,
            ),
            const Text(
              'Try another search.',
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // UNIT
  // ============================================================

  String _unitForMaterial(
      RawMaterial material,
      ) {
    // Your current RawMaterial model contains unitId,
    // but POS does not currently have the Unit short code.
    //
    // Therefore the UI displays "units" for now.

    return 'units';
  }

  // ============================================================
  // FORMAT QUANTITY
  // ============================================================

  String _formatStockLabel(double value) {
    if (value.abs() < 0.000001) {
      return 'Stock 0';
    }
    return 'Stock ${_formatQty(value)}';
  }

  String _formatQty(
      double value,
      ) {
    if ((value -
        value.roundToDouble())
        .abs() <
        0.000001) {
      return value
          .round()
          .toString();
    }

    return value
        .toStringAsFixed(2)
        .replaceFirst(
      RegExp(
        r'\.?0+$',
      ),
      '',
    );
  }

  // ============================================================
  // ERROR
  // ============================================================

  void _showError(
      String message,
      ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content:
        Text(message),
        backgroundColor:
        Theme.of(
          context,
        )
            .colorScheme
            .error,
        behavior:
        SnackBarBehavior
            .floating,
      ),
    );
  }
}

class _PosGridEntry {
  const _PosGridEntry._({this.material, this.variantGroup});

  factory _PosGridEntry.material(RawMaterial material) {
    return _PosGridEntry._(material: material);
  }

  factory _PosGridEntry.variant(VariantGroup group) {
    return _PosGridEntry._(variantGroup: group);
  }

  final RawMaterial? material;
  final VariantGroup? variantGroup;
}

class _VariantQtyField extends StatefulWidget {
  const _VariantQtyField({required this.onQtyCommitted});

  final ValueChanged<double> onQtyCommitted;

  @override
  State<_VariantQtyField> createState() => _VariantQtyFieldState();
}

class _VariantQtyFieldState extends State<_VariantQtyField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final raw = _controller.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return;
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      _controller.clear();
      return;
    }
    widget.onQtyCommitted(parsed);
    _controller.clear();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11),
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'Qty',
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _commit(),
        onEditingComplete: _commit,
      ),
    );
  }
}

class _CartQtyField extends StatefulWidget {
  final double qty;
  final String Function(double value) formatQty;
  final ValueChanged<double> onQtyCommitted;

  const _CartQtyField({
    required this.qty,
    required this.formatQty,
    required this.onQtyCommitted,
  });

  @override
  State<_CartQtyField> createState() => _CartQtyFieldState();
}

class _CartQtyFieldState extends State<_CartQtyField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.formatQty(widget.qty));
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(_CartQtyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && oldWidget.qty != widget.qty) {
      _controller.text = widget.formatQty(widget.qty);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    final raw = _controller.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) {
      _controller.text = widget.formatQty(widget.qty);
      return;
    }

    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      _controller.text = widget.formatQty(widget.qty);
      return;
    }

    _controller.text = widget.formatQty(parsed);
    if ((parsed - widget.qty).abs() > 0.000001) {
      widget.onQtyCommitted(parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}