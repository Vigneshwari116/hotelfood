import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('stockMovementReport', () {
    late Database database;
    late SqliteAppDb appDb;

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
              barcode TEXT,
              name TEXT NOT NULL,
              sub_item TEXT,
              qty_needed REAL NOT NULL DEFAULT 1,
              category_id INTEGER,
              unit_id INTEGER,
              opening_stock REAL NOT NULL DEFAULT 0,
              current_stock REAL NOT NULL DEFAULT 0,
              reorder_level REAL NOT NULL DEFAULT 0,
              cost_price REAL,
              selling_price REAL,
              listed INTEGER NOT NULL DEFAULT 1,
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
          await db.insert('units', {'name': 'Piece', 'short_code': 'pc'});
          await db.insert('raw_materials', {
            'name': 'French Fries',
            'sub_item': 'French Fries',
            'category_id': 1,
            'unit_id': 1,
            'opening_stock': 100,
            'current_stock': 130,
            'cost_price': 2,
            'listed': 1,
            'created_at': '2026-09-01T00:00:00.000',
          });

          await db.insert('stock_ledger', {
            'raw_material_id': 1,
            'entry_date': '2026-09-01T08:00:00.000',
            'ref_type': 'opening',
            'qty_in': 100,
            'qty_out': 0,
            'unit_cost': 2,
            'balance_after': 100,
          });
          await db.insert('stock_ledger', {
            'raw_material_id': 1,
            'entry_date': '2026-09-10T10:00:00.000',
            'ref_type': 'purchase',
            'qty_in': 50,
            'qty_out': 0,
            'unit_cost': 2,
            'balance_after': 150,
          });
          await db.insert('stock_ledger', {
            'raw_material_id': 1,
            'entry_date': '2026-09-12T12:00:00.000',
            'ref_type': 'sale_deduction',
            'qty_in': 0,
            'qty_out': 20,
            'unit_cost': 2,
            'balance_after': 130,
          });
        },
      );

      appDb = SqliteAppDb(database);
      Repository.instance.setAppDbForTesting(appDb);
      Repository.instance.bindSession(role: 'admin');
    });

    tearDown(() async {
      Repository.instance.setAppDbForTesting(null);
      Repository.instance.clearSession();
      await database.close();
    });

    test('calculates opening, purchase, sales, and closing for a period', () async {
      final rows = await Repository.instance.stockMovementReport(
        from: DateTime(2026, 9, 10),
        to: DateTime(2026, 9, 12),
      );

      expect(rows.length, 1);
      final row = rows.first;
      expect(row['item_name'], 'French Fries');
      expect((row['opening_qty'] as num).toDouble(), 100);
      expect((row['purchase_qty'] as num).toDouble(), 50);
      expect((row['sales_qty'] as num).toDouble(), 20);
      expect((row['adjustment_qty'] as num).toDouble(), 0);
      expect((row['closing_qty'] as num).toDouble(), 130);
      expect((row['opening_value'] as num).toDouble(), 200);
      expect((row['closing_value'] as num).toDouble(), 260);
    });
  });
}
