import 'dart:convert';

import 'package:archive/archive.dart';
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
        await db.insert('categories', {'name': 'Snacks'});
        await db.insert('categories', {'name': 'Rolls'});
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
            created_at TEXT NOT NULL,
            location_id INTEGER
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
            location_id INTEGER,
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
        await db.insert('raw_materials', {
          'id': 3,
          'name': 'Popcorn Small',
          'sub_item': 'Popcorn Small',
          'category_id': 3,
          'selling_price': 49,
          'created_at': now,
        });
        await db.insert('raw_materials', {
          'id': 4,
          'name': 'Kathi Roll Paratha',
          'sub_item': 'Kathi Roll Paratha',
          'category_id': 4,
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
    expect(rows, hasLength(1));
    expect(rows.map((row) => row[2]), isNot(contains('Hot Crispy Patty')));
    expect(rows.map((row) => row[2]), isNot(contains('Burger Bun With Sesame')));
    expect(rows.map((row) => row[2]), isNot(contains('Kathi Roll Paratha')));

    final snackRow = rows.single;
    expect(snackRow[0], 'Snacks');
    expect(snackRow[2], 'Popcorn Small');
    expect(snackRow[13], '49');

    final comboRows = await service.comboExportRows();
    expect(comboRows, hasLength(3));
    expect(comboRows[0][0], contains('Big juicy burger'));
    expect(comboRows.map((row) => row[1]), contains('Hot Crispy Patty'));
    expect(comboRows.map((row) => row[1]), contains('Burger Bun With Sesame'));

    final backupBytes = await service.exportBackupWorkbookForLocation(1);
    final archive = ZipDecoder().decodeBytes(backupBytes);
    final workbook = utf8.decode(
      archive.findFile('xl/workbook.xml')!.content as List<int>,
    );
    expect(workbook, contains('Menu Items'));
    expect(workbook, contains('Combos'));
    expect(archive.findFile('xl/worksheets/sheet1.xml'), isNotNull);
    expect(archive.findFile('xl/worksheets/sheet2.xml'), isNotNull);

    Repository.instance.setAppDbForTesting(null);
    await database.close();
  });

  test('backup export includes only current location catalog rows', () async {
    final database = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        final now = DateTime.now().toIso8601String();
        await db.execute('''
          CREATE TABLE locations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.insert('locations', {'name': 'Shop A', 'created_at': now});
        await db.insert('locations', {'name': 'Shop B', 'created_at': now});
        await db.execute('''
          CREATE TABLE categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            type TEXT NOT NULL DEFAULT 'raw_material'
          )
        ''');
        await db.insert('categories', {'name': 'Snacks'});
        await db.execute('''
          CREATE TABLE units (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            short_code TEXT NOT NULL
          )
        ''');
        await db.insert('units', {'name': 'Piece', 'short_code': 'pc'});
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
          CREATE TABLE raw_materials (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            sub_item TEXT,
            listed INTEGER NOT NULL DEFAULT 1,
            current_stock REAL NOT NULL DEFAULT 0,
            opening_stock REAL NOT NULL DEFAULT 0,
            reorder_level REAL NOT NULL DEFAULT 0,
            qty_needed REAL NOT NULL DEFAULT 1,
            category_id INTEGER,
            unit_id INTEGER,
            created_at TEXT NOT NULL,
            location_id INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE combos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            price REAL NOT NULL DEFAULT 0,
            selling_price REAL NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1,
            location_id INTEGER,
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
          'name': 'Tea Loc A',
          'sub_item': 'Tea Loc A',
          'category_id': 1,
          'location_id': 1,
          'created_at': now,
        });
        await db.insert('location_stock', {
          'location_id': 1,
          'raw_material_id': 1,
          'current_stock': 1,
          'opening_stock': 1,
        });
        await db.insert('raw_materials', {
          'name': 'Tea Loc B',
          'sub_item': 'Tea Loc B',
          'category_id': 1,
          'location_id': 2,
          'created_at': now,
        });
        await db.insert('location_stock', {
          'location_id': 2,
          'raw_material_id': 2,
          'current_stock': 1,
          'opening_stock': 1,
        });
        await db.insert('combos', {
          'name': 'Combo A',
          'price': 99,
          'selling_price': 99,
          'location_id': 1,
          'created_at': now,
        });
        await db.insert('combos', {
          'name': 'Combo B',
          'price': 88,
          'selling_price': 88,
          'location_id': 2,
          'created_at': now,
        });
      },
    );

    Repository.instance.setAppDbForTesting(SqliteAppDb(database));
    Repository.instance.bindSession(
      role: 'location',
      locationId: 1,
      locationName: 'Shop A',
    );

    final service = ItemImportService();
    final menuRows = await service.gridExportRowsForLocation(1);
    expect(menuRows.map((row) => row[2]), contains('Tea Loc A'));
    expect(menuRows.map((row) => row[2]), isNot(contains('Tea Loc B')));

    final comboRows = await service.comboExportRows();
    expect(
      comboRows.map((row) => row[0]),
      anyElement(contains('Combo A')),
    );
    expect(
      comboRows.map((row) => row[0]),
      isNot(anyElement(contains('Combo B'))),
    );

    Repository.instance.setAppDbForTesting(null);
    await database.close();
  });
}
