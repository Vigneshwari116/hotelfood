import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/database/sub_item_migration.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/repository.dart';
import 'package:foodstock/services/sub_item_stock.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/stock_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('sub_item migration backfill (12a)', () {
    test('canonicalLabelUpdatesForRows merges duplicate-case labels', () {
      final updates = SubItemStock.canonicalLabelUpdatesForRows([
        {
          'id': 1,
          'name': 'Chicken Popcorn',
          'sub_item': 'Chicken Popcorn',
        },
        {
          'id': 2,
          'name': 'Chicken popcorn large',
          'sub_item': 'chicken popcorn',
        },
        {
          'id': 3,
          'name': 'Chicken popcorn large',
          'sub_item': ' Chicken Popcorn ',
        },
      ]);

      expect(updates[2], 'Chicken Popcorn');
      expect(updates[3], 'Chicken Popcorn');
      expect(updates.containsKey(1), isFalse);
    });

    test('normalizeSubItemLabelsInDatabase backfills seeded duplicate rows', () async {
      final database = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE raw_materials (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              sub_item TEXT,
              menu_sort_order INTEGER,
              opening_stock REAL NOT NULL DEFAULT 0,
              current_stock REAL NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            )
          ''');

          final now = DateTime.now().toIso8601String();
          await db.insert('raw_materials', {
            'name': 'Chicken Popcorn',
            'sub_item': 'Chicken Popcorn',
            'opening_stock': 550,
            'current_stock': 550,
            'created_at': now,
          });
          await db.insert('raw_materials', {
            'name': 'Chicken popcorn large',
            'sub_item': 'chicken popcorn',
            'opening_stock': 0,
            'current_stock': 0,
            'created_at': now,
          });
          await db.insert('raw_materials', {
            'name': 'Chicken Popcorn box',
            'sub_item': ' Chicken Popcorn ',
            'opening_stock': 5500,
            'current_stock': 5500,
            'created_at': now,
          });
        },
      );

      final updated = await normalizeSubItemLabels(SqliteAppDb(database));
      expect(updated, 2);

      final rows = await database.query('raw_materials', columns: ['sub_item']);
      final labels = rows.map((row) => row['sub_item']).toSet();
      expect(labels, {'Chicken Popcorn'});

      await database.close();
    });

    test('stock summary collapses duplicate-case rows after migration backfill', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('raw_materials', {
        'name': 'Chicken Popcorn',
        'sub_item': 'Chicken Popcorn',
        'unit_id': 1,
        'opening_stock': 550,
        'current_stock': 550,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Chicken popcorn large',
        'sub_item': 'chicken popcorn',
        'unit_id': 1,
        'opening_stock': 0,
        'current_stock': 0,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Chicken Popcorn box',
        'sub_item': ' Chicken Popcorn ',
        'unit_id': 1,
        'opening_stock': 5500,
        'current_stock': 5500,
        'created_at': now,
      });

      await normalizeSubItemLabels(SqliteAppDb(database));

      final rows = await Repository.instance.stockMovementReport(
        from: DateTime(2026, 9, 16),
        to: DateTime(2026, 9, 16),
      );
      final popcornRows = rows.where(
        (row) =>
            (row['sub_item']?.toString().toLowerCase() ?? '').contains('popcorn'),
      );

      expect(popcornRows.length, 1);

      await tearDownStockTestSession(database);
    });
  });

  group('item sales report totals (12b)', () {
    test('reports per-item totals for grouped chicken 65 sales', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('raw_materials', {
        'name': 'Chicken 65',
        'sub_item': 'chicken 65',
        'qty_needed': 8,
        'selling_price': 85,
        'current_stock': 100,
        'opening_stock': 100,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Krusty Bites',
        'sub_item': 'chicken 65',
        'stock_source_id': 1,
        'qty_needed': 1,
        'selling_price': 90,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await seedLocationStock(database, 1, stock: 100);
      await seedLocationStock(database, 2);

      await Repository.instance.recordSale(
        lines: [
          CartLine(
            rawMaterialId: 1,
            name: 'Chicken 65',
            subItem: 'chicken 65',
            qty: 1,
            price: 85,
          ),
          CartLine(
            rawMaterialId: 2,
            name: 'Krusty Bites',
            subItem: 'chicken 65',
            qty: 2,
            price: 90,
          ),
        ],
        tax: 0,
        discount: 0,
        paymentType: 'cash',
      );

      final rows = await Repository.instance.itemSalesReport();
      final chicken65 = rows.firstWhere(
        (row) => row['item_name'] == 'Chicken 65',
      );
      final krusty = rows.firstWhere(
        (row) => row['item_name'] == 'Krusty Bites',
      );

      expect((chicken65['sold_qty'] as num).toDouble(), 1);
      expect((chicken65['total_amount'] as num).toDouble(), 85);
      expect((krusty['sold_qty'] as num).toDouble(), 2);
      expect((krusty['total_amount'] as num).toDouble(), 180);

      await tearDownStockTestSession(database);
    });
  });

  group('rawMaterialById pooled stock (12c)', () {
    test('returns holder stock for linked variants after purchase', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('raw_materials', {
        'name': 'Chicken Fingers',
        'sub_item': 'chicken finger',
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Chicken roll',
        'sub_item': 'chicken finger',
        'stock_source_id': 1,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await seedLocationStock(database, 1);
      await seedLocationStock(database, 2);

      await Repository.instance.recordPurchase(
        date: DateTime.now(),
        lines: [
          {'raw_material_id': 2, 'qty': 15, 'rate': 1},
        ],
      );

      final variant = await Repository.instance.rawMaterialById(2);
      expect(variant!.currentStock, 15);

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

      final afterSale = await Repository.instance.rawMaterialById(2);
      expect(afterSale!.currentStock, 14);

      await tearDownStockTestSession(database);
    });
  });

  group('snacks combo popcorn cleanup (12d)', () {
    test('removePopcornFromSnacksComboComponents drops popcorn from snack combos', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('raw_materials', {
        'name': 'Chicken Popcorn',
        'sub_item': 'Chicken Popcorn',
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'French Fries',
        'sub_item': 'Masala Fries',
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await database.insert('combos', {
        'name': 'Snacks Combo',
        'price': 150,
        'selling_price': 150,
        'created_at': now,
      });
      await database.insert('combos', {
        'name': 'Burger Combo',
        'price': 200,
        'selling_price': 200,
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
      await database.insert('combo_raw_materials', {
        'combo_id': 2,
        'raw_material_id': 1,
        'qty': 1,
      });

      final removed =
          await Repository.instance.removePopcornFromSnacksComboComponents();
      expect(removed, 1);

      final snackComponents = await database.query(
        'combo_raw_materials',
        where: 'combo_id = ?',
        whereArgs: [1],
      );
      expect(snackComponents.length, 1);
      expect(snackComponents.first['raw_material_id'], 2);

      final burgerComponents = await database.query(
        'combo_raw_materials',
        where: 'combo_id = ?',
        whereArgs: [2],
      );
      expect(burgerComponents.length, 1);

      await tearDownStockTestSession(database);
    });
  });
}
