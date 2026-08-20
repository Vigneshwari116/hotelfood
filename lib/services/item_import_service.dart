import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

/// One spreadsheet row ready to be saved as a catalog item.
class ParsedItemRow {
  final int lineNumber;
  final String name;
  final String? barcode;
  final String? category;
  final String? unit;
  final String? unitCode;
  final double? openingStock;
  final double? reorderLevel;
  final double? costPrice;
  final double? sellingPrice;
  final int? shelfLifeDays;
  final double? unitsPerPacket;

  const ParsedItemRow({
    required this.lineNumber,
    required this.name,
    this.barcode,
    this.category,
    this.unit,
    this.unitCode,
    this.openingStock,
    this.reorderLevel,
    this.costPrice,
    this.sellingPrice,
    this.shelfLifeDays,
    this.unitsPerPacket,
  });
}

class ItemImportParseResult {
  final List<ParsedItemRow> rows;
  final List<String> errors;

  const ItemImportParseResult({
    required this.rows,
    required this.errors,
  });
}

class ItemImportResult {
  final int created;
  final int updated;
  final int skipped;
  final List<String> errors;

  const ItemImportResult({
    required this.created,
    required this.updated,
    required this.skipped,
    required this.errors,
  });
}

/// Parses CSV and Excel item lists. This is the right bulk-load path:
/// a spreadsheet is structured data; a PDF chart is not.
class ItemSpreadsheetParser {
  static const templateCsv = '''name,barcode,category,unit,unit_code,opening_stock,reorder_level,cost_price,selling_price,shelf_life_days,units_per_packet
Chicken Popcorn,,Frozen Snacks,Packet,pkt,0,10,120,180,90,1
Coke 300ml,8901234567890,Beverages,Bottle,btl,0,24,20,35,,
''';

  static const _nameKeys = [
    'name',
    'item',
    'item name',
    'item_name',
    'product',
    'product name',
    'menu item',
    'menu_item',
  ];

  static const _barcodeKeys = [
    'barcode',
    'sku',
    'code',
    'item code',
    'item_code',
  ];

  static const _categoryKeys = [
    'category',
    'category name',
    'category_name',
    'group',
  ];

  static const _unitKeys = [
    'unit',
    'uom',
    'unit name',
    'unit_name',
  ];

  static const _unitCodeKeys = [
    'unit_code',
    'unit code',
    'short_code',
    'short code',
    'uom code',
  ];

  static const _openingKeys = [
    'opening_stock',
    'opening stock',
    'opening',
    'stock',
  ];

  static const _reorderKeys = [
    'reorder_level',
    'reorder level',
    'reorder',
    'min stock',
    'min_stock',
  ];

  static const _costKeys = [
    'cost_price',
    'cost price',
    'cost',
    'purchase price',
  ];

  static const _sellingKeys = [
    'selling_price',
    'selling price',
    'selling',
    'price',
    'mrp',
    'sale price',
  ];

  static const _shelfKeys = [
    'shelf_life_days',
    'shelf life',
    'shelf life days',
    'expiry days',
  ];

  static const _packetKeys = [
    'units_per_packet',
    'units per packet',
    'pack size',
    'pack_size',
  ];

  static ItemImportParseResult parseFile({
    required String fileName,
    required Uint8List bytes,
  }) {
    final lower = fileName.toLowerCase();

    if (lower.endsWith('.csv') || lower.endsWith('.txt')) {
      return parseCsv(utf8.decode(bytes, allowMalformed: true));
    }

    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      try {
        return parseExcel(bytes);
      } catch (e) {
        return ItemImportParseResult(
          rows: const [],
          errors: [
            'Could not read the Excel file. Save it as .xlsx or .csv and try again. ($e)',
          ],
        );
      }
    }

    return const ItemImportParseResult(
      rows: [],
      errors: [
        'Unsupported file type. Use .csv or .xlsx.',
      ],
    );
  }

  static ItemImportParseResult parseCsv(String text) {
    final trimmed = text.replaceFirst(RegExp(r'^\uFEFF'), '');

    if (trimmed.trim().isEmpty) {
      return const ItemImportParseResult(
        rows: [],
        errors: ['The file is empty.'],
      );
    }

    final table = const CsvToListConverter(
      shouldParseNumbers: false,
    ).convert(trimmed);

    return _fromTable(table);
  }

  static ItemImportParseResult parseExcel(Uint8List bytes) {
    final book = Excel.decodeBytes(bytes);

    if (book.tables.isEmpty) {
      return const ItemImportParseResult(
        rows: [],
        errors: ['The spreadsheet has no sheets.'],
      );
    }

    final sheet = book.tables.values.first;
    final table = <List<dynamic>>[];

    for (final row in sheet.rows) {
      table.add([
        for (final cell in row) _cellText(cell?.value),
      ]);
    }

    return _fromTable(table);
  }

  static ItemImportParseResult _fromTable(List<List<dynamic>> table) {
    final errors = <String>[];

    if (table.isEmpty) {
      return ItemImportParseResult(
        rows: const [],
        errors: ['The file is empty.'],
      );
    }

    final headerIndex = table.indexWhere((row) {
      return row.any((cell) => _cellText(cell).isNotEmpty);
    });

    if (headerIndex < 0) {
      return ItemImportParseResult(
        rows: const [],
        errors: ['No header row was found.'],
      );
    }

    final headers = [
      for (final cell in table[headerIndex]) _normalizeHeader(_cellText(cell)),
    ];

    final nameIndex = _firstHeader(headers, _nameKeys);

    if (nameIndex == null) {
      return ItemImportParseResult(
        rows: const [],
        errors: [
          'A Name / Item Name column is required. '
              'Download the CSV template for the expected headers.',
        ],
      );
    }

    final rows = <ParsedItemRow>[];

    for (var i = headerIndex + 1; i < table.length; i++) {
      final lineNumber = i + 1;
      final raw = table[i];

      if (_rowEmpty(raw)) {
        continue;
      }

      String at(List<String> keys) {
        final index = _firstHeader(headers, keys);
        if (index == null || index >= raw.length) {
          return '';
        }
        return _cellText(raw[index]);
      }

      final name = at(_nameKeys);

      if (name.isEmpty) {
        errors.add('Row $lineNumber: item name is empty.');
        continue;
      }

      try {
        rows.add(
          ParsedItemRow(
            lineNumber: lineNumber,
            name: name,
            barcode: _optional(at(_barcodeKeys)),
            category: _optional(at(_categoryKeys)),
            unit: _optional(at(_unitKeys)),
            unitCode: _optional(at(_unitCodeKeys)),
            openingStock: _optionalDouble(at(_openingKeys), lineNumber, 'opening stock', errors),
            reorderLevel: _optionalDouble(at(_reorderKeys), lineNumber, 'reorder level', errors),
            costPrice: _optionalDouble(at(_costKeys), lineNumber, 'cost price', errors),
            sellingPrice: _optionalDouble(at(_sellingKeys), lineNumber, 'selling price', errors),
            shelfLifeDays: _optionalInt(at(_shelfKeys), lineNumber, 'shelf life days', errors),
            unitsPerPacket: _optionalDouble(at(_packetKeys), lineNumber, 'units per packet', errors),
          ),
        );
      } catch (e) {
        errors.add('Row $lineNumber: $e');
      }
    }

    if (rows.isEmpty && errors.isEmpty) {
      errors.add('No item rows were found under the header.');
    }

    return ItemImportParseResult(rows: rows, errors: errors);
  }

  static int? _firstHeader(List<String> headers, List<String> keys) {
    for (final key in keys) {
      final index = headers.indexOf(_normalizeHeader(key));
      if (index >= 0) {
        return index;
      }
    }
    return null;
  }

  static String _normalizeHeader(String value) {
    return value.trim().toLowerCase().replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _cellText(dynamic value) {
    if (value == null) {
      return '';
    }

    if (value is num) {
      if (value == value.roundToDouble()) {
        return value.round().toString();
      }
      return value.toString();
    }

    if (value is String) {
      return value.trim();
    }

    try {
      final inner = (value as dynamic).value;
      if (!identical(inner, value)) {
        return _cellText(inner);
      }
    } catch (_) {
      // Not an excel CellValue.
    }

    return value.toString().trim();
  }

  static bool _rowEmpty(List<dynamic> row) {
    return row.every((cell) => _cellText(cell).isEmpty);
  }

  static String? _optional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static double? _optionalDouble(
    String value,
    int lineNumber,
    String label,
    List<String> errors,
  ) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final parsed = double.tryParse(trimmed.replaceAll(',', ''));
    if (parsed == null) {
      errors.add('Row $lineNumber: $label "$trimmed" is not a number.');
      return null;
    }

    return parsed;
  }

  static int? _optionalInt(
    String value,
    int lineNumber,
    String label,
    List<String> errors,
  ) {
    final parsed = _optionalDouble(value, lineNumber, label, errors);
    return parsed?.round();
  }
}
