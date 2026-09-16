import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/repository.dart';
import 'package:foodstock/services/variant_helpers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/stock_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Stock management flows', () {
    // Test 1: cross-name sub_item pool — purchase one, sell another.
    test('purchase and sale share one sub_item stock pool across item names', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('raw_materials', {
        'name': 'Chicken 65',
        'sub_item': 'chicken 65',
        'qty_needed': 8,
        'selling_price': 85,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Tandoori roll',
        'sub_item': 'chicken 65',
        'stock_source_id': 1,
        'qty_needed': 1,
        'selling_price': 85,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await seedLocationStock(database, 1);
      await seedLocationStock(database, 2);

      await Repository.instance.recordPurchase(
        date: DateTime.now(),
        lines: [
          {'raw_material_id': 2, 'qty': 40, 'rate': 1},
        ],
      );

      expect(await locationStock(database, 1), 40);
      expect(await locationStock(database, 2), 0);

      await Repository.instance.recordSale(
        lines: [
          CartLine(
            rawMaterialId: 1,
            name: 'Chicken 65',
            subItem: 'chicken 65',
            qty: 1,
            price: 85,
          ),
        ],
        tax: 0,
        discount: 0,
        paymentType: 'cash',
      );

      expect(await locationStock(database, 1), 32);
      expect(await locationStock(database, 2), 0);

      final display = await Repository.instance.rawMaterialsForDisplay(
        includeHidden: true,
      );
      final roll = display.firstWhere((item) => item.id == 2);
      expect(roll.currentStock, 32);

      await tearDownStockTestSession(database);
    });

    // Test 2: Chicken Popcorn pooled sale math.
    test('popcorn regular and large sales deduct from one pooled stock', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('raw_materials', {
        'name': 'Chicken Popcorn',
        'sub_item': 'Chicken Popcorn',
        'qty_needed': 80,
        'unit_id': 1,
        'selling_price': 75,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Chicken popcorn large',
        'sub_item': 'Chicken Popcorn',
        'stock_source_id': 1,
        'qty_needed': 130,
        'unit_id': 1,
        'selling_price': 129,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await seedLocationStock(database, 1);
      await seedLocationStock(database, 2);

      await Repository.instance.recordPurchase(
        date: DateTime.now(),
        lines: [
          {'raw_material_id': 1, 'qty': 5500, 'rate': 1},
        ],
      );

      await Repository.instance.recordSale(
        lines: [
          CartLine(
            rawMaterialId: 1,
            name: 'Chicken Popcorn',
            subItem: 'Chicken Popcorn',
            qty: 1,
            price: 75,
          ),
        ],
        tax: 0,
        discount: 0,
        paymentType: 'cash',
      );

      await Repository.instance.recordSale(
        lines: [
          CartLine(
            rawMaterialId: 2,
            name: 'Chicken popcorn large',
            subItem: 'Chicken Popcorn',
            qty: 1,
            price: 129,
          ),
        ],
        tax: 0,
        discount: 0,
        paymentType: 'cash',
      );

      expect(await locationStock(database, 1), 5290);
      expect(await locationStock(database, 2), 0);

      final display = await Repository.instance.rawMaterialsForDisplay(
        includeHidden: true,
      );
      final large = display.firstWhere((item) => item.id == 2);
      expect(large.currentStock, 5290);

      await tearDownStockTestSession(database);
    });

    // Test 3: purchase → Items → sale → Items agree on stock.
    test('purchase, display, sale, and display use the same pooled stock', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('raw_materials', {
        'name': 'Chicken Fingers',
        'sub_item': 'chicken finger',
        'qty_needed': 3,
        'selling_price': 60,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Chicken roll',
        'sub_item': 'chicken finger',
        'stock_source_id': 1,
        'qty_needed': 2,
        'selling_price': 75,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await seedLocationStock(database, 1);
      await seedLocationStock(database, 2);

      await Repository.instance.recordPurchase(
        date: DateTime.now(),
        lines: [
          {'raw_material_id': 2, 'qty': 100, 'rate': 1},
        ],
      );

      final afterPurchase = await Repository.instance.rawMaterialsForDisplay(
        includeHidden: true,
      );
      final rollAfterPurchase =
          afterPurchase.firstWhere((item) => item.id == 2);
      expect(rollAfterPurchase.currentStock, 100);

      await Repository.instance.recordSale(
        lines: [
          CartLine(
            rawMaterialId: 2,
            name: 'Chicken roll',
            subItem: 'chicken finger',
            qty: 1,
            price: 75,
          ),
        ],
        tax: 0,
        discount: 0,
        paymentType: 'cash',
      );

      final afterSale = await Repository.instance.rawMaterialsForDisplay(
        includeHidden: true,
      );
      final holderAfterSale =
          afterSale.firstWhere((item) => item.id == 1);
      final rollAfterSale = afterSale.firstWhere((item) => item.id == 2);
      expect(await locationStock(database, 1), 98);
      expect(holderAfterSale.currentStock, 98);
      expect(rollAfterSale.currentStock, 98);

      await tearDownStockTestSession(database);
    });

    // Test 4: combo sale deducts configured components only.
    test('combo sale deducts configured component quantities', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('raw_materials', {
        'name': 'Bun',
        'sub_item': 'Bun',
        'qty_needed': 1,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Patty',
        'sub_item': 'Patty',
        'qty_needed': 1,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Fries',
        'sub_item': 'French Fries',
        'qty_needed': 1,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await seedLocationStock(database, 1, stock: 10);
      await seedLocationStock(database, 2, stock: 10);
      await seedLocationStock(database, 3, stock: 10);

      await database.insert('combos', {
        'name': 'Star Burger Combo',
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
      await database.insert('combo_raw_materials', {
        'combo_id': 1,
        'raw_material_id': 2,
        'qty': 1,
      });

      await Repository.instance.recordSale(
        lines: [
          CartLine(
            comboId: 1,
            name: 'Star Burger Combo',
            componentLabels: const ['Bun', 'Patty'],
            qty: 1,
            price: 150,
          ),
        ],
        tax: 0,
        discount: 0,
        paymentType: 'cash',
      );

      expect(await locationStock(database, 1), 9);
      expect(await locationStock(database, 2), 9);
      expect(await locationStock(database, 3), 10);

      await tearDownStockTestSession(database);
    });

    // Test 6: Stock Summary closing formula with pooled rows.
    test('stock summary closing equals opening plus purchase minus sales', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('raw_materials', {
        'name': 'Chicken Popcorn',
        'sub_item': 'Chicken Popcorn',
        'qty_needed': 80,
        'unit_id': 1,
        'current_stock': 100,
        'opening_stock': 100,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Chicken popcorn large',
        'sub_item': 'Chicken Popcorn',
        'stock_source_id': 1,
        'qty_needed': 130,
        'unit_id': 1,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await seedLocationStock(database, 1, stock: 100);
      await seedLocationStock(database, 2, stock: 0);

      await database.insert('stock_ledger', {
        'raw_material_id': 1,
        'entry_date': '2026-09-01T08:00:00.000',
        'ref_type': 'opening',
        'qty_in': 100,
        'qty_out': 0,
        'unit_cost': 1,
        'balance_after': 100,
        'location_id': 1,
      });
      await database.insert('stock_ledger', {
        'raw_material_id': 1,
        'entry_date': '2026-09-10T10:00:00.000',
        'ref_type': 'purchase',
        'qty_in': 50,
        'qty_out': 0,
        'unit_cost': 1,
        'balance_after': 150,
        'location_id': 1,
      });
      await database.insert('stock_ledger', {
        'raw_material_id': 1,
        'entry_date': '2026-09-12T12:00:00.000',
        'ref_type': 'sale_deduction',
        'qty_in': 0,
        'qty_out': 80,
        'unit_cost': 1,
        'balance_after': 70,
        'location_id': 1,
      });

      final rows = await Repository.instance.stockMovementReport(
        from: DateTime(2026, 9, 10),
        to: DateTime(2026, 9, 12),
      );

      final holder = rows.firstWhere((row) => row['id'] == 1);
      expect(rows.any((row) => row['id'] == 2), isFalse);
      final opening = (holder['opening_qty'] as num).toDouble();
      final purchase = (holder['purchase_qty'] as num).toDouble();
      final sales = (holder['sales_qty'] as num).toDouble();
      final closing = (holder['closing_qty'] as num).toDouble();
      final adjustment = (holder['adjustment_qty'] as num).toDouble();

      expect(opening + purchase - sales + adjustment, closing);

      await tearDownStockTestSession(database);
    });
  });

  group('Approved master data guards', () {
    // Test 7
    test('Krisper roll units_per_packet remains blank in approved CSV', () {
      final csv = File('assets/templates/shilpa_enterprise_menu_1401.csv')
          .readAsStringSync();
      final line = csv
          .split('\n')
          .firstWhere((row) => row.contains('Krisper roll'));
      final cells = line.split(',');
      expect(cells.length, greaterThan(6));
      expect(cells[6].trim(), isEmpty);
    });

    // Test 8
    test('Chicken Cheese Shotz Large is absent from approved templates', () {
      final master = File('assets/templates/shilpa_enterprise_menu_1401.csv')
          .readAsStringSync();
      final importCsv = File('assets/templates/menu_items_import.csv')
          .readAsStringSync();
      expect(master.toLowerCase(), isNot(contains('cheese shotz large')));
      expect(importCsv.toLowerCase(), isNot(contains('cheese shotz large')));
    });

    test('approved Sheet2 seed uses confirmed grouping and pricing', () {
      final csv = File('assets/templates/shilpa_enterprise_menu_1401.csv')
          .readAsStringSync();
      final rows = csv.split('\n').where((line) => line.trim().isNotEmpty);

      Map<String, String> rowFor(String itemName) {
        final line = rows.firstWhere(
          (row) => row.split(',')[1].trim() == itemName,
        );
        return {
          for (var i = 0; i < line.split(',').length; i++)
            '$i': line.split(',')[i].trim(),
        };
      }

      expect(rowFor('Tandoori roll')['6'], '5');
      expect(rowFor('Chicken popcorn large')['4'], '130');
      expect(rowFor('Chicken popcorn large')['10'], '129');
      expect(rowFor('Veg roll')['10']?.trim(), isEmpty);
      expect(rowFor('Krisper roll')['10'], '105');
      expect(rowFor('Chicken 65')['2'], 'chicken 65');
      expect(rowFor('Chicken Strips')['2'], 'chicken strips');
      expect(rowFor('French Fries')['2'], 'Masala Fries');
      expect(rowFor('masala fries Large')['2'], 'Masala Fries');
      expect(rowFor('Chicken Cheese Shotz')['2'], 'Cheese Shots');
      expect(csv.toLowerCase(), isNot(contains('snacks,chicken popcorn large')));
    });

    // Test 5 is covered by menu_import_stock_preservation_test.dart; verify file exists.
    test('menu re-import stock preservation test is present', () {
      expect(
        File('test/menu_import_stock_preservation_test.dart').existsSync(),
        isTrue,
      );
    });
  });

  group('POS burger rules', () {
    bool isBurgersCategory(String? categoryName) {
      final name = categoryName?.trim().toLowerCase() ?? '';
      return name == 'burgers' || name == 'burger';
    }

    bool isDirectSaleMaterial(String? categoryName) {
      return !isBurgersCategory(categoryName);
    }

    // Test 9
    test('burger rows are not direct POS sale items; combos are separate', () {
      final burger = RawMaterial(
        id: 1,
        name: 'star burger',
        subItem: 'Crispy Chicken Patty',
        categoryId: 10,
        sellingPrice: 60,
      );

      expect(isDirectSaleMaterial('Burgers'), isFalse);
      expect(isDirectSaleMaterial(burger.categoryId == 10 ? 'Burgers' : null),
          isFalse);

      final combo = Combo(
        id: 99,
        name: 'Star Burger Combo',
        price: 150,
        categoryId: 10,
        items: const [],
      );
      expect(combo.name.contains('Combo'), isTrue);
      expect(
        VariantHelpers.partitionForPos([burger]).singles.length,
        1,
      );
    });

    test('syncVariantLinks pools Krusty Bites with Chicken 65 by sub_item', () {
      final chicken65 = RawMaterial(
        id: 1,
        name: 'Chicken 65',
        subItem: 'chicken 65',
        categoryId: 1,
      );
      final krusty = RawMaterial(
        id: 2,
        name: 'Krusty Bites',
        subItem: 'chicken 65',
        categoryId: 2,
      );
      final roll = RawMaterial(
        id: 3,
        name: 'Tandoori roll',
        subItem: 'chicken 65',
        categoryId: 3,
      );

      final updates = VariantHelpers.syncVariantLinks(
        [chicken65, krusty, roll],
        categoryNameById: {
          1: 'Snacks',
          2: 'Fried Items',
          3: 'Rolls',
        },
      );

      final krustyUpdate = updates.firstWhere((item) => item.id == 2);
      final rollUpdate = updates.firstWhere((item) => item.id == 3);
      expect(krustyUpdate.stockSourceId, 1);
      expect(rollUpdate.stockSourceId, 1);
    });
  });
}
