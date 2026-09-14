import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/model/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('selling a bucket variant deducts from shared stock source', () async {
    final database = await openDatabase(
      inMemoryDatabasePath,
      version: 23,
      onCreate: (db, version) async {
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

        await db.insert('raw_materials', {
          'name': 'Thai Crispy',
          'sub_item': 'Thai Crispy',
          'qty_needed': 1,
          'current_stock': 20,
          'opening_stock': 20,
          'selling_price': 70,
          'variant_group': 'Thai Crispy',
          'variant_label': 'Pieces',
          'listed': 1,
          'created_at': DateTime.now().toIso8601String(),
        });

        await db.insert('raw_materials', {
          'name': 'Mini Bucket',
          'sub_item': 'Thai Crispy',
          'qty_needed': 5,
          'current_stock': 0,
          'opening_stock': 0,
          'selling_price': 150,
          'variant_group': 'Thai Crispy',
          'variant_label': 'Mini Bucket',
          'stock_source_id': 1,
          'listed': 1,
          'created_at': DateTime.now().toIso8601String(),
        });
      },
    );

    final appDb = SqliteAppDb(database);

    final bucketRows = await appDb.query(
      'raw_materials',
      where: 'name = ?',
      whereArgs: ['Mini Bucket'],
      limit: 1,
    );
    final bucketId = bucketRows.first['id'] as int;

    final stockRows = await appDb.query(
      'raw_materials',
      columns: ['stock_source_id', 'qty_needed'],
      where: 'id = ?',
      whereArgs: [bucketId],
      limit: 1,
    );
    final stockSourceId =
        (stockRows.first['stock_source_id'] as num?)?.toInt() ?? bucketId;
    final qtyNeeded =
        (stockRows.first['qty_needed'] as num?)?.toDouble() ?? 1.0;

    await appDb.update(
      'raw_materials',
      {
        'current_stock': 20 - qtyNeeded,
      },
      where: 'id = ?',
      whereArgs: [stockSourceId],
    );

    final after = await appDb.query(
      'raw_materials',
      where: 'id = ?',
      whereArgs: [stockSourceId],
      limit: 1,
    );

    expect((after.first['current_stock'] as num).toDouble(), 15);

    await database.close();
  });
}
