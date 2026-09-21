import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:foodstock/database/category_cleanup.dart';
import 'package:foodstock/database/menu_import_idempotency.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/listed_change_source.dart';
import 'package:foodstock/services/menu_item_edit_helpers.dart';
import 'package:foodstock/services/repository.dart';
import 'package:foodstock/services/sub_item_stock.dart';
import 'package:foodstock/services/variant_helpers.dart';
import 'package:path/path.dart' as p;

class ItemImportResult {
  int created = 0;
  int updated = 0;
  int skipped = 0;
  final List<String> errors = [];
  final List<String> warnings = [];
}

class MenuItemImportService {
  void validateImportFilename(String filePath, String expectedLocationName) {
    final baseName = p.basenameWithoutExtension(filePath).trim().toLowerCase();
    final expected = expectedLocationName.trim().toLowerCase();
    if (baseName != expected) {
      throw InvalidInventoryException(
        'This file is for a different location. '
        'Expected "$expectedLocationName" but got "${p.basenameWithoutExtension(filePath)}".',
      );
    }
  }

  Future<ItemImportResult> importFileBytes(
    Uint8List bytes,
    String filename, {
    String? expectedLocationName,
    bool replaceCatalog = true,
  }) async {
    if (expectedLocationName != null) {
      validateImportFilename(filename, expectedLocationName);
      replaceCatalog = false;
    }

    final ext = p.extension(filename).toLowerCase();
    if (ext == '.xls') {
      throw InvalidInventoryException(
        'Old .xls files are not supported. Save as .xlsx or CSV and import again.',
      );
    }
    final rows = ext == '.xlsx'
        ? _parseXlsx(bytes)
        : _parseCsv(utf8.decode(bytes, allowMalformed: true));

    return _importRows(
      rows,
      updateExisting: true,
      replaceCatalog: replaceCatalog,
      preserveSourceCategories: expectedLocationName != null,
    );
  }

  Future<ItemImportResult> importFile(
    String path, {
    String? expectedLocationName,
    bool replaceCatalog = true,
  }) async {
    final bytes = await File(path).readAsBytes();
    return importFileBytes(
      bytes,
      p.basename(path),
      expectedLocationName: expectedLocationName,
      replaceCatalog: replaceCatalog,
    );
  }

  Future<ItemImportResult> importCsvText(
    String text, {
    bool updateExisting = false,
    bool replaceCatalog = false,
  }) {
    return _importRows(
      _parseCsv(text),
      updateExisting: updateExisting || replaceCatalog,
      replaceCatalog: replaceCatalog,
    );
  }

  Future<ItemImportResult> importXlsxBytes(
    Uint8List bytes, {
    bool updateExisting = true,
    bool replaceCatalog = false,
  }) {
    return _importRows(
      _parseXlsx(bytes),
      updateExisting: updateExisting,
      replaceCatalog: replaceCatalog,
    );
  }

  List<List<String>> parseSpreadsheetBytes(
    Uint8List bytes, {
    String extension = '.xlsx',
  }) {
    if (extension.toLowerCase() == '.xlsx') {
      return _parseXlsx(bytes);
    }
    return _parseCsv(utf8.decode(bytes, allowMalformed: true));
  }

  List<String> buildMenuExportRow(List<String> headers, List<String> row) {
    final byKey = <String, String>{};
    for (var c = 0; c < headers.length && c < row.length; c++) {
      final key = _normalizeKey(headers[c]);
      if (key.isEmpty) continue;
      byKey[key] = row[c];
    }
    return ItemImportService.menuHeaders.map((header) {
      final key = _normalizeKey(header);
      return byKey[key] ?? '';
    }).toList();
  }

  Future<ItemImportResult> _importRows(
    List<List<String>> rows, {
    required bool updateExisting,
    bool replaceCatalog = false,
    bool preserveSourceCategories = false,
  }) async {
    final result = ItemImportResult();
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

    final existing = await Repository.instance.rawMaterials(
      includeHidden: true,
    );

    var categories = await Repository.instance.categories(type: 'raw_material');
    var units = await Repository.instance.units();
    final categoryNameById = {
      for (final category in categories)
        if (category.id != null) category.id!: category.name,
    };
    final contentFingerprint = menuImportContentFingerprint(
      rows,
      Repository.instance.sessionLocationId,
    );
    final postProcessAlreadyDone =
        await Repository.instance.hasImportPostProcessCompleted(
      contentFingerprint,
    );

    final importedKeys = <String>{};
    final existingByKey = <String, RawMaterial>{
      for (final item in existing)
        _itemKey(
          item.name,
          item.subItem,
          category: item.categoryId == null
              ? ''
              : categoryNameById[item.categoryId],
        ): item,
    };

    for (var i = headerIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((cell) => cell.trim().isEmpty)) continue;

      final map = <String, String>{};
      for (var c = 0; c < headers.length && c < row.length; c++) {
        if (headers[c].isEmpty) continue;
        map[headers[c]] = row[c].trim();
      }

      final name = _first(map, const [
        'itemname',
        'name',
        'item',
        'menuitem',
      ]);
      if (name.isEmpty) {
        continue;
      }

      final subItem = _first(map, const [
        'subitem',
        'subitemname',
        'sub',
        'variant',
      ]);

      final categoryName = preserveSourceCategories
          ? _first(map, const ['category', 'cat']).trim()
          : (ItemImportService.canonicalMenuCategory(
                _first(map, const ['category', 'cat']),
              ) ??
              '');

      final key = _itemKey(name, subItem, category: categoryName);
      importedKeys.add(key);
      final existingItem = existingByKey[key];
      if (existingItem != null && !updateExisting) {
        result.skipped++;
        continue;
      }

      try {
        int? categoryId;
        if (categoryName.isNotEmpty) {
          categoryId = await _ensureCategory(categoryName, categories);
          categories = await Repository.instance.categories(
            type: 'raw_material',
          );
        } else {
          categoryId = null;
        }

        final packetsRaw = _first(map, const ['packets', 'packet']);
        final packets = _number(packetsRaw);
        final openingPieces = _number(_first(map, const [
          'openingpieces',
          'openingpiece',
          'loosepieces',
          'opening pieces',
        ]));
        final unitName = _first(map, const ['unit', 'uom']);
        int? unitId;
        if (unitName.isNotEmpty) {
          unitId = await _ensureUnit(unitName, units);
          units = await Repository.instance.units();
        }

        final qtyRaw = _first(map, const [
          'qtypersale',
          'qtyneeded',
          'qty',
          'qtysale',
        ]);
        final qtyNeeded = _number(qtyRaw) ?? 0;
        final unitsPerPacket = _number(_first(map, const [
          'unitsperpacket',
          'unitspacket',
          'upp',
        ]));
        var stock = _number(_first(map, const [
          'openingstock',
          'opening',
          'stock',
        ]));
        if (stock == null &&
            packets != null &&
            unitsPerPacket != null) {
          stock = (packets * unitsPerPacket) + (openingPieces ?? 0);
        }
        stock ??= 0;
        final resolvedOpeningPieces = openingPieces ??
            existingItem?.openingPieces ??
            0;

        final barcodeRaw = _first(map, const ['barcode', 'code', 'barcodeno', 'grouping']);
        final trimmedBarcode = barcodeRaw?.trim() ?? '';
        final groupingTag =
            ItemImportService.isGroupingTag(trimmedBarcode) ? trimmedBarcode : null;
        // PDF grouping labels (COMBO, SNACKS, BEVARGES, …) are not unique product
        // barcodes. Storing them in raw_materials.barcode violates its UNIQUE
        // constraint on the second row with the same label. The spreadsheet value
        // is preserved in menu_export_row for round-trip export instead.
        final String? barcode;
        if (trimmedBarcode.isEmpty || groupingTag != null) {
          barcode = null;
        } else {
          barcode = ItemImportService.normalizeBarcode(trimmedBarcode);
        }

        final listed = !ItemImportService.shouldHideFromSales(
          groupingTag: groupingTag,
          name: name,
          subItem: subItem.isEmpty ? null : subItem,
          category: categoryName,
        );

        final variantGroup = _emptyToNull(_first(map, const [
          'variantgroup',
          'variantgroupname',
        ]));
        final variantLabel = _emptyToNull(_first(map, const [
          'variantlabel',
          'variantsize',
          'size',
          'portion',
        ]));
        final stockSourceName = _first(map, const [
          'stocksourcename',
          'stocksource',
          'stockitem',
        ]);
        int? stockSourceId = existingItem?.stockSourceId;
        if (stockSourceName.isNotEmpty && stockSourceId == null) {
          stockSourceId = _resolveStockSourceId(
            stockSourceName,
            existingByKey,
            categoryName,
            targetLocationId: existingItem?.locationId ??
                Repository.instance.sessionLocationId,
          );
        }

        final saved = RawMaterial(
            id: existingItem?.id,
            barcode: barcode,
            name: name,
            subItem: subItem.isEmpty ? null : subItem,
            qtyNeeded: qtyNeeded,
            categoryId: categoryId,
            unitId: unitId,
            openingStock: stock,
            openingPieces: resolvedOpeningPieces,
            currentStock: stock,
            reorderLevel: existingItem?.reorderLevel ?? 0,
            shelfLifeDays: existingItem?.shelfLifeDays,
            unitsPerPacket: unitsPerPacket,
            entryPasswordHash: existingItem?.entryPasswordHash,
            costPrice: _number(_first(map, const [
              'costprice',
              'cp',
              'cost',
            ])),
            sellingPrice: _number(_first(map, const [
              'sellingprice',
              'sp',
              'selling',
              'price',
            ])),
            imagePath: existingItem?.imagePath,
            listed: listed,
            createdAt: existingItem?.createdAt,
            menuSortOrder: existingItem?.menuSortOrder,
            variantGroup: variantGroup ?? existingItem?.variantGroup,
            variantLabel: variantLabel ?? existingItem?.variantLabel,
            stockSourceId: stockSourceId,
          );
        final id = await Repository.instance.saveRawMaterial(
          saved,
          fromMenuImport: true,
          menuExportRow: buildMenuExportRow(headers, row),
          menuSortOrder: i - headerIndex,
        );

        existingByKey[key] = RawMaterial(
          id: id,
          barcode: saved.barcode,
          name: saved.name,
          subItem: saved.subItem,
          qtyNeeded: saved.qtyNeeded,
          categoryId: saved.categoryId,
          unitId: saved.unitId,
          openingStock: saved.openingStock,
          openingPieces: saved.openingPieces,
          currentStock: saved.currentStock,
          reorderLevel: saved.reorderLevel,
          shelfLifeDays: saved.shelfLifeDays,
          unitsPerPacket: saved.unitsPerPacket,
          entryPasswordHash: saved.entryPasswordHash,
          costPrice: saved.costPrice,
          sellingPrice: saved.sellingPrice,
          imagePath: saved.imagePath,
          listed: saved.listed,
          createdAt: saved.createdAt,
          menuSortOrder: i - headerIndex,
          variantGroup: saved.variantGroup,
          variantLabel: saved.variantLabel,
          stockSourceId: saved.stockSourceId,
        );
        if (existingItem == null) {
          result.created++;
        } else {
          result.updated++;
        }
      } catch (e) {
        result.errors.add('Row ${i + 1} ($name): $e');
      }
    }

    if (replaceCatalog) {
      final leftovers = await Repository.instance.rawMaterials(
        includeHidden: true,
      );
      for (final item in leftovers) {
        if (item.id == null) continue;
        final key = _itemKey(
          item.name,
          item.subItem,
          category: item.categoryId == null
              ? ''
              : categoryNameById[item.categoryId],
        );
        if (importedKeys.contains(key)) continue;
        try {
          await Repository.instance.deleteRawMaterial(item.id!);
        } catch (_) {
          await Repository.instance.hideRawMaterial(
            item.id!,
            source: ListedChangeSource.importCatalogPrune,
          );
        }
      }
    }

    if (postProcessAlreadyDone) {
      result.warnings.add(
        'Import post-processing (variant link, catalog dedup) was already '
        'applied for this exact file at this location; skipped to prevent '
        'duplicate listed/stock side effects.',
      );
    } else {
      await _applyVariantAutoLinking();
      await _runCatalogMaintenance();
      await _dedupeDuplicateVariantLabels();
      await _cleanupPopcornFromSnacksCombos();
      final recorded = await Repository.instance.tryRecordImportPostProcess(
        contentFingerprint,
      );
      if (!recorded) {
        result.warnings.add(
          'Another import of this file finished post-processing first; '
          'this run skipped duplicate maintenance.',
        );
      }
    }

    final mismatches = await Repository.instance.auditStockGroupMismatches();
    for (final mismatch in mismatches) {
      result.warnings.add(
        'Stock group "${mismatch.stockKey}" — ${mismatch.itemName}: '
        '${mismatch.detail}',
      );
    }

    return result;
  }

  /// Removes Chicken Popcorn from snack-style combo definitions only.
  Future<void> _cleanupPopcornFromSnacksCombos() async {
    final removed =
        await Repository.instance.removePopcornFromSnacksComboComponents();
    if (removed > 0) {
      // Logged via import result only when callers surface errors; silent cleanup.
    }
  }

  /// Hides duplicate size labels within the same POS variant group.
  Future<void> _dedupeDuplicateVariantLabels() async {
    final items = await Repository.instance.rawMaterials(includeHidden: true);
    final categories = await Repository.instance.categories(type: 'raw_material');
    final categoryNameById = {
      for (final category in categories)
        if (category.id != null) category.id!: category.name,
    };

    final partition = VariantHelpers.partitionForPos(
      items.where((item) => item.listed).toList(),
    );

    RawMaterial preferVariant(RawMaterial a, RawMaterial b) {
      String categoryName(RawMaterial item) {
        if (item.categoryId == null) return '';
        return categoryNameById[item.categoryId]?.trim().toLowerCase() ?? '';
      }

      final aFried = categoryName(a).replaceAll(' ', '') == 'frieditems';
      final bFried = categoryName(b).replaceAll(' ', '') == 'frieditems';
      if (aFried != bFried) return aFried ? a : b;

      final orderA = a.menuSortOrder ?? 1 << 30;
      final orderB = b.menuSortOrder ?? 1 << 30;
      if (orderA != orderB) return orderA < orderB ? a : b;

      return a.name.length <= b.name.length ? a : b;
    }

    for (final group in partition.groups) {
      final winners = <String, RawMaterial>{};
      for (final variant in group.variants) {
        if (variant.id == null) continue;
        final label = SubItemStock.normalizeVariantLabel(
          VariantHelpers.variantSelectorLabel(variant),
        );
        final existing = winners[label];
        if (existing == null) {
          winners[label] = variant;
          continue;
        }

        final keep = preferVariant(existing, variant);
        final drop = keep.id == existing.id ? variant : existing;
        if (drop.id != null) {
          await Repository.instance.hideRawMaterial(
            drop.id!,
            source: ListedChangeSource.importVariantDedup,
          );
        }
        winners[label] = keep;
      }
    }
  }

  Future<void> _runCatalogMaintenance() async {
    final db = await Repository.instance.sharedAppDb();
    await runCatalogMaintenance(
      db,
      aggressiveDedup: true,
      syncAutoCombos: true,
    );
  }

  Future<void> _applyVariantAutoLinking() async {
    final items = await Repository.instance.rawMaterials(
      includeHidden: true,
    );
    final categories = await Repository.instance.categories(
      type: 'raw_material',
    );
    final categoryNameById = {
      for (final category in categories)
        if (category.id != null) category.id!: category.name,
    };
    final updates = VariantHelpers.syncVariantLinks(
      items,
      categoryNameById: categoryNameById,
    );
    for (final item in updates) {
      await Repository.instance.saveRawMaterial(
        item,
        skipVariantRefresh: true,
      );
    }
  }

  int? _resolveStockSourceId(
    String stockSourceName,
    Map<String, RawMaterial> existingByKey,
    String categoryName, {
    int? targetLocationId,
  }) {
    final target = stockSourceName.trim().toLowerCase();
    if (target.isEmpty) return null;

    bool sameLocation(RawMaterial item) {
      if (targetLocationId == null || item.locationId == null) return true;
      return item.locationId == targetLocationId;
    }

    for (final item in existingByKey.values) {
      if (item.id == null || !sameLocation(item)) continue;
      if (item.name.trim().toLowerCase() == target) {
        return item.id;
      }
    }

    for (final item in existingByKey.values) {
      if (item.id == null || !sameLocation(item)) continue;
      final sub = item.subItem?.trim().toLowerCase() ?? '';
      if (sub == target || item.name.trim().toLowerCase() == target) {
        return item.id;
      }
    }

    return null;
  }

  Future<int> _ensureCategory(
    String name,
    List<Category> categories,
  ) async {
    final canonical = ItemImportService.canonicalMenuCategory(name) ?? name.trim();
    final matchNames = <String>{
      canonical.toLowerCase(),
      name.trim().toLowerCase(),
    };
    if (canonical.toLowerCase() == 'uncategorized') {
      matchNames.addAll(['others', 'other', 'uncategorized']);
    }
    for (final category in categories) {
      if (category.id == null) continue;
      if (matchNames.contains(category.name.trim().toLowerCase())) {
        return category.id!;
      }
    }
    return Repository.instance.addCategory(
      Category(name: canonical, type: 'raw_material'),
    );
  }

  Future<int> _ensureUnit(String name, List<UnitM> units) async {
    final normalized = name.trim().toLowerCase();
    final aliases = {
      'g': 'g',
      'gm': 'g',
      'gms': 'g',
      'gram': 'g',
      'grams': 'g',
      'pc': 'pc',
      'pcs': 'pc',
      'piece': 'pc',
      'pieces': 'pc',
    };
    final lookup = aliases[normalized] ?? normalized;
    for (final unit in units) {
      if (unit.name.trim().toLowerCase() == lookup ||
          unit.shortCode.trim().toLowerCase() == lookup) {
        return unit.id!;
      }
    }
    final displayName = lookup == 'g'
        ? 'Gram'
        : lookup == 'pc'
            ? 'Piece'
            : name.trim();
    final short = lookup.length <= 6 ? lookup : lookup.substring(0, 6);
    return Repository.instance.addUnit(
      UnitM(name: displayName, shortCode: short),
    );
  }

  String _first(Map<String, String> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  String _itemKey(
    String name,
    String? subItem, {
    String? category,
  }) {
    return ItemImportService().itemKeyFor(name, subItem, category: category);
  }

  String _normalizeKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  double? _number(String value) {
    if (value.trim().isEmpty) return null;
    return double.tryParse(value.trim().replaceAll(',', ''));
  }

  List<List<String>> _parseCsv(String text) {
    var source = text;
    if (source.startsWith('\uFEFF')) {
      source = source.substring(1);
    }
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < source.length; i++) {
      final ch = source[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < source.length && source[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',' || ch == ';' || ch == '\t') {
        row.add(cell.toString());
        cell.clear();
      } else if (ch == '\n') {
        row.add(cell.toString());
        cell.clear();
        rows.add(row);
        row = [];
      } else if (ch != '\r') {
        cell.write(ch);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      rows.add(row);
    }
    return rows;
  }

  List<List<String>> _parseXlsx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final strings = <String>[];
    final shared = archive.findFile('xl/sharedStrings.xml');
    if (shared != null) {
      final xml = utf8.decode(shared.content as List<int>, allowMalformed: true);
      final siBlocks = RegExp(r'<si>([\s\S]*?)</si>').allMatches(xml);
      for (final si in siBlocks) {
        final texts = RegExp(r'<t[^>]*>([\s\S]*?)</t>')
            .allMatches(si.group(1)!)
            .map((m) => _unescapeXml(m.group(1)!))
            .join();
        strings.add(texts);
      }
    }

    ArchiveFile? sheet;
    for (final file in archive.files) {
      if (file.name.startsWith('xl/worksheets/sheet') &&
          file.name.endsWith('.xml')) {
        sheet = file;
        break;
      }
    }
    if (sheet == null) {
      throw InvalidInventoryException('Could not read the Excel sheet.');
    }

    final xml = utf8.decode(sheet.content as List<int>, allowMalformed: true);
    final rows = <List<String>>[];
    final rowMatches =
        RegExp(r'<(?:\w+:)?row\b[^>]*>([\s\S]*?)</(?:\w+:)?row>')
            .allMatches(xml);
    for (final rowMatch in rowMatches) {
      final cells = <int, String>{};
      final cellMatches =
          RegExp(r'<(?:\w+:)?c\b([^>]*)>([\s\S]*?)</(?:\w+:)?c>')
              .allMatches(rowMatch.group(1)!);
      var maxCol = 0;
      for (final cell in cellMatches) {
        final attrs = cell.group(1)!;
        final body = cell.group(2)!;
        final ref = RegExp(r'r="([A-Z]+)(\d+)"').firstMatch(attrs);
        final col = ref == null ? maxCol : _columnIndex(ref.group(1)!);
        maxCol = col > maxCol ? col : maxCol;
        final type = RegExp(r't="([^"]+)"').firstMatch(attrs)?.group(1);
        String value = '';
        if (type == 's') {
          final index = int.tryParse(
                RegExp(r'<v[^>]*>([\s\S]*?)</v>').firstMatch(body)?.group(1) ??
                    '',
              ) ??
              -1;
          if (index >= 0 && index < strings.length) value = strings[index];
        } else if (type == 'inlineStr') {
          value = RegExp(r'<t[^>]*>([\s\S]*?)</t>')
                  .firstMatch(body)
                  ?.group(1) ??
              '';
          value = _unescapeXml(value);
        } else {
          value = _unescapeXml(
            RegExp(r'<v[^>]*>([\s\S]*?)</v>').firstMatch(body)?.group(1) ?? '',
          );
        }
        cells[col] = value;
      }
      final row = List<String>.generate(maxCol + 1, (i) => cells[i] ?? '');
      rows.add(row);
    }
    return rows;
  }

  int _columnIndex(String letters) {
    var n = 0;
    for (final code in letters.codeUnits) {
      n = n * 26 + (code - 64);
    }
    return n - 1;
  }

  String _unescapeXml(String value) {
    return value
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }
}
