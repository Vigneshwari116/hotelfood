import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/repository.dart';
import 'package:path/path.dart' as p;

class ItemImportResult {
  int created = 0;
  int updated = 0;
  int skipped = 0;
  final List<String> errors = [];
}

class ItemImportService {
  Future<ItemImportResult> importFile(String path) async {
    final ext = p.extension(path).toLowerCase();
    final bytes = await File(path).readAsBytes();
    if (ext == '.xls') {
      throw InvalidInventoryException(
        'Old .xls files are not supported. Save as .xlsx or CSV and import again.',
      );
    }
    final rows = ext == '.xlsx'
        ? _parseXlsx(bytes)
        : _parseCsv(utf8.decode(bytes, allowMalformed: true));

    return _importRows(rows, updateExisting: true);
  }

  Future<ItemImportResult> importCsvText(
    String text, {
    bool updateExisting = false,
  }) {
    return _importRows(_parseCsv(text), updateExisting: updateExisting);
  }

  Future<ItemImportResult> importXlsxBytes(Uint8List bytes) {
    return _importRows(_parseXlsx(bytes), updateExisting: false);
  }

  String exportCsv({
    required List<RawMaterial> items,
    required List<Category> categories,
    required List<UnitM> units,
  }) {
    String categoryName(int? id) {
      for (final category in categories) {
        if (category.id == id) return category.name;
      }
      return '';
    }

    String unitCode(int? id) {
      for (final unit in units) {
        if (unit.id == id) return unit.shortCode;
      }
      return '';
    }

    String numOrEmpty(double? value) {
      if (value == null) return '';
      return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
    }

    final buffer = StringBuffer();
    buffer.writeln(
      'category,item_name,sub_item,barcode,qty_per_sale,packets,units_per_packet,unit,opening stock,cost_price,selling_price',
    );
    for (final item in items) {
      String packets = '';
      if (item.unitsPerPacket != null &&
          item.unitsPerPacket! > 0 &&
          item.currentStock > 0) {
        packets = numOrEmpty(item.currentStock / item.unitsPerPacket!);
      }
      buffer.writeln(
        [
          categoryName(item.categoryId),
          item.name,
          item.subItem ?? item.name,
          item.barcode ?? '',
          numOrEmpty(item.qtyNeeded),
          packets,
          numOrEmpty(item.unitsPerPacket),
          unitCode(item.unitId),
          numOrEmpty(item.currentStock),
          numOrEmpty(item.costPrice),
          numOrEmpty(item.sellingPrice),
        ].map(_csvCell).join(','),
      );
    }
    return '\uFEFF${buffer.toString()}';
  }

  String _csvCell(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<ItemImportResult> _importRows(
    List<List<String>> rows, {
    required bool updateExisting,
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

    final existing = await Repository.instance.rawMaterials();
    final existingByKey = <String, RawMaterial>{
      for (final item in existing)
        _itemKey(item.name, item.subItem): item,
    };

    var categories = await Repository.instance.categories(type: 'raw_material');
    var units = await Repository.instance.units();

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
        result.errors.add('Row ${i + 1}: missing item name.');
        continue;
      }

      final subItem = _first(map, const [
        'subitem',
        'subitemname',
        'sub',
        'variant',
      ]);
      final key = _itemKey(name, subItem);
      final existingItem = existingByKey[key];
      if (existingItem != null && !updateExisting) {
        result.skipped++;
        continue;
      }

      try {
        final categoryName = _first(map, const ['category', 'cat']);
        int? categoryId;
        if (categoryName.isNotEmpty) {
          categoryId = await _ensureCategory(categoryName, categories);
          categories = await Repository.instance.categories(
            type: 'raw_material',
          );
        } else {
          categoryId = existingItem?.categoryId;
        }

        final unitName = _first(map, const ['unit', 'uom']);
        int? unitId;
        if (unitName.isNotEmpty) {
          unitId = await _ensureUnit(unitName, units);
          units = await Repository.instance.units();
        } else if (existingItem?.unitId != null) {
          unitId = existingItem!.unitId;
        } else if (units.isNotEmpty) {
          unitId = units.first.id;
        }

        final qtyNeeded = _number(_first(map, const [
              'qtypersale',
              'qtyneeded',
              'qty',
              'qtysale',
            ])) ??
            1;
        final packets = _number(_first(map, const ['packets', 'packet']));
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
          stock = packets * unitsPerPacket;
        }
        stock ??= 0;

        final keepLiveStock =
            existingItem != null && (stock == null || stock == 0);

        final saved = RawMaterial(
            id: existingItem?.id,
            barcode: _emptyToNull(_first(map, const ['barcode', 'code'])),
            name: name,
            subItem: subItem.isEmpty ? name : subItem,
            qtyNeeded: qtyNeeded,
            categoryId: categoryId,
            unitId: unitId,
            openingStock: keepLiveStock
                ? existingItem!.openingStock
                : (stock ?? 0),
            currentStock: keepLiveStock
                ? existingItem!.currentStock
                : (stock ?? 0),
            reorderLevel: existingItem?.reorderLevel ?? 0,
            shelfLifeDays: existingItem?.shelfLifeDays,
            unitsPerPacket: unitsPerPacket ?? existingItem?.unitsPerPacket,
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
            createdAt: existingItem?.createdAt,
          );
        final id = await Repository.instance.saveRawMaterial(saved);

        existingByKey[key] = RawMaterial(
          id: id,
          barcode: saved.barcode,
          name: saved.name,
          subItem: saved.subItem,
          qtyNeeded: saved.qtyNeeded,
          categoryId: saved.categoryId,
          unitId: saved.unitId,
          openingStock: saved.openingStock,
          currentStock: saved.currentStock,
          reorderLevel: saved.reorderLevel,
          shelfLifeDays: saved.shelfLifeDays,
          unitsPerPacket: saved.unitsPerPacket,
          entryPasswordHash: saved.entryPasswordHash,
          costPrice: saved.costPrice,
          sellingPrice: saved.sellingPrice,
          imagePath: saved.imagePath,
          createdAt: saved.createdAt,
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

    return result;
  }

  Future<int> _ensureCategory(
    String name,
    List<Category> categories,
  ) async {
    final key = name.trim().toLowerCase();
    for (final category in categories) {
      if (category.name.trim().toLowerCase() == key && category.id != null) {
        return category.id!;
      }
    }
    return Repository.instance.addCategory(
      Category(name: name.trim(), type: 'raw_material'),
    );
  }

  Future<int> _ensureUnit(String name, List<UnitM> units) async {
    const aliases = {
      'gms': 'g',
      'gm': 'g',
      'grams': 'g',
      'gram': 'g',
      'pcs': 'pc',
      'piece': 'pc',
      'pieces': 'pc',
    };
    final key = aliases[name.trim().toLowerCase()] ??
        name.trim().toLowerCase();
    for (final unit in units) {
      if (unit.name.trim().toLowerCase() == key ||
          unit.shortCode.trim().toLowerCase() == key) {
        return unit.id!;
      }
    }
    final short = name.trim().length <= 6 ? name.trim() : name.trim().substring(0, 6);
    return Repository.instance.addUnit(
      UnitM(name: name.trim(), shortCode: short),
    );
  }

  String _first(Map<String, String> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  String _itemKey(String name, String? subItem) {
    return '${name.trim().toLowerCase()}|${(subItem ?? '').trim().toLowerCase()}';
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
