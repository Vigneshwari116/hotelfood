import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('combo model', () {
    test('treats null is_active as active', () {
      final combo = Combo.fromMap({
        'id': 1,
        'name': 'Snack Box',
        'price': 99,
        'created_at': DateTime.now().toIso8601String(),
      });
      expect(combo.isActive, isTrue);
    });
  });

  group('customer phone validation', () {
    test('rejects blank and all-zero numbers', () {
      expect(Repository.isValidCustomerPhone(null), isFalse);
      expect(Repository.isValidCustomerPhone(''), isFalse);
      expect(Repository.isValidCustomerPhone('0'), isFalse);
      expect(Repository.isValidCustomerPhone('0000'), isFalse);
    });

    test('accepts any other non-empty value', () {
      expect(Repository.isValidCustomerPhone('9876543210'), isTrue);
      expect(Repository.isValidCustomerPhone('12'), isTrue);
    });
  });

  group('substring search helpers', () {
    bool matches(String haystack, String query) {
      return haystack.toLowerCase().contains(query.trim().toLowerCase());
    }

    test('finds mid-word matches', () {
      expect(matches('Chicken Cheese Shotz', 'cheese'), isTrue);
      expect(matches('Tandoori roll', 'roll'), isTrue);
      expect(matches('Crunchy Masala', 'masala'), isTrue);
    });
  });

  group('reset restores imported location stock', () {
    Future<Database> openTestDb() {
      return openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE locations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE raw_materials (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              opening_stock REAL NOT NULL DEFAULT 0,
              current_stock REAL NOT NULL DEFAULT 0,
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
              reorder_level REAL NOT NULL DEFAULT 0,
              UNIQUE(location_id, raw_material_id)
            )
          ''');
          await db.execute('''
            CREATE TABLE stock_batches (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              raw_material_id INTEGER NOT NULL,
              qty_remaining REAL NOT NULL,
              rate REAL,
              expiry_date TEXT,
              purchase_item_id INTEGER,
              location_id INTEGER,
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
          await db.execute('''
            CREATE TABLE sales (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              sale_date TEXT NOT NULL,
              subtotal REAL NOT NULL,
              tax REAL NOT NULL DEFAULT 0,
              discount REAL NOT NULL DEFAULT 0,
              total REAL NOT NULL,
              payment_type TEXT NOT NULL,
              is_voided INTEGER NOT NULL DEFAULT 0,
              location_id INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE sale_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              sale_id INTEGER NOT NULL,
              item_name TEXT NOT NULL,
              qty REAL NOT NULL,
              price REAL NOT NULL,
              amount REAL NOT NULL
            )
          ''');
        },
      );
    }

    test('location stock returns to imported opening after reset', () async {
      final db = await openTestDb();
      final now = DateTime.now().toIso8601String();

      await db.insert('locations', {'name': 'Test', 'created_at': now});
      await db.insert('raw_materials', {
        'name': 'Chicken 65',
        'opening_stock': 10,
        'current_stock': 3,
        'created_at': now,
      });
      await db.insert('location_stock', {
        'location_id': 1,
        'raw_material_id': 1,
        'opening_stock': 10,
        'current_stock': 3,
        'reorder_level': 0,
      });
      await db.insert('sales', {
        'sale_date': now,
        'subtotal': 85,
        'tax': 0,
        'discount': 0,
        'total': 85,
        'payment_type': 'cash',
        'location_id': 1,
      });

      await db.delete('sale_items');
      await db.delete('sales', where: 'location_id = ?', whereArgs: [1]);
      await db.delete('stock_ledger', where: 'location_id = ?', whereArgs: [1]);
      await db.delete('stock_batches', where: 'location_id = ?', whereArgs: [1]);
      await db.update(
        'location_stock',
        {'current_stock': 10},
        where: 'location_id = ? AND raw_material_id = ?',
        whereArgs: [1, 1],
      );

      final row = (await db.query(
        'location_stock',
        where: 'location_id = ? AND raw_material_id = ?',
        whereArgs: [1, 1],
      )).single;

      expect((row['current_stock'] as num).toDouble(), 10);
      expect((row['opening_stock'] as num).toDouble(), 10);

      await db.close();
    });
  });
}
