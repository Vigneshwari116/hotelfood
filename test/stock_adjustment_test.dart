import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/stock_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('stock adjustments', () {
    test('negative adjustment updates stock, summary, and list', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final startIso = startOfDay.toIso8601String();

      await database.insert('raw_materials', {
        'name': 'French Fries',
        'sub_item': 'French Fries',
        'unit_id': 2,
        'opening_stock': 100,
        'current_stock': 100,
        'cost_price': 2,
        'listed': 1,
        'created_at': startIso,
      });
      await seedLocationStock(database, 1, stock: 100);
      await database.insert('stock_batches', {
        'raw_material_id': 1,
        'qty_remaining': 100,
        'rate': 2,
        'location_id': 1,
        'created_at': startIso,
      });
      await database.insert('stock_ledger', {
        'raw_material_id': 1,
        'entry_date': startIso,
        'ref_type': 'opening',
        'qty_in': 100,
        'qty_out': 0,
        'unit_cost': 2,
        'balance_after': 100,
        'location_id': 1,
      });

      await Repository.instance.adjustStock(1, -5, 'Wastage test');

      expect(await locationStock(database, 1), 95);

      final summary = await Repository.instance.stockMovementReport(
        from: startOfDay,
        to: startOfDay,
      );
      expect(summary.length, 1);
      expect((summary.first['adjustment_qty'] as num).toDouble(), -5);
      expect((summary.first['closing_qty'] as num).toDouble(), 95);

      final rows = await Repository.instance.stockAdjustments(
        from: startOfDay,
        to: startOfDay,
      );
      expect(rows.length, 1);
      expect(rows.first['item_name'], 'French Fries');
      expect((rows.first['qty'] as num).toDouble(), -5);
      expect((rows.first['closing_stock'] as num).toDouble(), 95);
      expect(rows.first['reason'], 'Wastage test');

      await tearDownStockTestSession(database);
    });

    test('positive adjustment increases stock and closing balance', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final startIso = startOfDay.toIso8601String();

      await database.insert('raw_materials', {
        'name': 'Tea',
        'sub_item': 'Tea',
        'opening_stock': 20,
        'current_stock': 20,
        'listed': 1,
        'created_at': startIso,
      });
      await seedLocationStock(database, 1, stock: 20);
      await database.insert('stock_batches', {
        'raw_material_id': 1,
        'qty_remaining': 20,
        'location_id': 1,
        'created_at': startIso,
      });

      await Repository.instance.adjustStock(1, 10, 'Found extra stock');

      expect(await locationStock(database, 1), 30);

      final rows = await Repository.instance.stockAdjustments(
        from: startOfDay,
        to: startOfDay,
      );
      expect(rows.length, 1);
      expect((rows.first['qty'] as num).toDouble(), 10);
      expect((rows.first['closing_stock'] as num).toDouble(), 30);

      await tearDownStockTestSession(database);
    });

    test('adjustStock rejects empty reason and zero qty', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('raw_materials', {
        'name': 'Salt',
        'opening_stock': 5,
        'current_stock': 5,
        'created_at': now,
      });
      await seedLocationStock(database, 1, stock: 5);
      await database.insert('stock_batches', {
        'raw_material_id': 1,
        'qty_remaining': 5,
        'location_id': 1,
        'created_at': now,
      });

      expect(
        () => Repository.instance.adjustStock(1, 0, 'Test'),
        throwsA(isA<InvalidInventoryException>()),
      );
      expect(
        () => Repository.instance.adjustStock(1, -1, '  '),
        throwsA(isA<InvalidInventoryException>()),
      );

      await tearDownStockTestSession(database);
    });
  });
}
