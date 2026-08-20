import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/item_import_service.dart';

void main() {
  test('parses CSV headers and quoted item names', () {
    const csv = '''Name,Category,Unit,Selling Price,Barcode
"Chicken, Popcorn",Frozen Snacks,pkt,180,ABC-1
Coke,Beverages,btl,35,
''';

    final result = ItemSpreadsheetParser.parseCsv(csv);

    expect(result.errors, isEmpty);
    expect(result.rows, hasLength(2));
    expect(result.rows[0].name, 'Chicken, Popcorn');
    expect(result.rows[0].category, 'Frozen Snacks');
    expect(result.rows[0].unit, 'pkt');
    expect(result.rows[0].sellingPrice, 180);
    expect(result.rows[0].barcode, 'ABC-1');
    expect(result.rows[1].name, 'Coke');
    expect(result.rows[1].barcode, isNull);
  });

  test('rejects files without a name column', () {
    const csv = 'category,price\nSnacks,10\n';
    final result = ItemSpreadsheetParser.parseCsv(csv);

    expect(result.rows, isEmpty);
    expect(result.errors.single, contains('Name'));
  });

  test('parseFile accepts csv by extension', () {
    final result = ItemSpreadsheetParser.parseFile(
      fileName: 'items.csv',
      bytes: Uint8List.fromList(
        utf8.encode(ItemSpreadsheetParser.templateCsv),
      ),
    );

    expect(result.rows, hasLength(2));
    expect(result.rows.first.name, 'Chicken Popcorn');
    expect(result.rows.last.barcode, '8901234567890');
  });

  test('parseFile rejects unknown extensions', () {
    final result = ItemSpreadsheetParser.parseFile(
      fileName: 'chart.pdf',
      bytes: Uint8List.fromList(utf8.encode('not a sheet')),
    );

    expect(result.rows, isEmpty);
    expect(result.errors.single, contains('Unsupported'));
  });
}
