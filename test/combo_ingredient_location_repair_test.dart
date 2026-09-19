import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/combo_ingredient_location_repair.dart';
import 'package:foodstock/database/location_menu_scoping.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/stock_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('combo ingredient location repair', () {
    test('remaps cloned-location combos that still reference location-1 ids', () async {
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
        'name': 'Burger Bun With Sesame',
        'sub_item': 'Burger Bun With Sesame',
        'barcode': 'BUN-1',
        'category_id': 1,
        'listed': 1,
        'created_at': now,
      });
      await database.insert('location_stock', {
        'location_id': 1,
        'raw_material_id': 1,
        'current_stock': 10,
        'opening_stock': 10,
        'reorder_level': 0,
      });
      await database.insert('location_stock', {
        'location_id': 2,
        'raw_material_id': 1,
        'current_stock': 5,
        'opening_stock': 5,
        'reorder_level': 0,
      });
      await database.insert('location_stock', {
        'location_id': 3,
        'raw_material_id': 1,
        'current_stock': 3,
        'opening_stock': 3,
        'reorder_level': 0,
      });

      await database.insert('raw_materials', {
        'name': 'Hot Crispy Patty',
        'sub_item': 'Hot Crispy Patty',
        'category_id': 1,
        'listed': 0,
        'created_at': now,
      });

      await database.insert('combos', {
        'name': 'Big juicy burger',
        'price': 129,
        'selling_price': 129,
        'is_active': 1,
        'created_at': now,
      });
      await database.insert('combo_raw_materials', {
        'combo_id': 1,
        'raw_material_id': 1,
        'qty': 1,
      });
      await database.insert('combo_raw_materials', {
        'combo_id': 1,
        'raw_material_id': 2,
        'qty': 1,
      });

      await migrateMenuCatalogToLocationScope(database);

      final loc1Bun = 1;
      final loc1Patty = 2;

      final loc2Combo = (await database.query(
        'combos',
        where: 'location_id = ?',
        whereArgs: [2],
      ))
          .single;
      final loc3Combo = (await database.query(
        'combos',
        where: 'location_id = ?',
        whereArgs: [3],
      ))
          .single;

      final loc2Materials = await database.query(
        'raw_materials',
        where: 'location_id = ?',
        whereArgs: [2],
        orderBy: 'id ASC',
      );
      final loc3Materials = await database.query(
        'raw_materials',
        where: 'location_id = ?',
        whereArgs: [3],
        orderBy: 'id ASC',
      );

      // Simulate PR #88 fallout: cloned combos still point at location-1 ids.
      Future<void> breakComboLinks(int comboId) async {
        final links = await database.query(
          'combo_raw_materials',
          where: 'combo_id = ?',
          whereArgs: [comboId],
          orderBy: 'id ASC',
        );
        expect(links.length, 2);
        await database.update(
          'combo_raw_materials',
          {'raw_material_id': loc1Bun},
          where: 'id = ?',
          whereArgs: [links[0]['id']],
        );
        await database.update(
          'combo_raw_materials',
          {'raw_material_id': loc1Patty},
          where: 'id = ?',
          whereArgs: [links[1]['id']],
        );
      }

      await breakComboLinks(loc2Combo['id'] as int);
      await breakComboLinks(loc3Combo['id'] as int);

      final brokenLinks = await countCrossLocationComboIngredientLinks(database);
      expect(brokenLinks, 4);

      final result = await migrateComboIngredientLocationRepair(database);
      expect(result.mismatchedBefore, 4);
      expect(result.linksUpdated, 4);
      expect(result.mismatchedAfter, 0);
      expect(result.isClean, isTrue);

      final loc2Links = await database.query(
        'combo_raw_materials',
        where: 'combo_id = ?',
        whereArgs: [loc2Combo['id']],
        orderBy: 'raw_material_id ASC',
      );
      expect(
        loc2Links.map((row) => row['raw_material_id']).toSet(),
        loc2Materials.map((row) => row['id']).toSet(),
      );

      final loc3Links = await database.query(
        'combo_raw_materials',
        where: 'combo_id = ?',
        whereArgs: [loc3Combo['id']],
        orderBy: 'raw_material_id ASC',
      );
      expect(
        loc3Links.map((row) => row['raw_material_id']).toSet(),
        loc3Materials.map((row) => row['id']).toSet(),
      );

      final secondPass = await migrateComboIngredientLocationRepair(database);
      expect(secondPass.linksUpdated, 0);
      expect(secondPass.mismatchedAfter, 0);

      await database.close();
    });

    test('location menu migration keeps combo ingredients on cloned materials', () async {
      final database = await openStockTestDatabase();
      final now = DateTime.now().toIso8601String();

      await database.insert('locations', {
        'name': 'Magadi road',
        'created_at': now,
      });

      await database.insert('raw_materials', {
        'name': 'Chicken 65',
        'sub_item': 'Chicken 65',
        'listed': 1,
        'created_at': now,
      });
      await database.insert('combos', {
        'name': 'Value meal',
        'price': 150,
        'selling_price': 150,
        'is_active': 1,
        'created_at': now,
      });
      await database.insert('combo_raw_materials', {
        'combo_id': 1,
        'raw_material_id': 1,
        'qty': 1,
      });

      await migrateMenuCatalogToLocationScope(database);

      expect(await countCrossLocationComboIngredientLinks(database), 0);

      await database.close();
    });
  });
}
