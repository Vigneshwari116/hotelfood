import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/category_cleanup.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _bindRepositoryForCategoryTests(Database database) async {
  await database.execute('''
    CREATE TABLE IF NOT EXISTS inventory_save_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      operation TEXT NOT NULL,
      raw_material_id INTEGER,
      success INTEGER NOT NULL DEFAULT 1,
      error_message TEXT,
      created_at TEXT NOT NULL
    )
  ''');
  Repository.instance.setAppDbForTesting(SqliteAppDb(database));
  Repository.instance.bindSession(role: 'admin');
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('mergeOthersCategoryIntoUncategorized', () {
    late Database database;

    setUp(() async {
      database = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                type TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE raw_materials (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                sub_item TEXT,
                category_id INTEGER,
                listed INTEGER NOT NULL DEFAULT 1,
                opening_stock REAL NOT NULL DEFAULT 0,
                current_stock REAL NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
              )
            ''');

            await db.insert('categories', {
              'name': 'Others',
              'type': 'raw_material',
            });
            await db.insert('categories', {
              'name': 'Uncategorized',
              'type': 'raw_material',
            });
            await db.insert('raw_materials', {
              'name': 'cool drinks glass',
              'sub_item': 'cool drinks',
              'category_id': null,
              'listed': 1,
              'created_at': '2026-01-01T00:00:00.000',
            });
            await db.insert('raw_materials', {
              'name': 'cool drinks glass',
              'sub_item': 'cool drinks',
              'category_id': 1,
              'listed': 1,
              'created_at': '2026-01-01T00:00:00.000',
            });
            await db.insert('raw_materials', {
              'name': 'water 1/2 liter',
              'sub_item': 'water 1/2 liter',
              'category_id': 2,
              'listed': 1,
              'created_at': '2026-01-01T00:00:00.000',
            });
          },
        ),
      );
    });

    tearDown(() async {
      Repository.instance.setAppDbForTesting(null);
      await database.close();
    });

    test('merges Others into Uncategorized and hides duplicate rows', () async {
      await _bindRepositoryForCategoryTests(database);
      final removed =
          await mergeOthersCategoryIntoUncategorized(SqliteAppDb(database));

      expect(removed, 1);

      final categories = await database.query('categories');
      expect(categories, hasLength(1));
      expect(categories.single['name'], 'Uncategorized');

      final listedRows = await database.query(
        'raw_materials',
        where: 'listed = 1',
      );
      expect(listedRows, hasLength(2));

      final keys = listedRows
          .map(
            (row) => (row['sub_item'] ?? row['name']).toString().toLowerCase(),
          )
          .toList();
      expect(keys.where((key) => key.contains('cool drinks')).length, 1);
    });
  });

  group('displayCategoryName', () {
    test('maps Others aliases to Uncategorized', () {
      expect(ItemImportService.displayCategoryName('Others'), 'Uncategorized');
      expect(ItemImportService.displayCategoryName('OTHERS'), 'Uncategorized');
      expect(ItemImportService.displayCategoryName('Snacks'), 'Snacks');
    });
  });

  group('dedupeDuplicateRowsInCategory', () {
    late Database database;

    setUp(() async {
      database = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                type TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE raw_materials (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                sub_item TEXT,
                category_id INTEGER,
                listed INTEGER NOT NULL DEFAULT 1,
                opening_stock REAL NOT NULL DEFAULT 0,
                opening_pieces REAL NOT NULL DEFAULT 0,
                current_stock REAL NOT NULL DEFAULT 0,
                units_per_packet REAL,
                variant_group TEXT,
                variant_label TEXT,
                qty_needed REAL NOT NULL DEFAULT 1,
                selling_price REAL,
                created_at TEXT NOT NULL
              )
            ''');
            await db.insert('categories', {
              'id': 1,
              'name': 'Burgers',
              'type': 'raw_material',
            });
            await db.insert('raw_materials', {
              'name': 'Hot Crispy Patty',
              'sub_item': 'Hot Crispy Patty',
              'category_id': 1,
              'listed': 1,
              'created_at': '2026-01-01T00:00:00.000',
            });
            await db.insert('raw_materials', {
              'name': 'Hot Crispy Patty',
              'sub_item': 'Hot Crispy Patty',
              'category_id': 1,
              'listed': 1,
              'created_at': '2026-01-01T00:00:00.000',
            });
          },
        ),
      );
    });

    tearDown(() async {
      Repository.instance.setAppDbForTesting(null);
      await database.close();
    });

    test('hides duplicate rows with same category and item key', () async {
      await _bindRepositoryForCategoryTests(database);
      final hidden = await dedupeDuplicateRowsInCategory(SqliteAppDb(database));
      expect(hidden, 1);

      final listedRows = await database.query(
        'raw_materials',
        where: 'listed = 1',
      );
      expect(listedRows, hasLength(1));
      expect(listedRows.single['name'], 'Hot Crispy Patty');
    });
  });

  group('mergeGlobalStockDuplicateRows', () {
    late Database database;

    setUp(() async {
      database = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                type TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE raw_materials (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                sub_item TEXT,
                category_id INTEGER,
                listed INTEGER NOT NULL DEFAULT 1,
                opening_stock REAL NOT NULL DEFAULT 0,
                current_stock REAL NOT NULL DEFAULT 0,
                units_per_packet REAL,
                variant_group TEXT,
                variant_label TEXT,
                menu_sort_order INTEGER,
                stock_source_id INTEGER,
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
            await db.execute('''
              CREATE TABLE location_stock (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                location_id INTEGER NOT NULL,
                raw_material_id INTEGER NOT NULL,
                current_stock REAL NOT NULL DEFAULT 0,
                opening_stock REAL NOT NULL DEFAULT 0,
                reorder_level REAL NOT NULL DEFAULT 0,
                UNIQUE(location_id, raw_material_id)
              )
            ''');
            await db.execute('''
              CREATE TABLE stock_batches (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                raw_material_id INTEGER NOT NULL,
                qty_remaining REAL NOT NULL,
                created_at TEXT NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE stock_ledger (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                raw_material_id INTEGER NOT NULL,
                entry_date TEXT NOT NULL,
                ref_type TEXT NOT NULL,
                qty_in REAL NOT NULL DEFAULT 0,
                qty_out REAL NOT NULL DEFAULT 0,
                balance_after REAL NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE purchase_items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                purchase_id INTEGER NOT NULL,
                raw_material_id INTEGER NOT NULL,
                qty REAL NOT NULL,
                rate REAL NOT NULL,
                amount REAL NOT NULL
              )
            ''');

            await db.insert('categories', {
              'id': 1,
              'name': 'Burgers',
              'type': 'raw_material',
            });
            await db.insert('categories', {
              'id': 2,
              'name': 'Rolls',
              'type': 'raw_material',
            });
            await db.insert('categories', {
              'id': 3,
              'name': 'snacks',
              'type': 'raw_material',
            });

            await db.insert('raw_materials', {
              'name': 'Hot Crispy Patty',
              'sub_item': 'Hot Crispy Patty',
              'category_id': 1,
              'listed': 1,
              'current_stock': -10,
              'created_at': '2026-01-01T00:00:00.000',
            });
            await db.insert('raw_materials', {
              'name': 'Hot Crispy Patty',
              'sub_item': 'Hot Crispy Patty',
              'category_id': 1,
              'listed': 1,
              'current_stock': -10,
              'created_at': '2026-01-01T00:00:00.000',
            });
            await db.insert('raw_materials', {
              'name': 'Paneer Patty',
              'sub_item': 'Paneer Patty',
              'category_id': 1,
              'listed': 1,
              'current_stock': 0,
              'created_at': '2026-01-01T00:00:00.000',
            });
            await db.insert('raw_materials', {
              'name': 'panner patty',
              'sub_item': 'panner patty',
              'category_id': 2,
              'listed': 1,
              'current_stock': 0,
              'created_at': '2026-01-01T00:00:00.000',
            });
            await db.insert('raw_materials', {
              'name': 'Veg Finger',
              'sub_item': 'veg finger',
              'category_id': 3,
              'listed': 1,
              'current_stock': 0,
              'created_at': '2026-01-01T00:00:00.000',
            });
            await db.insert('raw_materials', {
              'name': 'veg fingers',
              'sub_item': 'veg finger',
              'category_id': 2,
              'listed': 1,
              'current_stock': 0,
              'created_at': '2026-01-01T00:00:00.000',
            });
            await db.insert('combo_raw_materials', {
              'combo_id': 1,
              'raw_material_id': 4,
              'qty': 1,
            });
          },
        ),
      );
    });

    tearDown(() async {
      Repository.instance.setAppDbForTesting(null);
      await database.close();
    });

    test('merges duplicate patties and veg finger rows across categories', () async {
      await _bindRepositoryForCategoryTests(database);
      final merged = await mergeGlobalStockDuplicateRows(SqliteAppDb(database));
      expect(merged, greaterThanOrEqualTo(3));

      final listedPattyRows = await database.query(
        'raw_materials',
        where: "listed = 1 AND lower(name) LIKE '%patty%'",
      );
      expect(listedPattyRows.length, lessThanOrEqualTo(2));

      final listedFingerRows = await database.query(
        'raw_materials',
        where: "listed = 1 AND lower(name) LIKE '%finger%'",
      );
      expect(listedFingerRows, hasLength(1));

      final comboRows = await database.query('combo_raw_materials');
      expect(
        comboRows.every((row) => row['raw_material_id'] != 4),
        isTrue,
      );
    });
  });
}
