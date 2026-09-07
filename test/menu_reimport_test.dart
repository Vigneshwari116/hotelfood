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

  late Database database;
  late SqliteAppDb appDb;

  const seedMenuCsv = '''
category,item_name,sub_item,barcode,qty_per_sale,packets,units_per_packet,unit,opening stock,cost_price,selling_price
SNACKS,Chicken 65,Chicken 65,,1,,,pc,0,,85
SNACKS,French Fries,French Fries Small,,80,,,g,0,,50
''';

  Future<void> openImportDb() async {
    database = await openDatabase(
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
            balance_after REAL NOT NULL
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

    appDb = SqliteAppDb(database);
    Repository.instance.setAppDbForTesting(appDb);
    Repository.instance.bindSession(
      role: 'location',
      locationId: 1,
      locationName: 'Gt world mall',
    );
  }

  tearDown(() async {
    Repository.instance.setAppDbForTesting(null);
    Repository.instance.bindSession(role: 'admin');
    await database.close();
  });

  RawMaterial? findItem(List<RawMaterial> items, String name) {
    return items.cast<RawMaterial?>().firstWhere(
      (item) => item!.name == name,
      orElse: () => null,
    );
  }

  group('location menu re-import', () {
    test('re-import overwrites manual price edits with Excel values', () async {
      await openImportDb();
      final service = ItemImportService();

      await service.importCsvText(seedMenuCsv);

      final afterSeed = await Repository.instance.rawMaterials(includeHidden: true);
      final chicken65 = findItem(afterSeed, 'Chicken 65');
      expect(chicken65, isNotNull);
      expect(chicken65!.sellingPrice, 85);

      await Repository.instance.saveRawMaterial(
        RawMaterial(
          id: chicken65!.id,
          name: chicken65.name,
          subItem: chicken65.subItem,
          qtyNeeded: chicken65.qtyNeeded,
          categoryId: chicken65.categoryId,
          unitId: chicken65.unitId,
          openingStock: chicken65.openingStock,
          currentStock: chicken65.currentStock,
          sellingPrice: 99,
          listed: chicken65.listed,
          createdAt: chicken65.createdAt,
        ),
      );

      final afterManualEdit =
          await Repository.instance.rawMaterials(includeHidden: true);
      expect(findItem(afterManualEdit, 'Chicken 65')!.sellingPrice, 99);

      final reimport = await service.importCsvText(
        seedMenuCsv,
        updateExisting: true,
      );
      expect(reimport.updated, greaterThan(0));

      final afterReimport =
          await Repository.instance.rawMaterials(includeHidden: true);
      expect(
        findItem(afterReimport, 'Chicken 65')!.sellingPrice,
        85,
        reason: 'Location re-import updates matching rows from Excel',
      );
    });

    test('re-import does not delete items missing from the Excel file', () async {
      await openImportDb();
      final service = ItemImportService();

      await service.importCsvText(seedMenuCsv, updateExisting: true);

      final extraId = await Repository.instance.saveRawMaterial(
        RawMaterial(
          name: 'Staff Only Item',
          subItem: 'Staff Only Item',
          qtyNeeded: 1,
          openingStock: 0,
          currentStock: 0,
          sellingPrice: 25,
          listed: true,
        ),
      );
      expect(extraId, greaterThan(0));

      final before = await Repository.instance.rawMaterials(includeHidden: true);
      expect(before.any((item) => item.name == 'Staff Only Item'), isTrue);
      expect(before.length, 3);

      await service.importCsvText(
        seedMenuCsv,
        updateExisting: true,
      );

      final after = await Repository.instance.rawMaterials(includeHidden: true);
      expect(after.any((item) => item.name == 'Staff Only Item'), isTrue);
      expect(after.length, 3);
    });

    test('location importFile uses merge mode (replaceCatalog false)', () async {
      await openImportDb();
      final service = ItemImportService();

      await service.importCsvText(seedMenuCsv);
      await Repository.instance.saveRawMaterial(
        RawMaterial(
          name: 'Only In App',
          subItem: 'Only In App',
          qtyNeeded: 1,
          openingStock: 0,
          currentStock: 0,
          sellingPrice: 40,
        ),
      );

      final result = await service.importCsvText(
        seedMenuCsv,
        updateExisting: true,
        replaceCatalog: false,
      );

      final items = await Repository.instance.rawMaterials(includeHidden: true);
      expect(items.any((item) => item.name == 'Only In App'), isTrue);
      expect(result.updated, greaterThan(0));
    });

    test('replaceCatalog true hides leftovers when delete is blocked', () async {
      await openImportDb();
      final service = ItemImportService();

      await service.importCsvText(seedMenuCsv);
      await Repository.instance.saveRawMaterial(
        RawMaterial(
          name: 'Only In App',
          subItem: 'Only In App',
          qtyNeeded: 1,
          openingStock: 0,
          currentStock: 0,
          sellingPrice: 40,
        ),
      );

      await service.importCsvText(
        seedMenuCsv,
        updateExisting: true,
        replaceCatalog: true,
      );

      final items = await Repository.instance.rawMaterials(includeHidden: true);
      final orphan = items.where((item) => item.name == 'Only In App').toList();
      expect(orphan, hasLength(1));
      expect(
        orphan.first.listed,
        isFalse,
        reason: 'Leftover items are hidden when hard delete is not possible',
      );
      expect(items.where((item) => item.listed).length, 2);
    });
  });
}
