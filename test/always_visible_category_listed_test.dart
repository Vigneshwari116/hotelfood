import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/always_visible_category_listed_repair.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/always_visible_menu_categories.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/stock_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('always visible menu categories', () {
    test('canonical names include Sauces Fried Items Snacks Uncategorized', () {
      expect(isAlwaysVisibleInSalesCategoryName('SAUCES'), isTrue);
      expect(isAlwaysVisibleInSalesCategoryName('fried items'), isTrue);
      expect(isAlwaysVisibleInSalesCategoryName('snacks'), isTrue);
      expect(isAlwaysVisibleInSalesCategoryName('Others'), isTrue);
      expect(isAlwaysVisibleInSalesCategoryName('Burgers'), isFalse);
    });

    test('repair migration lists hidden rows in always-visible categories only',
        () async {
      final database = await openStockTestDatabase();
      final now = DateTime.now().toIso8601String();

      await database.insert('categories', {
        'name': 'Burgers',
        'type': 'raw_material',
      });
      await database.insert('categories', {
        'name': 'Sauces',
        'type': 'raw_material',
      });
      await database.insert('categories', {
        'name': 'Fried Items',
        'type': 'raw_material',
      });

      final burgersCat = (await database.query(
        'categories',
        where: 'name = ?',
        whereArgs: ['Burgers'],
      ))
          .single['id'] as int;
      final saucesCat = (await database.query(
        'categories',
        where: 'name = ?',
        whereArgs: ['Sauces'],
      ))
          .single['id'] as int;
      final friedCat = (await database.query(
        'categories',
        where: 'name = ?',
        whereArgs: ['Fried Items'],
      ))
          .single['id'] as int;

      await database.insert('raw_materials', {
        'name': 'Hidden patty',
        'category_id': burgersCat,
        'listed': 0,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Hidden sauce',
        'category_id': saucesCat,
        'listed': 0,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Hidden fries',
        'category_id': friedCat,
        'listed': 0,
        'created_at': now,
      });

      final first = await migrateAlwaysVisibleCategoryListedRepair(database);
      expect(first.rowsUpdated, 2);
      expect(first.hiddenRemaining, 0);

      final burgerRow = await database.query(
        'raw_materials',
        where: 'name = ?',
        whereArgs: ['Hidden patty'],
      );
      final sauceRow = await database.query(
        'raw_materials',
        where: 'name = ?',
        whereArgs: ['Hidden sauce'],
      );
      expect(burgerRow.single['listed'], 0);
      expect(sauceRow.single['listed'], 1);

      final second = await migrateAlwaysVisibleCategoryListedRepair(database);
      expect(second.rowsUpdated, 0);

      await database.close();
    });

    test('saveRawMaterial forces listed for Fried Items even when hidden requested',
        () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);
      final now = DateTime.now().toIso8601String();

      await database.insert('categories', {
        'name': 'Fried Items',
        'type': 'raw_material',
      });
      final friedCat = (await database.query(
        'categories',
        where: 'name = ?',
        whereArgs: ['Fried Items'],
      ))
          .single['id'] as int;

      await migrateAlwaysVisibleCategoryListedRepair(database);

      final id = await Repository.instance.saveRawMaterial(
        RawMaterial(
          name: 'French Fries',
          categoryId: friedCat,
          listed: false,
        ),
      );

      final row = await database.query(
        'raw_materials',
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(row.single['listed'], 1);

      await tearDownStockTestSession(database);
    });

    test('saveRawMaterial respects listed=false for Burgers', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);
      final now = DateTime.now().toIso8601String();

      await database.insert('categories', {
        'name': 'Burgers',
        'type': 'raw_material',
      });
      final burgersCat = (await database.query(
        'categories',
        where: 'name = ?',
        whereArgs: ['Burgers'],
      ))
          .single['id'] as int;

      final id = await Repository.instance.saveRawMaterial(
        RawMaterial(
          name: 'Secret patty',
          categoryId: burgersCat,
          listed: false,
        ),
      );

      final row = await database.query(
        'raw_materials',
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(row.single['listed'], 0);

      await tearDownStockTestSession(database);
    });
  });
}
