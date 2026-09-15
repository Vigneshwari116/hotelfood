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

  test('menu re-import preserves existing live stock', () async {
    final database = await openDatabase(
      inMemoryDatabasePath,
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
          CREATE TABLE combos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            price REAL NOT NULL DEFAULT 0,
            selling_price REAL NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1,
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
      },
    );

    Repository.instance.setAppDbForTesting(SqliteAppDb(database));
    Repository.instance.bindSession(
      role: 'location',
      locationId: 1,
      locationName: 'Gt world mall',
    );

    const seedCsv = '''
category,item_name,sub_item,barcode,qty_per_sale,packets,units_per_packet,unit,opening stock,cost_price,selling_price
SNACKS,Chicken 65,Chicken 65,,8,,90,pc,0,,85
''';

    final service = ItemImportService();
    final firstImport = await service.importCsvText(seedCsv);
    expect(firstImport.errors, isEmpty);

    final items = await Repository.instance.rawMaterials(includeHidden: true);
    expect(items, isNotEmpty);
    final chickenId = items.first.id!;

    await database.update(
      'location_stock',
      {'current_stock': 36, 'opening_stock': 10},
      where: 'location_id = ? AND raw_material_id = ?',
      whereArgs: [1, chickenId],
    );
    await database.update(
      'raw_materials',
      {'current_stock': 36, 'opening_stock': 10, 'selling_price': 99},
      where: 'id = ?',
      whereArgs: [chickenId],
    );

    await service.importCsvText(seedCsv, updateExisting: true);

    final row = await database.query(
      'location_stock',
      where: 'location_id = ? AND raw_material_id = ?',
      whereArgs: [1, chickenId],
    );
    expect((row.first['current_stock'] as num).toDouble(), 36);
    expect((row.first['opening_stock'] as num).toDouble(), 10);

    final item = await Repository.instance.rawMaterialById(chickenId);
    expect(item!.sellingPrice, 85);

    await database.close();
    Repository.instance.setAppDbForTesting(null);
    Repository.instance.bindSession(role: 'admin');
  });
}
