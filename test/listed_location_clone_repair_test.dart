import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/listed_location_clone_repair.dart';
import 'package:foodstock/database/location_menu_scoping.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/stock_test_db.dart';

/// Mirrors [postgres_listed_material_dedup_v1] (no location_id in partition).
Future<void> applyLegacyGlobalListedDedup(DatabaseExecutor db) async {
  await db.rawUpdate('''
    WITH ranked AS (
      SELECT id,
        ROW_NUMBER() OVER (
          PARTITION BY category_id,
            lower(trim(name)),
            lower(trim(coalesce(nullif(trim(sub_item), ''), name)))
          ORDER BY
            listed DESC,
            abs(current_stock) DESC,
            CASE WHEN units_per_packet IS NOT NULL THEN 0 ELSE 1 END,
            id ASC
        ) AS rn
      FROM raw_materials
      WHERE listed = 1
    )
    UPDATE raw_materials SET listed = 0
    WHERE id IN (SELECT id FROM ranked WHERE rn > 1)
  ''');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('listed location clone repair', () {
    test('location migration copies listed flag to cloned rows', () async {
      final database = await openStockTestDatabase();
      final now = DateTime.now().toIso8601String();

      await database.insert('locations', {
        'name': 'Magadi road',
        'created_at': now,
      });

      await database.insert('raw_materials', {
        'name': 'Krusty Bites',
        'sub_item': 'chicken 65',
        'listed': 1,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Chicken 65',
        'sub_item': 'Chicken 65',
        'listed': 0,
        'created_at': now,
      });

      await migrateMenuCatalogToLocationScope(database);

      final clones = await database.query(
        'raw_materials',
        where: 'location_id = ?',
        whereArgs: [2],
        orderBy: 'name ASC',
      );
      expect(clones, hasLength(2));
      final krusty = clones.firstWhere((r) => r['name'] == 'Krusty Bites');
      final chicken = clones.firstWhere((r) => r['name'] == 'Chicken 65');
      expect(krusty['listed'], 1);
      expect(chicken['listed'], 0);

      await database.close();
    });

    test('repair restores listed after global dedup zeros clones', () async {
      final database = await openStockTestDatabase();
      final now = DateTime.now().toIso8601String();

      await database.insert('locations', {
        'name': 'Magadi road',
        'created_at': now,
      });
      await database.insert('locations', {
        'name': 'Subbanna garden',
        'created_at': now,
      });

      await database.insert('raw_materials', {
        'name': 'Tea',
        'sub_item': 'Tea',
        'listed': 1,
        'category_id': 1,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Coffee',
        'sub_item': 'Coffee',
        'listed': 0,
        'category_id': 1,
        'created_at': now,
      });

      await migrateMenuCatalogToLocationScope(database);
      await applyLegacyGlobalListedDedup(database);

      final loc2Before = await database.query(
        'raw_materials',
        where: 'location_id = ? AND listed = ?',
        whereArgs: [2, 1],
      );
      expect(loc2Before, isEmpty);

      final result = await migrateListedLocationCloneRepair(database);
      expect(result.materialRowsUpdated, greaterThan(0));
      expect(result.mismatchedListedAfter, 0);

      final loc1Listed = await database.query(
        'raw_materials',
        where: 'location_id = ?',
        whereArgs: [1],
        orderBy: 'name ASC',
      );
      final loc2Listed = await database.query(
        'raw_materials',
        where: 'location_id = ?',
        whereArgs: [2],
        orderBy: 'name ASC',
      );
      expect(
        loc2Listed.map((r) => r['listed']).toList(),
        loc1Listed.map((r) => r['listed']).toList(),
      );

      final second = await migrateListedLocationCloneRepair(database);
      expect(second.materialRowsUpdated, 0);

      await database.close();
    });
  });
}
