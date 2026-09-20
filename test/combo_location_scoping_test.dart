import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/combo_material_picker.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/stock_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> seedSecondLocation(Database db) async {
    await db.insert('locations', {
      'name': 'Magadi road',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  void bindLocationTwo(Database database) {
    Repository.instance.setAppDbForTesting(SqliteAppDb(database));
    Repository.instance.bindSession(
      role: 'location',
      locationId: 2,
      locationName: 'Magadi road',
    );
  }

  group('combo ingredient location scoping', () {
    test('picker excludes ingredients from other locations', () {
      final materials = materialsForComboPicker(
        [
          RawMaterial(
            id: 2,
            name: 'Burger Bun With Sesame',
            subItem: 'Burger Bun',
            locationId: 1,
            listed: true,
          ),
          RawMaterial(
            id: 55,
            name: 'Big juciy burger',
            subItem: 'Hot Crispy Patty',
            locationId: 1,
            listed: true,
          ),
          RawMaterial(
            id: 795,
            name: 'Chicken 65',
            subItem: 'Chicken 65',
            locationId: 2,
            listed: true,
          ),
          RawMaterial(
            id: 820,
            name: 'Burger Bun With Sesame',
            subItem: 'Burger Bun',
            locationId: 2,
            listed: true,
          ),
        ],
        catalogLocationId: 2,
      );

      expect(materials.map((m) => m.id).toSet(), {795, 820});
      expect(materials.any((m) => m.id == 2 || m.id == 55), isFalse);
    });

    test('saveCombo stores location-local ids, not another shop canonical ids',
        () async {
      final database = await openStockTestDatabase();
      await seedSecondLocation(database);
      final now = DateTime.now().toIso8601String();

      final loc1Patty = await database.insert('raw_materials', {
        'name': 'Big juciy burger',
        'sub_item': 'Hot Crispy Patty',
        'location_id': 1,
        'listed': 1,
        'created_at': now,
      });
      await seedLocationStock(database, loc1Patty);

      final loc2Patty = await database.insert('raw_materials', {
        'name': 'Big juciy burger',
        'sub_item': 'Hot Crispy Patty',
        'location_id': 2,
        'listed': 1,
        'created_at': now,
      });
      await database.insert('location_stock', {
        'location_id': 2,
        'raw_material_id': loc2Patty,
        'current_stock': 10,
        'opening_stock': 10,
        'reorder_level': 0,
      });

      bindLocationTwo(database);

      final comboId = await Repository.instance.saveCombo(
        Combo(
          name: 'Combo test for magadi',
          price: 199,
          locationId: 2,
        ),
        [
          ComboRawMaterial(
            comboId: 0,
            rawMaterialId: loc2Patty,
            qty: 1,
          ),
        ],
      );

      final linkRows = await database.query(
        'combo_raw_materials',
        where: 'combo_id = ?',
        whereArgs: [comboId],
      );
      expect(linkRows, hasLength(1));
      expect(linkRows.first['raw_material_id'], loc2Patty);
      expect(linkRows.first['raw_material_id'], isNot(loc1Patty));

      await tearDownStockTestSession(database);
    });

    test('saveCombo rejects ingredients from another location', () async {
      final database = await openStockTestDatabase();
      await seedSecondLocation(database);
      final now = DateTime.now().toIso8601String();

      final loc1Patty = await database.insert('raw_materials', {
        'name': 'Big juciy burger',
        'sub_item': 'Hot Crispy Patty',
        'location_id': 1,
        'listed': 1,
        'created_at': now,
      });
      await seedLocationStock(database, loc1Patty);

      bindLocationTwo(database);

      await expectLater(
        Repository.instance.saveCombo(
          Combo(
            name: 'Bad cross-location combo',
            price: 150,
            locationId: 2,
          ),
          [
            ComboRawMaterial(
              comboId: 0,
              rawMaterialId: loc1Patty,
              qty: 1,
            ),
          ],
        ),
        throwsA(isA<InvalidInventoryException>()),
      );

      await tearDownStockTestSession(database);
    });

    test('saveCombo remaps cross-location pick to current location catalog id',
        () async {
      final database = await openStockTestDatabase();
      await seedSecondLocation(database);
      final now = DateTime.now().toIso8601String();

      final loc1Ingredient = await database.insert('raw_materials', {
        'name': 'Chicken 65',
        'sub_item': 'Chicken 65',
        'location_id': 1,
        'listed': 1,
        'created_at': now,
      });
      await seedLocationStock(database, loc1Ingredient);

      final loc2Ingredient = await database.insert('raw_materials', {
        'name': 'Chicken 65',
        'sub_item': 'Chicken 65',
        'location_id': 2,
        'listed': 1,
        'created_at': now,
      });
      await database.insert('location_stock', {
        'location_id': 2,
        'raw_material_id': loc2Ingredient,
        'current_stock': 10,
        'opening_stock': 10,
        'reorder_level': 0,
      });

      Repository.instance.setAppDbForTesting(SqliteAppDb(database));
      Repository.instance.bindSession(
        role: 'location',
        locationId: 2,
        locationName: 'Magadi road',
      );

      final comboId = await Repository.instance.saveCombo(
        Combo(
          name: '199 combo',
          price: 199,
          locationId: 2,
        ),
        [
          ComboRawMaterial(
            comboId: 0,
            rawMaterialId: loc1Ingredient,
            qty: 1,
          ),
        ],
      );

      final link = (await database.query(
        'combo_raw_materials',
        where: 'combo_id = ?',
        whereArgs: [comboId],
      ))
          .single;
      expect(link['raw_material_id'], loc2Ingredient);
      expect(link['raw_material_id'], isNot(loc1Ingredient));

      await tearDownStockTestSession(database);
    });

    test('audit counts cross-location combo ingredient links', () async {
      final database = await openStockTestDatabase();
      await seedSecondLocation(database);
      final now = DateTime.now().toIso8601String();

      final loc1Item = await database.insert('raw_materials', {
        'name': 'Burger Bun With Sesame',
        'sub_item': 'Burger Bun',
        'location_id': 1,
        'listed': 1,
        'created_at': now,
      });
      await seedLocationStock(database, loc1Item);

      final loc2Item = await database.insert('raw_materials', {
        'name': 'Chicken 65',
        'sub_item': 'Chicken 65',
        'location_id': 2,
        'listed': 1,
        'created_at': now,
      });
      await database.insert('location_stock', {
        'location_id': 2,
        'raw_material_id': loc2Item,
        'current_stock': 5,
        'opening_stock': 5,
        'reorder_level': 0,
      });

      final badComboId = await database.insert('combos', {
        'name': 'Combo test for magadi',
        'price': 199,
        'selling_price': 199,
        'is_active': 1,
        'location_id': 2,
        'created_at': now,
      });
      await database.insert('combo_raw_materials', {
        'combo_id': badComboId,
        'raw_material_id': loc1Item,
        'qty': 1,
      });
      await database.insert('combo_raw_materials', {
        'combo_id': badComboId,
        'raw_material_id': loc2Item,
        'qty': 1,
      });

      await database.insert('combos', {
        'name': 'Local only combo',
        'price': 120,
        'selling_price': 120,
        'is_active': 1,
        'location_id': 2,
        'created_at': now,
      });

      Repository.instance.setAppDbForTesting(SqliteAppDb(database));

      final mismatched =
          await Repository.instance.countCrossLocationComboIngredients();
      expect(mismatched, 1);

      await tearDownStockTestSession(database);
    });
  });
}
