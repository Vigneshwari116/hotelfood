import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/sub_item_stock.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SubItemStock helpers', () {
    test('normalizes group keys case-insensitively', () {
      expect(
        SubItemStock.normalizeGroupKey(' Chicken Popcorn '),
        SubItemStock.normalizeGroupKey('chicken popcorn'),
      );
    });

    test('resolveCanonicalLabel reuses existing spelling', () {
      expect(
        SubItemStock.resolveCanonicalLabel(
          'chicken popcorn',
          const ['Chicken Popcorn'],
        ),
        'Chicken Popcorn',
      );
    });

    test('distinctGroupLabels dedupes case variants', () {
      expect(
        SubItemStock.distinctGroupLabels(const [
          'Chicken Popcorn',
          'chicken popcorn',
          'Masala Fries',
        ]),
        ['Chicken Popcorn', 'Masala Fries'],
      );
    });

    test('resolveCanonicalStockHolderId pools duplicate paratha rows', () {
      final stockParatha = RawMaterial(
        id: 1,
        name: 'Paratha',
        subItem: 'Paratha',
        categoryId: 10,
      );
      final comboParatha = RawMaterial(
        id: 2,
        name: 'Paratha',
        subItem: 'Paratha',
        categoryId: 20,
      );
      final byId = {
        1: stockParatha,
        2: comboParatha,
      };

      expect(
        SubItemStock.resolveCanonicalStockHolderId(comboParatha, byId),
        1,
      );
      expect(
        SubItemStock.resolveCanonicalStockHolderId(stockParatha, byId),
        1,
      );
    });
  });

  group('stock movement pooling', () {
    late Database database;

    setUp(() async {
      database = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              type TEXT NOT NULL DEFAULT 'raw_material'
            )
          ''');
          await db.execute('''
            CREATE TABLE units (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              short_code TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE raw_materials (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              sub_item TEXT,
              qty_needed REAL NOT NULL DEFAULT 1,
              category_id INTEGER,
              unit_id INTEGER,
              opening_stock REAL NOT NULL DEFAULT 0,
              current_stock REAL NOT NULL DEFAULT 0,
              cost_price REAL,
              selling_price REAL,
              listed INTEGER NOT NULL DEFAULT 1,
              menu_sort_order INTEGER,
              variant_group TEXT,
              variant_label TEXT,
              stock_source_id INTEGER,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE stock_ledger (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              raw_material_id INTEGER NOT NULL,
              entry_date TEXT NOT NULL,
              ref_type TEXT NOT NULL,
              ref_id INTEGER,
              qty_in REAL NOT NULL DEFAULT 0,
              qty_out REAL NOT NULL DEFAULT 0,
              unit_cost REAL,
              balance_after REAL NOT NULL,
              location_id INTEGER
            )
          ''');

          await db.insert('categories', {'name': 'Snacks', 'type': 'raw_material'});
          await db.insert('units', {'name': 'Gram', 'short_code': 'g'});
          await db.insert('raw_materials', {
            'name': 'Chicken Popcorn',
            'sub_item': 'Chicken Popcorn',
            'category_id': 1,
            'unit_id': 1,
            'opening_stock': 550,
            'current_stock': 550,
            'listed': 1,
            'created_at': '2026-09-16T00:00:00.000',
          });
          await db.insert('raw_materials', {
            'name': 'Chicken popcorn large',
            'sub_item': 'chicken popcorn',
            'category_id': 1,
            'unit_id': 1,
            'opening_stock': 0,
            'current_stock': 0,
            'listed': 1,
            'created_at': '2026-09-16T00:00:00.000',
          });
        },
      );

      Repository.instance.setAppDbForTesting(SqliteAppDb(database));
      Repository.instance.bindSession(role: 'admin');
    });

    tearDown(() async {
      Repository.instance.setAppDbForTesting(null);
      Repository.instance.clearSession();
      await database.close();
    });

    test('collapses rows that share a stock pool', () async {
      await Repository.instance.normalizeSubItemGroupLabels();

      final rows = await Repository.instance.stockMovementReport(
        from: DateTime(2026, 9, 16),
        to: DateTime(2026, 9, 16),
      );
      final popcornRows = rows.where(
        (row) =>
            (row['sub_item']?.toString().toLowerCase() ?? '').contains('popcorn'),
      );

      expect(popcornRows.length, 1);
    });
  });
}
