import 'dart:convert';
import 'dart:typed_data';

import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/menu_item_edit_helpers.dart';
import 'package:foodstock/services/repository.dart';
import 'package:foodstock/services/spreadsheet_export.dart';


class ItemImportService {
  static const menuCategoryAliases = {
    'burger': 'Burgers',
    'burgers': 'Burgers',
    'bun': 'Burgers',
    'buns': 'Burgers',
    'snacks': 'Snacks',
    'sauces': 'Sauces',
    'frieditems': 'Fried Items',
    'fried items': 'Fried Items',
    'fried item': 'Fried Items',
    'rolls': 'Rolls',
    'roll': 'Rolls',
    'others': 'Uncategorized',
    'other': 'Uncategorized',
    'beverages': 'Beverages',
    'bevarges': 'Beverages',
    'beverage': 'Beverages',
    'drinks': 'Beverages',
    'sauce dry stock': 'Sauces',
    'saucedrystock': 'Sauces',
  };

  /// Tags in the barcode/grouping column that are not real barcodes.
  static const groupingTags = {
    'combo',
    'fried item',
    'fried items',
    'snacks',
    'sauce/dry stock',
    'sauce dry stock',
    'sauces',
    'bevarges',
    'beverages',
    'burgers',
    'burger',
    'rolls',
    'roll',
    'stock',
  };

  static const hiddenGroupingTags = <String>{};

  static const hiddenByDefaultNames = {
    'paratha',
    'bun',
    'burger bun with sesame',
  };

  static bool isGroupingTag(String? value) {
    final key = value?.trim().toLowerCase() ?? '';
    if (key.isEmpty) return false;
    final collapsed = key.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    final normalized = collapsed.replaceAll(RegExp(r'\s+'), ' ').trim();
    return groupingTags.contains(normalized) ||
        groupingTags.contains(normalized.replaceAll(' ', ''));
  }

  /// PDF menu uses category-style labels in the barcode column (BEVARGES, COMBO, etc.).
  static String canonicalGroupingBarcode(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    switch (normalized) {
      case 'bevarges':
      case 'beverages':
        return 'BEVARGES';
      case 'combo':
        return 'COMBO';
      case 'fried item':
      case 'fried items':
        return 'FRIED ITEM';
      case 'snacks':
        return 'SNACKS';
      case 'sauce dry stock':
      case 'sauces':
        return 'SAUCE/DRY STOCK';
      case 'stock':
        return 'STOCK';
      default:
        return value.trim();
    }
  }

  static bool shouldHideFromSales({
    String? groupingTag,
    required String name,
    String? subItem,
    String? category,
  }) {
    final tag = groupingTag?.trim().toLowerCase() ?? '';
    if (hiddenGroupingTags.contains(tag)) return true;

    final labels = [
      name.trim().toLowerCase(),
      (subItem ?? '').trim().toLowerCase(),
    ];
    for (final label in labels) {
      if (label.isEmpty) continue;
      if (hiddenByDefaultNames.contains(label)) return true;
    }

    return false;
  }

  static String? canonicalMenuCategory(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final key = trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    final collapsed = key.replaceAll(RegExp(r'\s+'), ' ').trim();
    final aliasKey = collapsed.replaceAll(' ', '');
    return menuCategoryAliases[collapsed] ??
        menuCategoryAliases[aliasKey] ??
        trimmed;
  }

  /// Single label for Menu Items / grid grouping (Others → Uncategorized).
  static String displayCategoryName(String? name) {
    final canonical = canonicalMenuCategory(name) ?? name?.trim() ?? '';
    if (canonical.isEmpty) return 'Uncategorized';
    final lower = canonical.toLowerCase();
    if (lower == 'others' || lower == 'other' || lower == 'uncategorized') {
      return 'Uncategorized';
    }
    return canonical;
  }

  static bool isUncategorizedCategoryName(String? name) {
    final lower = displayCategoryName(name).toLowerCase();
    return lower == 'uncategorized';
  }

  static String? normalizeBarcode(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final numeric = double.tryParse(trimmed.replaceAll(',', ''));
    if (numeric != null && numeric.isFinite && numeric == numeric.roundToDouble()) {
      return numeric.toInt().toString();
    }
    return trimmed;
  }

  static const menuHeaders = [
    'category',
    'item_name',
    'sub_item',
    'barcode',
    'qty_per_sale',
    'packets',
    'opening_pieces',
    'units_per_packet',
    'unit',
    'opening stock',
    'cost_price',
    'selling_price',
    'variant_group',
    'variant_label',
    'stock_source_name',
  ];

  /// Matches the Menu Items Grid screen column-for-column (plus category).
  static const gridExportHeaders = [
    'category',
    'barcode',
    'item_name',
    'sub_item',
    'variant_group',
    'variant_label',
    'stock_source_name',
    'units_per_packet',
    'packets',
    'opening_pieces',
    'total_stock',
    'qty_per_sale',
    'cost_price',
    'selling_price',
  ];

  static const comboExportHeaders = [
    'combo',
    'item_name',
    'item_qty',
    'unit',
    'item_unit_price',
    'item_amount',
  ];

  Future<Uint8List> exportXlsxForLocation(int locationId) async {
    return exportGridWorkbookForLocation(locationId);
  }

  /// Full shop backup: menu grid on one sheet, combos on another.
  Future<Uint8List> exportBackupWorkbookForLocation(int locationId) async {
    final menuRows = await _gridRowsForLocation(locationId);
    final comboRows = await _comboRowsForExport();
    return SpreadsheetExport.buildMultiSheetXlsx({
      'Menu Items': (headers: gridExportHeaders, rows: menuRows),
      'Combos': (headers: comboExportHeaders, rows: comboRows),
    });
  }

  /// Grid-aligned menu export (menu items only — combos have their own export).
  Future<Uint8List> exportGridWorkbookForLocation(int locationId) async {
    final menuRows = await _gridRowsForLocation(locationId);
    return SpreadsheetExport.buildXlsx(gridExportHeaders, menuRows);
  }

  /// Dedicated combos export for the Combos screen.
  Future<Uint8List> exportCombosXlsx() async {
    final comboRows = await _comboRowsForExport();
    return SpreadsheetExport.buildXlsx(comboExportHeaders, comboRows);
  }

  Future<List<List<String>>> gridExportRowsForLocation(int locationId) {
    return _gridRowsForLocation(locationId);
  }

  Future<List<List<String>>> comboExportRows() {
    return _comboRowsForExport();
  }

  Future<List<List<String>>> _gridRowsForLocation(int locationId) async {
    final materials = await Repository.instance.rawMaterialsForDisplay(
      includeHidden: true,
    );
    final categories = await Repository.instance.categories(type: 'raw_material');
    final categoryNameById = {
      for (final category in categories)
        if (category.id != null) category.id!: category.name,
    };
    final nameById = {
      for (final material in materials)
        if (material.id != null) material.id!: material.name,
    };

    String cell(num? value) {
      if (value == null) return '';
      final number = value.toDouble();
      if (number % 1 == 0) return number.toStringAsFixed(0);
      return number.toString();
    }

    String cellDouble(double? value) {
      if (value == null) return '';
      return MenuItemEditHelpers.formatNumber(value);
    }

    final rows = <List<String>>[];
    for (final item in materials) {
      final categoryName = displayCategoryName(categoryNameById[item.categoryId]);
      final stockSourceName = item.stockSourceId == null
          ? ''
          : (nameById[item.stockSourceId] ?? '');
      final packets = MenuItemEditHelpers.packetsTextFromStock(
            item.currentStock,
            item.unitsPerPacket,
            openingPieces: item.openingPieces,
          ) ??
          '';

      rows.add([
        categoryName,
        item.barcode ?? '',
        item.name,
        item.subItem ?? item.name,
        item.variantGroup ?? '',
        item.variantLabel ?? '',
        stockSourceName,
        item.unitsPerPacket == null
            ? ''
            : MenuItemEditHelpers.formatNumber(item.unitsPerPacket!),
        packets,
        item.openingPieces == 0
            ? ''
            : MenuItemEditHelpers.formatNumber(item.openingPieces),
        MenuItemEditHelpers.formatNumber(item.currentStock),
        MenuItemEditHelpers.formatNumber(item.qtyNeeded),
        cellDouble(item.costPrice),
        cellDouble(item.sellingPrice),
      ]);
    }
    return rows;
  }

  Future<List<List<String>>> _comboRowsForExport() async {
    final combos = await Repository.instance.combosWithItems();
    final categories = await Repository.instance.categories(type: 'raw_material');
    final materials = await Repository.instance.rawMaterials(includeHidden: true);
    final categoryNameById = {
      for (final category in categories)
        if (category.id != null) category.id!: category.name,
    };
    final materialById = {
      for (final material in materials)
        if (material.id != null) material.id!: material,
    };
    final unitPriceById = {
      for (final material in materials)
        if (material.id != null) material.id!: material.sellingPrice ?? 0.0,
    };

    String cell(num? value) {
      if (value == null) return '';
      final number = value.toDouble();
      if (number % 1 == 0) return number.toStringAsFixed(0);
      return number.toString();
    }

    String comboHeaderLine(Combo combo, String categoryName) {
      final price = cell(combo.price);
      if (categoryName.isEmpty) {
        return '${combo.name} — ₹$price';
      }
      return '${combo.name} — ₹$price ($categoryName)';
    }

    String comboItemExportName(ComboItem item) {
      final material = materialById[item.rawMaterialId];
      final fromMaterial = material?.staffLabel.trim() ?? '';
      if (fromMaterial.isNotEmpty) return fromMaterial;
      return item.itemNameLabel.trim();
    }

    final rows = <List<String>>[];
    for (var comboIndex = 0; comboIndex < combos.length; comboIndex++) {
      final combo = combos[comboIndex];
      final categoryName = displayCategoryName(categoryNameById[combo.categoryId]);

      rows.add([
        comboHeaderLine(combo, categoryName),
        '',
        '',
        '',
        '',
        '',
      ]);

      for (final item in combo.items) {
        final unitPrice = unitPriceById[item.rawMaterialId] ?? 0.0;
        final amount = unitPrice * item.qty;
        rows.add([
          '',
          comboItemExportName(item),
          cell(item.qty),
          item.unit ?? '',
          cell(unitPrice),
          cell(amount),
        ]);
      }

      if (comboIndex < combos.length - 1) {
        rows.add(['', '', '', '', '', '']);
      }
    }
    return rows;
  }

  Future<String> exportCsvForLocation(int locationId) async {
    final rows = await _menuRowsForLocation(locationId);
    return SpreadsheetExport.buildCsv(menuHeaders, rows);
  }

  Future<List<List<String>>> _menuRowsForLocation(int locationId) async {
    final data = await Repository.instance.menuExportRows(locationId);
    return data.map((row) {
      final snapshot = row['menu_export_row']?.toString();
      if (snapshot != null && snapshot.isNotEmpty) {
        final decoded = jsonDecode(snapshot) as List<dynamic>;
        return decoded.map((cell) => cell.toString()).toList();
      }

      String cell(Object? value) {
        if (value == null) return '';
        if (value is num) {
          final number = value.toDouble();
          if (number % 1 == 0) return number.toStringAsFixed(0);
          return number.toString();
        }
        return value.toString();
      }

      return [
        cell(row['category']),
        cell(row['item_name']),
        cell(row['sub_item']),
        cell(row['barcode']),
        cell(row['qty_per_sale']),
        cell(row['packets']),
        cell(row['opening_pieces']),
        cell(row['units_per_packet']),
        cell(row['unit']),
        cell(row['opening_stock']),
        cell(row['cost_price']),
        cell(row['selling_price']),
      ];
    }).toList();
  }

  String itemKeyFor(
    String name,
    String? subItem, {
    String? category,
  }) {
    return '${(category ?? '').trim().toLowerCase()}|'
        '${name.trim().toLowerCase()}|'
        '${(subItem ?? '').trim().toLowerCase()}';
  }
}
