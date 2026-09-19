import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/inventory_search.dart';
import 'package:foodstock/services/krusty_bites_stock.dart';
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

  group('Krusty Bites POS visibility', () {
    test('stays visible when linked to Chicken 65 stock pool', () {
      final chicken65 = RawMaterial(
        id: 1,
        name: 'Chicken 65',
        subItem: 'chicken 65',
        categoryId: 1,
        listed: true,
        currentStock: 32400,
      );
      final krusty = RawMaterial(
        id: 2,
        name: 'Krusty Bites',
        subItem: 'chicken 65',
        categoryId: 2,
        listed: true,
        stockSourceId: 1,
        currentStock: 32400,
      );
      final linked = VariantHelpers.withEffectiveStock([chicken65, krusty]);
      final byId = {
        for (final material in linked)
          if (material.id != null) material.id!: material,
      };

      expect(SubItemStock.isListedStockShadow(krusty, byId), isFalse);

      final visible = linked.where((material) {
        if (SubItemStock.isListedStockShadow(material, byId)) return false;
        return true;
      });
      expect(visible.map((item) => item.name), contains('Krusty Bites'));
    });

    test('matches POS search query "krusty"', () {
      final krusty = RawMaterial(
        id: 2,
        name: 'Krusty Bites',
        subItem: 'chicken 65',
        categoryId: 2,
        listed: true,
        stockSourceId: 1,
      );
      final haystack = inventoryMaterialHaystack(
        krusty,
        categoryName: 'Fried Items',
      );
      expect(matchesInventorySearchQuery(haystack, 'krusty'), isTrue);
    });
  });

  group('Krusty Bites stock pooling', () {
    test('withZeroOwnStock clears own stock fields only for Krusty Bites', () {
      final krusty = RawMaterial(
        id: 2,
        name: 'Krusty Bites',
        subItem: 'chicken 65',
        stockSourceId: 1,
        openingStock: 32400,
        openingPieces: 5,
        currentStock: 32400,
      );
      final other = RawMaterial(
        id: 3,
        name: 'Chicken popcorn large',
        subItem: 'Chicken Popcorn',
        stockSourceId: 1,
        currentStock: 500,
      );

      final zeroed = KrustyBitesStock.withZeroOwnStock(krusty);
      expect(zeroed.openingStock, 0);
      expect(zeroed.openingPieces, 0);
      expect(zeroed.currentStock, 0);
      expect(zeroed.stockSourceId, 1);

      expect(KrustyBitesStock.withZeroOwnStock(other), same(other));
    });

    test('saveRawMaterial zeros Krusty own stock when stock source is set',
        () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('categories', {
        'id': 1,
        'name': 'Snacks',
        'type': 'raw_material',
      });
      await database.insert('categories', {
        'id': 2,
        'name': 'Fried Items',
        'type': 'raw_material',
      });
      await database.insert('raw_materials', {
        'id': 1,
        'name': 'Chicken 65',
        'sub_item': 'chicken 65',
        'category_id': 1,
        'listed': 1,
        'opening_stock': 100,
        'current_stock': 100,
        'units_per_packet': 90,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'id': 2,
        'name': 'Krusty Bites',
        'sub_item': 'chicken 65',
        'category_id': 2,
        'listed': 1,
        'stock_source_id': 1,
        'opening_stock': 32400,
        'current_stock': 32400,
        'opening_pieces': 0,
        'units_per_packet': 90,
        'qty_needed': 1,
        'created_at': now,
      });
      await seedLocationStock(database, 1, stock: 100);
      await seedLocationStock(database, 2, stock: 32400);

      await Repository.instance.saveRawMaterial(
        RawMaterial(
          id: 2,
          name: 'Krusty Bites',
          subItem: 'chicken 65',
          categoryId: 2,
          listed: true,
          stockSourceId: 1,
          openingStock: 32400,
          currentStock: 32400,
          unitsPerPacket: 90,
          qtyNeeded: 1,
        ),
        skipVariantRefresh: true,
      );

      final krustyRow = await database.query(
        'raw_materials',
        where: 'id = ?',
        whereArgs: [2],
      );
      expect((krustyRow.first['current_stock'] as num).toDouble(), 0);
      expect((krustyRow.first['opening_stock'] as num).toDouble(), 0);

      final krustyLocation = await database.query(
        'location_stock',
        where: 'raw_material_id = ?',
        whereArgs: [2],
      );
      expect((krustyLocation.first['current_stock'] as num).toDouble(), 0);

      final chickenLocation = await database.query(
        'location_stock',
        where: 'raw_material_id = ?',
        whereArgs: [1],
      );
      expect((chickenLocation.first['current_stock'] as num).toDouble(), 100);

      await tearDownStockTestSession(database);
    });

    test('recordSale deducts Chicken 65 stock when selling Krusty Bites', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('categories', {
        'id': 1,
        'name': 'Snacks',
        'type': 'raw_material',
      });
      await database.insert('categories', {
        'id': 2,
        'name': 'Fried Items',
        'type': 'raw_material',
      });
      await database.insert('raw_materials', {
        'id': 1,
        'name': 'Chicken 65',
        'sub_item': 'chicken 65',
        'category_id': 1,
        'listed': 1,
        'opening_stock': 100,
        'current_stock': 100,
        'qty_needed': 1,
        'selling_price': 95,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'id': 2,
        'name': 'Krusty Bites',
        'sub_item': 'chicken 65',
        'category_id': 2,
        'listed': 1,
        'stock_source_id': 1,
        'opening_stock': 0,
        'current_stock': 0,
        'qty_needed': 1,
        'selling_price': 99,
        'created_at': now,
      });
      await seedLocationStock(database, 1, stock: 100);
      await seedLocationStock(database, 2, stock: 0);
      await database.insert('stock_batches', {
        'raw_material_id': 1,
        'qty_remaining': 100,
        'rate': 10,
        'location_id': 1,
        'created_at': now,
      });

      await Repository.instance.recordSale(
        lines: [
          CartLine(
            rawMaterialId: 2,
            name: 'Krusty Bites',
            subItem: 'chicken 65',
            qty: 1,
            price: 99,
          ),
        ],
        tax: 0,
        discount: 0,
        paymentType: 'cash',
      );

      final chickenStock = await locationStock(database, 1);
      final krustyStock = await locationStock(database, 2);

      expect(chickenStock, 99);
      expect(krustyStock, 0);

      await tearDownStockTestSession(database);
    });
  });
}
