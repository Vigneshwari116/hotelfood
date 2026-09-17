import 'dart:convert';
import 'dart:typed_data';

import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/repository.dart';
import 'package:foodstock/services/spreadsheet_export.dart';

class ComboImportResult {
  int created = 0;
  int updated = 0;
  int skipped = 0;
  final List<String> errors = [];
}

class ComboImportService {
  static const comboHeaders = [
    'combo_name',
    'category',
    'combo_price',
    'item_name',
    'item_qty',
    'unit',
  ];

  final ItemImportService _spreadsheet = ItemImportService();

  Future<Uint8List> exportXlsx() async {
    final rows = await _exportRows();
    return SpreadsheetExport.buildXlsx(comboHeaders, rows);
  }

  Future<String> exportCsv() async {
    final rows = await _exportRows();
    return SpreadsheetExport.buildCsv(comboHeaders, rows);
  }

  Future<List<List<String>>> _exportRows() async {
    final combos = await Repository.instance.combosWithItems();
    final categories = await Repository.instance.categories(type: 'raw_material');
    final categoryNameById = {
      for (final category in categories)
        if (category.id != null) category.id!: category.name,
    };

    String cell(num? value) {
      if (value == null) return '';
      final number = value.toDouble();
      if (number % 1 == 0) return number.toStringAsFixed(0);
      return number.toString();
    }

    final rows = <List<String>>[];
    for (final combo in combos) {
      final categoryName = ItemImportService.displayCategoryName(
        categoryNameById[combo.categoryId],
      );
      if (combo.items.isEmpty) {
        rows.add([
          combo.name,
          categoryName,
          cell(combo.price),
          '',
          '',
          '',
        ]);
        continue;
      }

      for (final item in combo.items) {
        rows.add([
          combo.name,
          categoryName,
          cell(combo.price),
          item.itemNameLabel,
          cell(item.qty),
          item.unit ?? '',
        ]);
      }
    }
    return rows;
  }

  Future<ComboImportResult> importFileBytes(
    Uint8List bytes,
    String filename,
  ) async {
    final extension = filename.contains('.')
        ? filename.substring(filename.lastIndexOf('.'))
        : '.xlsx';
    final rows = _spreadsheet.parseSpreadsheetBytes(bytes, extension: extension);
    return _importRows(rows);
  }

  Future<ComboImportResult> _importRows(List<List<String>> rows) async {
    final result = ComboImportResult();
    if (rows.isEmpty) {
      result.errors.add('The file is empty.');
      return result;
    }

    final headerIndex = rows.indexWhere(
      (row) => row.any((cell) => cell.trim().isNotEmpty),
    );
    if (headerIndex < 0) {
      result.errors.add('No header row found.');
      return result;
    }

    final headers = rows[headerIndex]
        .map((cell) => _normalizeKey(cell))
        .toList();

    final materials = await Repository.instance.rawMaterials(includeHidden: true);
    final categories = await Repository.instance.categories(type: 'raw_material');
    final categoryIdByName = <String, int>{};
    for (final category in categories) {
      final id = category.id;
      final name = category.name;
      if (id == null) continue;
      categoryIdByName[name.trim().toLowerCase()] = id;
      final canonical =
          ItemImportService.canonicalMenuCategory(name)?.toLowerCase();
      if (canonical != null) {
        categoryIdByName.putIfAbsent(canonical, () => id);
      }
    }

    RawMaterial? findMaterial(String itemName) {
      final key = itemName.trim().toLowerCase();
      if (key.isEmpty) return null;

      for (final material in materials) {
        if (material.id == null) continue;
        if (material.name.trim().toLowerCase() == key) {
          return material;
        }
      }

      for (final material in materials) {
        if (material.id == null) continue;
        if (material.staffLabel.trim().toLowerCase() == key) {
          return material;
        }
      }

      for (final material in materials) {
        if (material.id == null) continue;
        String? categoryName;
        for (final category in categories) {
          if (category.id == material.categoryId) {
            categoryName = category.name;
            break;
          }
        }
        if (categoryName == null) continue;
        final labels = {
          '${categoryName.trim().toLowerCase()} — ${material.name.trim().toLowerCase()}',
          '${ItemImportService.displayCategoryName(categoryName).trim().toLowerCase()} — ${material.name.trim().toLowerCase()}',
        };
        if (labels.contains(key)) {
          return material;
        }
      }

      return null;
    }

    final existingCombos = await Repository.instance.combosWithItems();
    final comboByKey = <String, Combo>{};
    for (final combo in existingCombos) {
      String? categoryName;
      for (final category in categories) {
        if (category.id == combo.categoryId) {
          categoryName = category.name;
          break;
        }
      }
      final key = _comboKey(combo.name, categoryName);
      comboByKey[key] = combo;
    }

    final grouped = <String, _ComboImportGroup>{};
    for (var i = headerIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((cell) => cell.trim().isEmpty)) continue;

      final map = <String, String>{};
      for (var c = 0; c < headers.length && c < row.length; c++) {
        if (headers[c].isEmpty) continue;
        map[headers[c]] = row[c].trim();
      }

      final comboName = map['comboname'] ?? map['name'] ?? '';
      if (comboName.isEmpty) {
        result.errors.add('Row ${i + 1}: combo_name is required.');
        result.skipped++;
        continue;
      }

      final category = map['category'] ?? '';
      final comboPrice = _number(map['comboprice'] ?? map['price']) ?? 0;
      final itemName = map['itemname'] ?? '';
      final itemQty = _number(map['itemqty'] ?? map['qty']) ?? 1;
      if (itemQty <= 0) {
        result.errors.add('Row ${i + 1}: item_qty must be greater than zero.');
        result.skipped++;
        continue;
      }

      final key = _comboKey(comboName, category);
      final group = grouped.putIfAbsent(
        key,
        () => _ComboImportGroup(
          name: comboName,
          categoryName: category,
          price: comboPrice,
        ),
      );
      group.price = comboPrice;

      if (itemName.isNotEmpty) {
        final material = findMaterial(itemName);
        if (material?.id == null) {
          result.errors.add(
            'Row ${i + 1}: item "$itemName" was not found in menu items.',
          );
          result.skipped++;
          continue;
        }
        group.items.add(
          ComboRawMaterial(
            comboId: 0,
            rawMaterialId: material!.id!,
            qty: itemQty,
          ),
        );
      }
    }

    for (final group in grouped.values) {
      if (group.items.isEmpty) {
        result.errors.add('Combo "${group.name}" has no valid items.');
        result.skipped++;
        continue;
      }

      final categoryId = group.categoryName.trim().isEmpty
          ? null
          : categoryIdByName[group.categoryName.trim().toLowerCase()] ??
              categoryIdByName[
                (ItemImportService.canonicalMenuCategory(group.categoryName) ??
                        group.categoryName)
                    .trim()
                    .toLowerCase()
              ];

      final existing = comboByKey[_comboKey(group.name, group.categoryName)];
      final comboId = await Repository.instance.saveCombo(
        Combo(
          id: existing?.id,
          name: group.name,
          categoryId: categoryId ?? existing?.categoryId,
          price: group.price,
          imagePath: existing?.imagePath,
          isActive: existing?.isActive ?? true,
        ),
        group.items
            .map(
              (item) => ComboRawMaterial(
                comboId: existing?.id ?? 0,
                rawMaterialId: item.rawMaterialId,
                qty: item.qty,
              ),
            )
            .toList(),
      );

      if (existing == null) {
        result.created++;
        comboByKey[_comboKey(group.name, group.categoryName)] = Combo(
          id: comboId,
          name: group.name,
          categoryId: categoryId,
          price: group.price,
        );
      } else {
        result.updated++;
      }
    }

    return result;
  }

  String _comboKey(String name, String? category) {
    final categoryLabel =
        (category == null || category.trim().isEmpty)
            ? ''
            : ItemImportService.displayCategoryName(category).trim().toLowerCase();
    return '${categoryLabel}|${name.trim().toLowerCase()}';
  }

  String _normalizeKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  double? _number(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return double.tryParse(value.trim().replaceAll(',', ''));
  }
}

class _ComboImportGroup {
  _ComboImportGroup({
    required this.name,
    required this.categoryName,
    required this.price,
  });

  final String name;
  final String categoryName;
  double price;
  final List<ComboRawMaterial> items = [];
}
