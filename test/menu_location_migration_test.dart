import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/location_menu_scoping.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/stock_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('location menu migration', () {
    test('backs up, clones per location, remaps history, and runs once', () async {
      final database = await openStockTestDatabase();
      final now = DateTime.now().toIso8601String();

      await database.insert('locations', {
        'name': 'Location B',
        'created_at': now,
      });

      await database.insert('raw_materials', {
        'name': 'Tea',
        'sub_item': 'Tea',
        'barcode': 'TEA-001',
        'opening_stock': 10,
        'current_stock': 10,
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
        'current_stock': 20,
        'opening_stock': 20,
        'reorder_level': 0,
      });

      await database.insert('combos', {
        'name': 'Big juicy burger',
        'price': 99,
        'selling_price': 99,
        'is_active': 1,
        'created_at': now,
      });
      await database.insert('combo_raw_materials', {
        'combo_id': 1,
        'raw_material_id': 1,
        'qty': 1,
      });

      final purchaseId = await database.insert('purchases', {
        'purchase_date': now,
        'total_amount': 50,
        'location_id': 2,
      });
      await database.insert('purchase_items', {
        'purchase_id': purchaseId,
        'raw_material_id': 1,
        'qty': 5,
        'rate': 10,
        'amount': 50,
      });

      await database.insert('stock_ledger', {
        'raw_material_id': 1,
        'entry_date': now,
        'ref_type': 'purchase',
        'ref_id': purchaseId,
        'qty_in': 5,
        'qty_out': 0,
        'balance_after': 20,
        'location_id': 2,
      });

      await database.insert('stock_batches', {
        'raw_material_id': 1,
        'qty_remaining': 5,
        'location_id': 2,
        'created_at': now,
      });

      final saleId = await database.insert('sales', {
        'sale_date': now,
        'subtotal': 99,
        'total': 99,
        'payment_type': 'cash',
        'location_id': 2,
      });
      await database.insert('sale_items', {
        'sale_id': saleId,
        'raw_material_id': 1,
        'combo_id': 1,
        'item_name': 'Combo A',
        'qty': 1,
        'price': 99,
        'amount': 99,
      });

      await migrateMenuCatalogToLocationScope(database);

      final backupCount = await database.rawQuery(
        'SELECT COUNT(*) AS c FROM raw_materials_pre_migration_backup',
      );
      expect((backupCount.first['c'] as num).toInt(), 1);

      final migrationRow = await database.query(
        'schema_migrations',
        where: 'name = ?',
        whereArgs: ['location_menu_catalog_scope_v1'],
      );
      expect(migrationRow, isNotEmpty);

      final materials = await database.query('raw_materials', orderBy: 'id ASC');
      expect(materials.length, 2);
      expect(materials.first['location_id'], 1);
      expect(materials.last['location_id'], 2);
      expect(materials.first['barcode'], 'TEA-001');
      expect(materials.last['barcode'], 'TEA-001');
      final loc2MaterialId = materials.last['id'] as int;

      final purchaseLine = await database.query('purchase_items');
      expect(purchaseLine.single['raw_material_id'], loc2MaterialId);

      final ledger = await database.query(
        'stock_ledger',
        where: 'location_id = ?',
        whereArgs: [2],
      );
      expect(ledger.single['raw_material_id'], loc2MaterialId);

      final batch = await database.query(
        'stock_batches',
        where: 'location_id = ?',
        whereArgs: [2],
      );
      expect(batch.single['raw_material_id'], loc2MaterialId);

      final saleLine = await database.query('sale_items');
      expect(saleLine.single['raw_material_id'], loc2MaterialId);
      expect(saleLine.single['combo_id'], isNot(1));

      final combos = await database.query('combos', orderBy: 'id ASC');
      expect(combos.length, 2);
      expect(combos.first['name'], 'Big juicy burger');
      expect(combos.last['name'], 'Big juicy burger');

      final loc2ComboId = combos.last['id'] as int;
      final comboLinks = await database.query(
        'combo_raw_materials',
        where: 'combo_id = ?',
        whereArgs: [loc2ComboId],
      );
      expect(comboLinks, hasLength(1));
      expect(comboLinks.single['raw_material_id'], loc2MaterialId);

      await migrateMenuCatalogToLocationScope(database);
      final materialsAfter = await database.query('raw_materials');
      expect(materialsAfter.length, 2);

      await database.close();
    });
  });
}
