import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/repository.dart';
import 'package:foodstock/services/sales_export_service.dart';
import 'package:foodstock/services/spreadsheet_export.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test('import filename must match location name exactly', () {
    final service = ItemImportService();
    expect(
      () => service.validateImportFilename(
        '/tmp/Gt world mall.xlsx',
        'Gt world mall',
      ),
      returnsNormally,
    );
    expect(
      () => service.validateImportFilename(
        '/tmp/Magadi road.xlsx',
        'Gt world mall',
      ),
      throwsA(
        isA<InvalidInventoryException>().having(
          (e) => e.message,
          'message',
          'This file is for a different location',
        ),
      ),
    );
  });

  test('sales export includes customer columns', () {
    final csv = SalesExportService.buildCsv([
      {
        'id': 1,
        'sale_date': '2026-09-04T10:00:00.000',
        'location_name': 'Gt world mall',
        'customer_name': 'Ravi',
        'customer_phone': '9876543210',
        'subtotal': 100,
        'tax': 0,
        'discount': 0,
        'total': 100,
        'payment_type': 'cash',
        'is_voided': 0,
      },
    ]);

    expect(csv, contains('customer_name'));
    expect(csv, contains('mobile'));
    expect(csv, contains('Ravi'));
    expect(csv, contains('9876543210'));
  });

  test('menu export reads live selling price from database', () async {
    final db = await openDatabase(inMemoryDatabasePath);
    final now = DateTime.now().toIso8601String();

    await db.execute('''
      CREATE TABLE locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE units (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        short_code TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE raw_materials (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        sub_item TEXT,
        barcode TEXT,
        qty_needed REAL NOT NULL DEFAULT 1,
        category_id INTEGER,
        unit_id INTEGER,
        opening_stock REAL NOT NULL DEFAULT 0,
        current_stock REAL NOT NULL DEFAULT 0,
        reorder_level REAL NOT NULL DEFAULT 0,
        units_per_packet REAL,
        cost_price REAL,
        selling_price REAL,
        listed INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE location_stock (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        location_id INTEGER NOT NULL,
        raw_material_id INTEGER NOT NULL,
        opening_stock REAL NOT NULL DEFAULT 0,
        current_stock REAL NOT NULL DEFAULT 0,
        reorder_level REAL NOT NULL DEFAULT 0
      )
    ''');

    await db.insert('locations', {'name': 'Gt world mall'});
    await db.insert('categories', {'name': 'Snacks', 'type': 'raw_material'});
    await db.insert('units', {'name': 'Piece', 'short_code': 'pc'});
    await db.insert('raw_materials', {
      'name': 'Chicken 65',
      'sub_item': 'Chicken 65',
      'barcode': 'SNACKS',
      'qty_needed': 1,
      'category_id': 1,
      'unit_id': 1,
      'opening_stock': 0,
      'current_stock': 0,
      'selling_price': 85,
      'listed': 1,
      'created_at': now,
    });
    await db.insert('location_stock', {
      'location_id': 1,
      'raw_material_id': 1,
      'opening_stock': 0,
      'current_stock': 0,
    });

    await db.update(
      'raw_materials',
      {'selling_price': 99},
      where: 'id = ?',
      whereArgs: [1],
    );

    final rows = await db.rawQuery('''
      SELECT
        COALESCE(c.name, '') AS category,
        rm.name AS item_name,
        COALESCE(rm.sub_item, '') AS sub_item,
        COALESCE(rm.barcode, '') AS barcode,
        rm.qty_needed AS qty_per_sale,
        rm.units_per_packet AS units_per_packet,
        COALESCE(u.short_code, '') AS unit,
        COALESCE(ls.opening_stock, 0) AS opening_stock,
        rm.cost_price AS cost_price,
        rm.selling_price AS selling_price
      FROM raw_materials rm
      LEFT JOIN categories c ON c.id = rm.category_id
      LEFT JOIN units u ON u.id = rm.unit_id
      LEFT JOIN location_stock ls
        ON ls.raw_material_id = rm.id
        AND ls.location_id = ?
      WHERE rm.listed IS NULL OR rm.listed = 1
    ''', [1]);

    expect(rows.single['selling_price'], 99);

    final xlsx = SpreadsheetExport.buildXlsx(
      ItemImportService.menuHeaders,
      [
        [
          rows.single['category'].toString(),
          rows.single['item_name'].toString(),
          rows.single['sub_item'].toString(),
          rows.single['barcode'].toString(),
          rows.single['qty_per_sale'].toString(),
          '',
          rows.single['units_per_packet']?.toString() ?? '',
          rows.single['unit'].toString(),
          rows.single['opening_stock'].toString(),
          rows.single['cost_price']?.toString() ?? '',
          rows.single['selling_price'].toString(),
        ],
      ],
    );

    expect(xlsx.length, greaterThan(100));
    await db.close();
  });

  test('spreadsheet export builds non-empty xlsx bytes', () {
    final bytes = SpreadsheetExport.buildXlsx(
      const ['a', 'b'],
      const [
        ['1', 'two'],
      ],
    );
    expect(bytes.length, greaterThan(100));
    expect(String.fromCharCodes(bytes.take(2)), 'PK');
  });
}
