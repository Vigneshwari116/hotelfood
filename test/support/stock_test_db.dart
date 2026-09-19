import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

int _stockTestDbCounter = 0;

/// Opens an isolated in-memory FFI database for stock integration tests.
Future<Database> openStockTestDatabase() async {
  final path = 'file:stock_test_${_stockTestDbCounter++}?mode=memory&cache=private';
  return openDatabase(
    path,
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
      await db.insert('locations', {
        'name': 'Test',
        'created_at': now,
      });

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
      await db.insert('units', {'name': 'Gram', 'short_code': 'g'});
      await db.insert('units', {'name': 'Piece', 'short_code': 'pc'});

      await db.execute('''
        CREATE TABLE raw_materials (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          barcode TEXT,
          name TEXT NOT NULL,
          sub_item TEXT,
          qty_needed REAL NOT NULL DEFAULT 1,
          category_id INTEGER,
          unit_id INTEGER,
          image_path TEXT,
          opening_stock REAL NOT NULL DEFAULT 0,
          opening_pieces REAL NOT NULL DEFAULT 0,
          current_stock REAL NOT NULL DEFAULT 0,
          reorder_level REAL NOT NULL DEFAULT 0,
          shelf_life_days INTEGER,
          units_per_packet REAL,
          entry_password_hash TEXT,
          cost_price REAL,
          selling_price REAL,
          listed INTEGER NOT NULL DEFAULT 1,
          menu_sort_order INTEGER,
          menu_export_row TEXT,
          variant_group TEXT,
          variant_label TEXT,
          stock_source_id INTEGER,
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
        CREATE TABLE stock_adjustments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          raw_material_id INTEGER NOT NULL,
          adjust_date TEXT NOT NULL,
          qty REAL NOT NULL,
          reason TEXT,
          location_id INTEGER
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
        CREATE TABLE sales (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER,
          customer_name TEXT,
          customer_phone TEXT,
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
          raw_material_id INTEGER,
          combo_id INTEGER,
          item_name TEXT NOT NULL,
          sub_item TEXT,
          qty REAL NOT NULL,
          price REAL NOT NULL,
          amount REAL NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE combos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          price REAL NOT NULL DEFAULT 0,
          selling_price REAL NOT NULL DEFAULT 0,
          is_active INTEGER NOT NULL DEFAULT 1,
          category_id INTEGER,
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
        CREATE TABLE pending_order_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          pending_order_id INTEGER NOT NULL,
          raw_material_id INTEGER,
          combo_id INTEGER,
          item_name TEXT NOT NULL,
          sub_item TEXT,
          component_labels TEXT,
          qty REAL NOT NULL,
          price REAL NOT NULL,
          amount REAL NOT NULL
        )
      ''');
    },
  );
}

void bindStockTestSession(Database database) {
  Repository.instance.setAppDbForTesting(SqliteAppDb(database));
  Repository.instance.bindSession(
    role: 'location',
    locationId: 1,
    locationName: 'Test',
  );
}

Future<void> tearDownStockTestSession(Database database) async {
  Repository.instance.setAppDbForTesting(null);
  Repository.instance.clearSession();
  await database.close();
}

Future<void> seedLocationStock(
  Database database,
  int rawMaterialId, {
  double stock = 0,
  double? openingStock,
}) async {
  await database.insert('location_stock', {
    'location_id': 1,
    'raw_material_id': rawMaterialId,
    'current_stock': stock,
    'opening_stock': openingStock ?? stock,
    'reorder_level': 0,
  });
}

Future<double> locationStock(Database database, int rawMaterialId) async {
  final rows = await database.query(
    'location_stock',
    columns: ['current_stock'],
    where: 'location_id = ? AND raw_material_id = ?',
    whereArgs: [1, rawMaterialId],
    limit: 1,
  );
  return (rows.first['current_stock'] as num).toDouble();
}
