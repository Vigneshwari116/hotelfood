import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/repository.dart';
import 'package:foodstock/services/variant_helpers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('withEffectiveStock follows stock_source_id for display', () {
    final holder = RawMaterial(
      id: 1,
      name: 'Chicken Fingers',
      subItem: 'chicken finger',
      currentStock: 42,
    );
    final variant = RawMaterial(
      id: 2,
      name: 'Chicken roll',
      subItem: 'chicken finger',
      stockSourceId: 1,
      currentStock: 0,
    );

    final display = VariantHelpers.withEffectiveStock([holder, variant]);
    final roll = display.firstWhere((item) => item.id == 2);
    expect(roll.currentStock, 42);
  });

  test('recordPurchase credits pooled stock holder', () async {
    final database = await openDatabase(
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
        await db.insert('locations', {
          'name': 'Test',
          'created_at': DateTime.now().toIso8601String(),
        });
        await db.execute('''
          CREATE TABLE raw_materials (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            sub_item TEXT,
            qty_needed REAL NOT NULL DEFAULT 1,
            unit_id INTEGER,
            opening_stock REAL NOT NULL DEFAULT 0,
            current_stock REAL NOT NULL DEFAULT 0,
            reorder_level REAL NOT NULL DEFAULT 0,
            stock_source_id INTEGER,
            cost_price REAL,
            listed INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL
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
          CREATE TABLE purchases (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            supplier_id INTEGER,
            invoice_no TEXT,
            purchase_date TEXT NOT NULL,
            total_amount REAL NOT NULL,
            notes TEXT,
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
            amount REAL NOT NULL,
            expiry_date TEXT
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

        final now = DateTime.now().toIso8601String();
        await db.insert('raw_materials', {
          'name': 'Chicken Fingers',
          'sub_item': 'chicken finger',
          'current_stock': 0,
          'opening_stock': 0,
          'created_at': now,
        });
        await db.insert('raw_materials', {
          'name': 'Chicken roll',
          'sub_item': 'chicken finger',
          'stock_source_id': 1,
          'current_stock': 0,
          'opening_stock': 0,
          'created_at': now,
        });
        await db.insert('location_stock', {
          'location_id': 1,
          'raw_material_id': 1,
          'current_stock': 0,
          'opening_stock': 0,
          'reorder_level': 0,
        });
        await db.insert('location_stock', {
          'location_id': 1,
          'raw_material_id': 2,
          'current_stock': 0,
          'opening_stock': 0,
          'reorder_level': 0,
        });
      },
    );

    Repository.instance.setAppDbForTesting(SqliteAppDb(database));
    Repository.instance.bindSession(
      role: 'location',
      locationId: 1,
      locationName: 'Test',
    );

    await Repository.instance.recordPurchase(
      date: DateTime.now(),
      lines: [
        {
          'raw_material_id': 2,
          'qty': 10,
          'rate': 5,
        },
      ],
    );

    final holder = await Repository.instance.rawMaterialById(1);
    final variant = await Repository.instance.rawMaterialById(2);
    expect(holder!.currentStock, 10);
    expect(variant!.currentStock, 10);

    final display = await Repository.instance.rawMaterialsForDisplay(
      includeHidden: true,
    );
    final roll = display.firstWhere((item) => item.id == 2);
    expect(roll.currentStock, 10);

    await database.close();
    Repository.instance.setAppDbForTesting(null);
    Repository.instance.bindSession(role: 'admin');
  });
}
