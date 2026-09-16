import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/category_cleanup.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
      await database.close();
    });

    test('merges Others into Uncategorized and hides duplicate rows', () async {
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
      await database.close();
    });

    test('hides duplicate rows with same category and item key', () async {
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
}
