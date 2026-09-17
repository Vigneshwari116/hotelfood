import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('grid export rows match grid columns and include stock source', () async {
    final database = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        final now = DateTime.now().toIso8601String();
        await db.execute('''
          CREATE TABLE categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            type TEXT NOT NULL DEFAULT 'raw_material'
          )
        ''');
        await db.insert('categories', {'name': 'Burgers'});
        await db.insert('categories', {'name': 'Fried Items'});
        await db.execute('''
          CREATE TABLE location_stock (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            location_id INTEGER NOT NULL,
            raw_material_id INTEGER NOT NULL,
            current_stock REAL NOT NULL DEFAULT 0,
            opening_stock REAL NOT NULL DEFAULT 0,
            reorder_level REAL NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE units (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            short_code TEXT NOT NULL
          )
        ''');
        await db.insert('units', {'name': 'Piece', 'short_code': 'pc'});
        await db.execute('''
          CREATE TABLE raw_materials (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            sub_item TEXT,
            barcode TEXT,
            qty_needed REAL NOT NULL DEFAULT 1,
            category_id INTEGER,
            menu_sort_order INTEGER,
            unit_id INTEGER,
            variant_group TEXT,
            variant_label TEXT,
            stock_source_id INTEGER,
            units_per_packet REAL,
            opening_pieces REAL NOT NULL DEFAULT 0,
            listed INTEGER NOT NULL DEFAULT 1,
            current_stock REAL NOT NULL DEFAULT 0,
            opening_stock REAL NOT NULL DEFAULT 0,
            reorder_level REAL NOT NULL DEFAULT 0,
            cost_price REAL,
            selling_price REAL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE combos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            barcode TEXT,
            category_id INTEGER,
            price REAL NOT NULL DEFAULT 0,
            selling_price REAL NOT NULL DEFAULT 0,
            image_path TEXT,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE combo_raw_materials (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            combo_id INTEGER NOT NULL,
            raw_material_id INTEGER NOT NULL,
            qty REAL NOT NULL DEFAULT 1
          )
        ''');
        await db.insert('raw_materials', {
          'id': 1,
          'name': 'Burger Bun With Sesame',
          'sub_item': 'Burger Bun With Sesame',
          'category_id': 2,
          'unit_id': 1,
          'units_per_packet': 10,
          'opening_pieces': 2,
          'current_stock': 22,
          'opening_stock': 22,
          'created_at': now,
        });
        await db.insert('location_stock', {
          'location_id': 1,
          'raw_material_id': 1,
          'current_stock': 22,
          'opening_stock': 22,
        });
        await db.insert('raw_materials', {
          'id': 2,
          'name': 'Hot Crispy Patty',
          'sub_item': 'Hot Crispy Patty',
          'category_id': 1,
          'qty_needed': 5,
          'created_at': now,
        });
      },
    );

    Repository.instance.setAppDbForTesting(SqliteAppDb(database));
    Repository.instance.bindSession(
      role: 'location',
      locationId: 1,
      locationName: 'Gt world mall',
    );

    await Repository.instance.saveCombo(
      Combo(name: 'Big juicy burger', categoryId: 1, price: 129),
      [
        ComboRawMaterial(comboId: 0, rawMaterialId: 2, qty: 5),
        ComboRawMaterial(comboId: 0, rawMaterialId: 1, qty: 1),
      ],
    );

    final service = ItemImportService();
    final rows = await service.gridExportRowsForLocation(1);
    expect(rows, hasLength(2));

    final pattyRow = rows.firstWhere((row) => row[2] == 'Hot Crispy Patty');
    expect(pattyRow[0], 'Burgers');
    expect(pattyRow[11], '5');

    final bunRow = rows.firstWhere((row) => row[2] == 'Burger Bun With Sesame');
    expect(bunRow[7], '10');
    expect(bunRow[9], '2');
    expect(bunRow[10], '22');

    final comboRows = await service.comboExportRows();
    expect(comboRows, hasLength(2));
    expect(comboRows.map((row) => row[3]), contains('Hot Crispy Patty'));

    Repository.instance.setAppDbForTesting(null);
    await database.close();
  });
}
