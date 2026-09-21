import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

int _importTestDbCounter = 0;

/// Opens an in-memory database with the schema required by menu import tests
/// and post-import catalog maintenance.
Future<Database> openImportTestDatabase() async {
  final path =
      'file:import_test_${_importTestDbCounter++}?mode=memory&cache=private';
  return openDatabase(
    path,
    version: 1,
    onCreate: (db, version) async {
      final now = DateTime.now().toIso8601String();
      await db.execute('''
        CREATE TABLE locations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          created_at TEXT NOT NULL
        )
      ''');
      await db.insert('locations', {
        'name': 'Gt world mall',
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
          location_id INTEGER,
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
          UNIQUE(location_id, raw_material_id),
          FOREIGN KEY (raw_material_id)
            REFERENCES raw_materials (id)
            ON DELETE CASCADE
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

      await db.execute('''
        CREATE TABLE purchase_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          raw_material_id INTEGER
        )
      ''');

      await db.execute('''
        CREATE TABLE sale_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          raw_material_id INTEGER
        )
      ''');

      await db.execute('''
        CREATE TABLE inventory_save_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          operation TEXT NOT NULL,
          raw_material_id INTEGER,
          success INTEGER NOT NULL DEFAULT 1,
          error_message TEXT,
          created_at TEXT NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE menu_import_batches (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          location_id INTEGER,
          content_fingerprint TEXT NOT NULL,
          completed_at TEXT NOT NULL,
          UNIQUE(location_id, content_fingerprint)
        )
      ''');
    },
  );
}

void bindImportTestSession(Database database) {
  Repository.instance.setAppDbForTesting(SqliteAppDb(database));
  Repository.remoteMenuExportMetadataSupported = true;
  Repository.instance.bindSession(
    role: 'location',
    locationId: 1,
    locationName: 'Gt world mall',
  );
}

Future<void> tearDownImportTestSession(Database database) async {
  Repository.instance.setAppDbForTesting(null);
  Repository.remoteMenuExportMetadataSupported = false;
  Repository.instance.bindSession(role: 'admin');
  await database.close();
}
