import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/combo_only_categories.dart';
import 'package:foodstock/services/repository.dart';
import 'package:foodstock/services/sub_item_stock.dart';
import 'package:foodstock/services/variant_helpers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/stock_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('CartLine variant keying (14c)', () {
    test('displayLabel includes variant for sized items', () {
      final line = CartLine(
        rawMaterialId: 2,
        name: 'Chicken Popcorn',
        subItem: 'Chicken Popcorn',
        variantLabel: 'popcorn large',
        qty: 3,
        price: 129,
      );

      expect(line.displayLabel, 'Chicken Popcorn — popcorn large');
    });

    test('distinct variant labels create distinct cart identities', () {
      final regular = CartLine(
        rawMaterialId: 1,
        name: 'Chicken Popcorn',
        variantLabel: 'Regular',
        qty: 2,
        price: 75,
      );
      final large = CartLine(
        rawMaterialId: 2,
        name: 'Chicken Popcorn',
        variantLabel: 'popcorn large',
        qty: 1,
        price: 129,
      );

      expect(regular.displayLabel, isNot(large.displayLabel));
      expect(regular.rawMaterialId, isNot(large.rawMaterialId));
    });
  });

  group('sold line labels (14b)', () {
    test('soldLineLabel shows variant size on bill detail', () {
      final item = RawMaterial(name: 'Chicken Popcorn');
      expect(
        item.soldLineLabel(variantLabel: 'popcorn large'),
        'Chicken Popcorn — popcorn large',
      );
      expect(
        item.soldLineLabel(variantLabel: 'Regular'),
        'Chicken Popcorn',
      );
    });
  });

  group('variant label dedupe (14a)', () {
    test('normalizeVariantLabel treats case variants as duplicates', () {
      expect(
        SubItemStock.normalizeVariantLabel('Popcorn Large'),
        SubItemStock.normalizeVariantLabel('popcorn large'),
      );
    });
  });

  group('stock group unit validation (13c)', () {
    test('saveRawMaterial rejects mismatched unit in same stock group', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('raw_materials', {
        'name': 'Chicken Popcorn',
        'sub_item': 'Chicken Popcorn',
        'unit_id': 1,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Chicken popcorn large',
        'sub_item': 'Chicken Popcorn',
        'unit_id': 1,
        'stock_source_id': 1,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });

      await expectLater(
        Repository.instance.saveRawMaterial(
          RawMaterial(
            id: 2,
            name: 'Chicken popcorn large',
            subItem: 'Chicken Popcorn',
            unitId: 2,
            stockSourceId: 1,
          ),
        ),
        throwsA(isA<InvalidInventoryException>()),
      );

      await tearDownStockTestSession(database);
    });

    test('recordPurchase rejects mismatched unit with InvalidInventoryException', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('raw_materials', {
        'name': 'Chicken Popcorn',
        'sub_item': 'Chicken Popcorn',
        'unit_id': 1,
        'current_stock': 100,
        'opening_stock': 100,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Chicken popcorn large',
        'sub_item': 'Chicken Popcorn',
        'unit_id': 1,
        'stock_source_id': 1,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await seedLocationStock(database, 1, stock: 100);
      await seedLocationStock(database, 2);
      await database.update(
        'raw_materials',
        {'unit_id': 2},
        where: 'id = ?',
        whereArgs: [2],
      );

      await expectLater(
        Repository.instance.recordPurchase(
          date: DateTime.now(),
          lines: [
            {
              'raw_material_id': 2,
              'qty': 10,
              'rate': 1,
            },
          ],
        ),
        throwsA(
          isA<InvalidInventoryException>().having(
            (error) => error.message,
            'message',
            contains('tracked in g'),
          ),
        ),
      );

      await tearDownStockTestSession(database);
    });
  });

  group('inventory pooled stock (13b)', () {
    test('currentStockReport collapses grouped variants to one row', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('raw_materials', {
        'name': 'Chicken Popcorn',
        'sub_item': 'Chicken Popcorn',
        'unit_id': 1,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Chicken popcorn large',
        'sub_item': 'Chicken Popcorn',
        'unit_id': 1,
        'stock_source_id': 1,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await seedLocationStock(database, 1, stock: 500);
      await seedLocationStock(database, 2);

      final rows = await Repository.instance.currentStockReport();
      final popcornRows = rows.where(
        (row) =>
            (row['sub_item']?.toString().toLowerCase() ?? '').contains('popcorn'),
      );

      expect(popcornRows.length, 1);
      expect((popcornRows.first['current_stock'] as num).toDouble(), 500);

      await tearDownStockTestSession(database);
    });
  });

  group('combo-only categories (13a)', () {
    test('ComboOnlyCategories hides all-component categories only', () {
      final materials = [
        RawMaterial(id: 1, name: 'Bun', categoryId: 5, listed: true),
        RawMaterial(id: 2, name: 'Patty', categoryId: 5, listed: true),
        RawMaterial(id: 3, name: 'Chicken Roll', categoryId: 6, listed: true),
        RawMaterial(id: 4, name: 'Paratha', categoryId: 6, listed: true),
      ];
      final combos = [
        Combo(
          id: 1,
          name: 'Burger Combo',
          price: 150,
          items: [
            ComboItem(comboId: 1, rawMaterialId: 1, qty: 1),
            ComboItem(comboId: 1, rawMaterialId: 2, qty: 1),
          ],
        ),
        Combo(
          id: 2,
          name: 'Roll Combo',
          price: 120,
          items: [
            ComboItem(comboId: 2, rawMaterialId: 4, qty: 1),
          ],
        ),
      ];

      final comboOnly = ComboOnlyCategories.categoryIds(
        materials: materials,
        combos: combos,
      );

      expect(comboOnly, {5});
      expect(
        ComboOnlyCategories.isDirectSaleMaterial(
          materials[2],
          comboOnlyCategoryIds: comboOnly,
        ),
        isTrue,
      );
    });

    test('posVisibleCategoryIds keeps chip when combo-only category has combos', () {
      final materials = [
        RawMaterial(id: 1, name: 'Bun', categoryId: 5, listed: true),
        RawMaterial(id: 2, name: 'Patty', categoryId: 5, listed: true),
      ];
      final combos = [
        Combo(
          id: 1,
          name: 'Big juicy burger',
          price: 129,
          categoryId: 5,
          items: [
            ComboItem(comboId: 1, rawMaterialId: 1, qty: 1),
            ComboItem(comboId: 1, rawMaterialId: 2, qty: 1),
          ],
        ),
      ];

      final visible = ComboOnlyCategories.posVisibleCategoryIds(
        materials: materials,
        combos: combos,
      );

      expect(visible, {5});
    });

    test('posVisibleCategoryIds hides empty combo-only categories', () {
      final materials = [
        RawMaterial(id: 1, name: 'Bun', categoryId: 5, listed: true),
        RawMaterial(id: 2, name: 'Patty', categoryId: 5, listed: true),
      ];
      final combos = [
        Combo(
          id: 1,
          name: 'Retired burger',
          price: 129,
          categoryId: 5,
          isActive: false,
          items: [
            ComboItem(comboId: 1, rawMaterialId: 1, qty: 1),
            ComboItem(comboId: 1, rawMaterialId: 2, qty: 1),
          ],
        ),
      ];

      final visible = ComboOnlyCategories.posVisibleCategoryIds(
        materials: materials,
        combos: combos,
      );

      expect(visible, isEmpty);
    });
  });
}
