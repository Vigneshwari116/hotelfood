import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/category_cleanup.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Reproduces catalog dedup unlisting (same class of bug as duplicate Crunchy Masala rows).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('dedupeDuplicateItemNamesInCategory unlists with traced source', () async {
    final database = await openDatabase(
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
            listed INTEGER NOT NULL DEFAULT 1,
            current_stock REAL NOT NULL DEFAULT 0,
            opening_stock REAL NOT NULL DEFAULT 0,
            units_per_packet REAL,
            variant_group TEXT,
            variant_label TEXT,
            created_at TEXT NOT NULL
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
        await db.insert('categories', {
          'name': 'Buckets',
          'type': 'raw_material',
        });
        final now = DateTime.now().toIso8601String();
        await db.insert('raw_materials', {
          'name': 'Crunchy Masala Big Bucket',
          'sub_item': 'Crunchy Masala',
          'category_id': 1,
          'listed': 1,
          'current_stock': 5,
          'opening_stock': 5,
          'created_at': now,
        });
        await db.insert('raw_materials', {
          'name': 'Crunchy Masala Big Bucket',
          'sub_item': 'Crunchy Masala Mini',
          'category_id': 1,
          'listed': 1,
          'current_stock': 0,
          'opening_stock': 0,
          'created_at': now,
        });
      },
    );

    Repository.instance.setAppDbForTesting(SqliteAppDb(database));
    Repository.instance.bindSession(role: 'admin');

    final hidden = await dedupeDuplicateItemNamesInCategory(SqliteAppDb(database));
    expect(hidden, 1);

    final logs = await database.query('inventory_save_log');
    expect(
      logs.any(
        (row) =>
            (row['operation'] as String?)
                ?.contains('import_catalog_dedup_name') ==
            true,
      ),
      isTrue,
    );

    Repository.instance.setAppDbForTesting(null);
    await database.close();
  });
}
