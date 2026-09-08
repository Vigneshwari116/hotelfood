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

  group('resetDemoTransactionData', () {
    late Database database;
    late SqliteAppDb appDb;
    var _dbCounter = 0;

    Future<void> openResetDb() async {
      _dbCounter++;
      final dbPath = '/tmp/foodstock_reset_test_$_dbCounter.db';
      await deleteDatabase(dbPath);
      database = await openDatabase(
        dbPath,
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('PRAGMA foreign_keys = ON');
          final now = DateTime.now().toIso8601String();
          await db.execute('''
            CREATE TABLE locations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              created_at TEXT NOT NULL
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
          await db.execute('''
            CREATE TABLE purchases (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              purchase_date TEXT NOT NULL,
              total_amount REAL NOT NULL DEFAULT 0,
              location_id INTEGER
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
          await db.execute('''
            CREATE TABLE stock_ledger (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              raw_material_id INTEGER NOT NULL,
              entry_date TEXT NOT NULL,
              ref_type TEXT NOT NULL,
              qty_in REAL NOT NULL DEFAULT 0,
              qty_out REAL NOT NULL DEFAULT 0,
              balance_after REAL NOT NULL,
              location_id INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE stock_adjustments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              raw_material_id INTEGER NOT NULL,
              adjust_date TEXT NOT NULL,
              qty REAL NOT NULL,
              location_id INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE stock_batches (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              raw_material_id INTEGER NOT NULL,
              qty_remaining REAL NOT NULL,
              created_at TEXT NOT NULL,
              location_id INTEGER
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
            CREATE TABLE pending_orders (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              token_number INTEGER NOT NULL,
              location_id INTEGER,
              tax REAL NOT NULL DEFAULT 0,
              discount REAL NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE pending_order_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              pending_order_id INTEGER NOT NULL,
              item_name TEXT NOT NULL,
              qty REAL NOT NULL,
              price REAL NOT NULL,
              amount REAL NOT NULL,
              FOREIGN KEY (pending_order_id)
                REFERENCES pending_orders (id)
                ON DELETE CASCADE
            )
          ''');

          await db.insert('locations', {'name': 'Location A', 'created_at': now});
          await db.insert('locations', {'name': 'Location B', 'created_at': now});
        },
      );

      appDb = SqliteAppDb(database);
      Repository.instance.setAppDbForTesting(appDb);
      Repository.instance.bindSession(
        role: 'staff',
        locationId: 1,
        locationName: 'Location A',
      );
    }

    tearDown(() async {
      Repository.instance.clearSession();
      Repository.instance.setAppDbForTesting(null);
      final dbPath = database.path;
      await database.close();
      await deleteDatabase(dbPath);
    });

    test('transaction delete removes pending orders by location', () async {
      await openResetDb();
      final now = DateTime.now().toIso8601String();
      await database.insert('pending_orders', {
        'token_number': 1,
        'location_id': 1,
        'tax': 0,
        'discount': 0,
        'created_at': now,
        'updated_at': now,
      });

      await appDb.transaction((txn) async {
        await txn.delete(
          'pending_orders',
          where: 'location_id = ?',
          whereArgs: [1],
        );
      });

      expect(await database.query('pending_orders'), isEmpty);
    });

    test('clears pending tokens for the reset location only', () async {
      await openResetDb();
      final now = DateTime.now().toIso8601String();

      final pendingA = await database.insert('pending_orders', {
        'token_number': 1,
        'location_id': 1,
        'tax': 0,
        'discount': 0,
        'created_at': now,
        'updated_at': now,
      });
      await database.insert('pending_order_items', {
        'pending_order_id': pendingA,
        'item_name': 'Mirchi bites',
        'qty': 8,
        'price': 10,
        'amount': 80,
      });

      final pendingB = await database.insert('pending_orders', {
        'token_number': 2,
        'location_id': 2,
        'tax': 0,
        'discount': 0,
        'created_at': now,
        'updated_at': now,
      });
      await database.insert('pending_order_items', {
        'pending_order_id': pendingB,
        'item_name': 'Other location token',
        'qty': 1,
        'price': 50,
        'amount': 50,
      });

      await Repository.instance.resetDemoTransactionData(locationId: 1);

      final remainingOrders = await appDb.query(
        'pending_orders',
        orderBy: 'id ASC',
      );
      expect(remainingOrders, hasLength(1));
      expect(remainingOrders.first['location_id'], 2);

      final remainingItems = await appDb.query('pending_order_items');
      expect(remainingItems, hasLength(1));
      expect(remainingItems.first['item_name'], 'Other location token');
    });

    test('clears all pending tokens when admin resets every location', () async {
      await openResetDb();
      Repository.instance.clearSession();
      Repository.instance.bindSession(role: 'admin');

      final now = DateTime.now().toIso8601String();
      final pendingA = await database.insert('pending_orders', {
        'token_number': 1,
        'location_id': 1,
        'tax': 0,
        'discount': 0,
        'created_at': now,
        'updated_at': now,
      });
      await database.insert('pending_order_items', {
        'pending_order_id': pendingA,
        'item_name': 'Token A',
        'qty': 2,
        'price': 10,
        'amount': 20,
      });

      final pendingB = await database.insert('pending_orders', {
        'token_number': 2,
        'location_id': 2,
        'tax': 0,
        'discount': 0,
        'created_at': now,
        'updated_at': now,
      });
      await database.insert('pending_order_items', {
        'pending_order_id': pendingB,
        'item_name': 'Token B',
        'qty': 3,
        'price': 10,
        'amount': 30,
      });

      await database.insert('pending_orders', {
        'token_number': 3,
        'location_id': null,
        'tax': 0,
        'discount': 0,
        'created_at': now,
        'updated_at': now,
      });

      await Repository.instance.resetDemoTransactionData();

      expect(await database.query('pending_orders'), isEmpty);
      expect(await database.query('pending_order_items'), isEmpty);
    });
  });
}
