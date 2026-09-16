import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/raw_material_integrity.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/services/inventory_search.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/stock_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('repairOrphanedRawMaterialReferences', () {
    test('clears invalid stock_source_id and orphan combo links', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('raw_materials', {
        'id': 10,
        'name': 'Burger Bun With Sesame',
        'sub_item': 'Burger Bun With Sesame',
        'stock_source_id': 47,
        'unit_id': 1,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await database.insert('combos', {
        'id': 1,
        'name': 'chicken roll',
        'price': 75,
        'is_active': 1,
        'created_at': now,
      });
      await database.insert('combo_raw_materials', {
        'combo_id': 1,
        'raw_material_id': 99,
        'qty': 1,
      });
      await database.insert('stock_batches', {
        'raw_material_id': 47,
        'qty_remaining': 5,
        'created_at': now,
      });

      final appDb = SqliteAppDb(database);
      final report = await repairOrphanedRawMaterialReferences(appDb);
      expect(report.clearedInvalidStockSources, 1);
      expect(report.removedOrphanComboComponents, 1);
      expect(report.removedOrphanStockBatches, 1);

      final bun = await database.query(
        'raw_materials',
        where: 'id = ?',
        whereArgs: [10],
      );
      expect(bun.single['stock_source_id'], isNull);

      await tearDownStockTestSession(database);
    });

    test('recordPurchase succeeds after repair clears dangling stock source', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('raw_materials', {
        'id': 10,
        'name': 'Burger Bun With Sesame',
        'sub_item': 'Burger Bun With Sesame',
        'stock_source_id': 47,
        'unit_id': 1,
        'units_per_packet': 6,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await seedLocationStock(database, 10, stock: 0);

      await repairOrphanedRawMaterialReferences(SqliteAppDb(database));

      await Repository.instance.recordPurchase(
        date: DateTime.now(),
        lines: [
          {
            'raw_material_id': 10,
            'qty': 30,
            'rate': 79,
          },
        ],
      );

      expect(await locationStock(database, 10), 30);

      await tearDownStockTestSession(database);
    });
  });

  group('menu item search', () {
    test('matches category and multi-word queries', () {
      const haystack = 'krisper roll rolls paratha';
      expect(matchesInventorySearchQuery(haystack, 'krisper roll'), isTrue);
      expect(matchesInventorySearchQuery(haystack, 'roll krisper'), isTrue);
      expect(
        matchesInventorySearchQuery('sausage fried items snacks', 'fried items'),
        isTrue,
      );
    });
  });
}
