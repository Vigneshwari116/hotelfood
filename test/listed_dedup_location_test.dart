import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/category_cleanup.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('location-scoped listed dedup', () {
    late Database database;

    setUp(() async {
      database = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE raw_materials (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              sub_item TEXT,
              category_id INTEGER,
              location_id INTEGER,
              listed INTEGER NOT NULL DEFAULT 1,
              opening_stock REAL NOT NULL DEFAULT 0,
              current_stock REAL NOT NULL DEFAULT 0,
              units_per_packet REAL,
              variant_group TEXT,
              variant_label TEXT,
              created_at TEXT NOT NULL
            )
          ''');
          await db.insert('categories', {
            'id': 1,
            'name': 'Snacks',
            'type': 'raw_material',
          });
        },
      );
    });

    tearDown(() async {
      Repository.instance.setAppDbForTesting(null);
      await database.close();
    });

    Future<void> bindRepo() async {
      await database.execute('''
        CREATE TABLE IF NOT EXISTS inventory_save_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          operation TEXT NOT NULL,
          raw_material_id INTEGER,
          success INTEGER NOT NULL DEFAULT 1,
          error_message TEXT,
          created_at TEXT NOT NULL
        )
      ''');
      Repository.instance.setAppDbForTesting(SqliteAppDb(database));
      Repository.instance.bindSession(role: 'admin');
    }

    test('dedupeDuplicateRowsInCategory keeps listed=1 per location clone',
        () async {
      await bindRepo();
      final now = DateTime.now().toIso8601String();
      await database.insert('raw_materials', {
        'name': 'Chicken 65',
        'sub_item': 'chicken 65',
        'category_id': 1,
        'location_id': 1,
        'listed': 1,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Chicken 65',
        'sub_item': 'chicken 65',
        'category_id': 1,
        'location_id': 2,
        'listed': 1,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Chicken 65',
        'sub_item': 'chicken 65',
        'category_id': 1,
        'location_id': 3,
        'listed': 1,
        'created_at': now,
      });

      final hidden =
          await dedupeDuplicateRowsInCategory(SqliteAppDb(database));
      expect(hidden, 0);

      final listed = await database.query(
        'raw_materials',
        where: 'listed = 1',
      );
      expect(listed, hasLength(3));
    });

    test('dedupeDuplicateRowsInCategory still hides within one location',
        () async {
      await bindRepo();
      final now = DateTime.now().toIso8601String();
      await database.insert('raw_materials', {
        'name': 'Crunchy Masala',
        'sub_item': 'Crunchy Masala',
        'category_id': 1,
        'location_id': 2,
        'listed': 1,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Crunchy Masala',
        'sub_item': 'Crunchy Masala',
        'category_id': 1,
        'location_id': 2,
        'listed': 1,
        'created_at': now,
      });

      final hidden =
          await dedupeDuplicateRowsInCategory(SqliteAppDb(database));
      expect(hidden, 1);

      final listedAt2 = await database.query(
        'raw_materials',
        where: 'location_id = ? AND listed = 1',
        whereArgs: [2],
      );
      expect(listedAt2, hasLength(1));
    });
  });
}
