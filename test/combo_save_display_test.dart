import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/combo_catalog_sync.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('combo save and display', () {
    late Database database;
    late SqliteAppDb appDb;

    setUp(() async {
      database = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          final now = DateTime.now().toIso8601String();
          await db.execute('''
            CREATE TABLE categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              type TEXT NOT NULL DEFAULT 'raw_material'
            )
          ''');
          await db.insert('categories', {
            'name': 'Burgers',
            'type': 'raw_material',
          });
          await db.insert('categories', {
            'name': 'Rolls',
            'type': 'raw_material',
          });
          await db.insert('categories', {
            'name': 'Fried Items',
            'type': 'raw_material',
          });
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
            CREATE TABLE units (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              short_code TEXT NOT NULL
            )
          ''');
          await db.insert('units', {
            'name': 'Piece',
            'short_code': 'pc',
          });
          await db.execute('''
            CREATE TABLE raw_materials (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              sub_item TEXT,
              qty_needed REAL NOT NULL DEFAULT 1,
              category_id INTEGER,
              menu_sort_order INTEGER,
              stock_source_id INTEGER,
              unit_id INTEGER,
              listed INTEGER NOT NULL DEFAULT 1,
              current_stock REAL NOT NULL DEFAULT 0,
              opening_stock REAL NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            )
          ''');
          await db.insert('raw_materials', {
            'id': 1,
            'name': 'Big juicy burger',
            'sub_item': 'Hot Crispy Patty',
            'qty_needed': 1,
            'category_id': 1,
            'listed': 1,
            'created_at': now,
          });
          await db.insert('raw_materials', {
            'id': 2,
            'name': 'Hot Crispy Patty',
            'sub_item': 'Hot Crispy Patty',
            'qty_needed': 1,
            'category_id': 1,
            'listed': 0,
            'created_at': now,
          });
          await db.insert('raw_materials', {
            'id': 3,
            'name': 'Burger Bun With Sesame',
            'sub_item': 'Burger Bun With Sesame',
            'qty_needed': 1,
            'category_id': 3,
            'listed': 0,
            'created_at': now,
          });
          await db.insert('raw_materials', {
            'id': 4,
            'name': 'Chicken roll',
            'sub_item': 'spicy fingers',
            'qty_needed': 2,
            'category_id': 2,
            'listed': 1,
            'created_at': now,
          });
          await db.insert('raw_materials', {
            'id': 5,
            'name': 'spicy fingers',
            'sub_item': 'spicy fingers',
            'qty_needed': 1,
            'category_id': 2,
            'listed': 0,
            'created_at': now,
          });
        },
      );

      appDb = SqliteAppDb(database);
      Repository.instance.setAppDbForTesting(appDb);
    });

    tearDown(() async {
      Repository.instance.setAppDbForTesting(null);
      await database.close();
    });

    test('saveCombo keeps the selected ingredient id instead of remapping', () async {
      final comboId = await Repository.instance.saveCombo(
        Combo(
          name: 'Big juicy burger',
          categoryId: 1,
          price: 129,
        ),
        [
          ComboRawMaterial(comboId: 0, rawMaterialId: 2, qty: 5),
          ComboRawMaterial(comboId: 0, rawMaterialId: 3, qty: 1),
        ],
      );

      final items = await Repository.instance.comboItems(comboId);

      expect(items, hasLength(2));
      final patty = items.firstWhere((item) => item.rawMaterialId == 2);
      final bun = items.firstWhere((item) => item.rawMaterialId == 3);
      expect(patty.materialName, 'Hot Crispy Patty');
      expect(patty.qty, 5);
      expect(bun.materialName, 'Burger Bun With Sesame');
      expect(bun.qty, 1);
    });

    test('syncBurgerRollCombos does not replace manually saved combo items', () async {
      final comboId = await Repository.instance.saveCombo(
        Combo(
          name: 'Big juicy burger',
          categoryId: 1,
          price: 129,
        ),
        [
          ComboRawMaterial(comboId: 0, rawMaterialId: 2, qty: 5),
          ComboRawMaterial(comboId: 0, rawMaterialId: 3, qty: 1),
        ],
      );

      await syncBurgerRollCombos(appDb);

      final items = await Repository.instance.comboItems(comboId);
      expect(items, hasLength(2));
      expect(items.map((item) => item.rawMaterialId).toSet(), {2, 3});
      expect(
        items.firstWhere((item) => item.rawMaterialId == 2).qty,
        5,
      );
      expect(
        items.firstWhere((item) => item.rawMaterialId == 3).qty,
        1,
      );
    });

    test('saveCombo stores the exact selected raw material id', () async {
      final comboId = await Repository.instance.saveCombo(
        Combo(
          name: 'Big juicy burger',
          categoryId: 1,
          price: 129,
        ),
        [
          ComboRawMaterial(comboId: 0, rawMaterialId: 1, qty: 5),
        ],
      );

      final items = await Repository.instance.comboItems(comboId);
      expect(items, hasLength(1));
      expect(items.first.rawMaterialId, 1);
      expect(items.first.materialName, 'Big juicy burger');
      expect(items.first.qty, 5);
    });

    test('combo export groups by combo and writes every item name', () async {
      await Repository.instance.saveCombo(
        Combo(
          name: 'Big juicy burger',
          categoryId: 1,
          price: 129,
        ),
        [
          ComboRawMaterial(comboId: 0, rawMaterialId: 2, qty: 5),
          ComboRawMaterial(comboId: 0, rawMaterialId: 3, qty: 1),
        ],
      );

      final comboRows = await ItemImportService().comboExportRows();
      expect(comboRows, hasLength(3));
      expect(comboRows[0][0], 'Big juicy burger — ₹129 (Burgers)');
      final itemNames = comboRows.skip(1).map((row) => row[1]).toList();
      expect(itemNames, containsAll(['Hot Crispy Patty', 'Burger Bun With Sesame']));
      final pattyRow = comboRows.firstWhere((row) => row[1] == 'Hot Crispy Patty');
      final bunRow = comboRows.firstWhere((row) => row[1] == 'Burger Bun With Sesame');
      expect(pattyRow[2], '5');
      expect(bunRow[2], '1');
    });

    test('combo export rows keep saved component names and qty', () async {
      await Repository.instance.saveCombo(
        Combo(
          name: 'Chicken roll',
          categoryId: 2,
          price: 75,
        ),
        [
          ComboRawMaterial(comboId: 0, rawMaterialId: 5, qty: 2),
        ],
      );

      final comboRows = await ItemImportService().comboExportRows();
      expect(comboRows, hasLength(2));
      expect(comboRows[0][0], 'Chicken roll — ₹75 (Rolls)');
      expect(comboRows[1][1], 'spicy fingers');
      expect(comboRows[1][2], '2');
      expect(comboRows[1][4], '0');
      expect(comboRows[1][5], '0');
    });
  });
}
