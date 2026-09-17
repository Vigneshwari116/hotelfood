import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('combo category assignment', () {
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
            'name': 'Rolls',
            'type': 'raw_material',
          });
          await db.insert('categories', {
            'name': 'Burgers',
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
            CREATE TABLE raw_materials (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              sub_item TEXT,
              qty_needed REAL NOT NULL DEFAULT 1,
              category_id INTEGER,
              menu_sort_order INTEGER,
              stock_source_id INTEGER,
              listed INTEGER NOT NULL DEFAULT 1,
              current_stock REAL NOT NULL DEFAULT 0,
              opening_stock REAL NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            )
          ''');
          await db.insert('raw_materials', {
            'name': 'KRISPER Roll',
            'sub_item': 'Krisper Roll',
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

    test('saveCombo persists category_id for POS grouping', () async {
      final comboId = await Repository.instance.saveCombo(
        Combo(
          name: 'KRISPER ROLL',
          categoryId: 1,
          price: 85,
        ),
        [
          ComboRawMaterial(
            comboId: 0,
            rawMaterialId: 1,
            qty: 1,
          ),
        ],
      );

      final saved = await Repository.instance.comboById(comboId);

      expect(saved?.categoryId, 1);
      expect(saved?.name, 'KRISPER ROLL');
    });

    test('uncategorized combos keep null category until edited', () async {
      await Repository.instance.saveCombo(
        Combo(
          name: 'Legacy combo',
          price: 60,
        ),
        [
          ComboRawMaterial(
            comboId: 0,
            rawMaterialId: 1,
            qty: 1,
          ),
        ],
      );

      final combos = await Repository.instance.combos();
      final legacy = combos.firstWhere((combo) => combo.name == 'Legacy combo');

      expect(legacy.categoryId, isNull);
    });

    test('saveCombo updates category on existing combo', () async {
      final comboId = await Repository.instance.saveCombo(
        Combo(
          name: 'Star burger combo',
          price: 210,
        ),
        [
          ComboRawMaterial(
            comboId: 0,
            rawMaterialId: 1,
            qty: 1,
          ),
        ],
      );

      await Repository.instance.saveCombo(
        Combo(
          id: comboId,
          name: 'Star burger combo',
          categoryId: 2,
          price: 210,
        ),
        [
          ComboRawMaterial(
            comboId: comboId,
            rawMaterialId: 1,
            qty: 1,
          ),
        ],
      );

      final saved = await Repository.instance.comboById(comboId);
      expect(saved?.categoryId, 2);
    });
  });
}
