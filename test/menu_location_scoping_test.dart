import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/menu_item_edit_helpers.dart';
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
      'name': 'Location B',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  group('stock source grid save', () {
    test('persists stock_source_id after save and reload', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);
      final now = DateTime.now().toIso8601String();

      final holderId = await database.insert('raw_materials', {
        'name': 'Chicken 65',
        'sub_item': 'Chicken 65',
        'location_id': 1,
        'qty_needed': 1,
        'opening_stock': 50,
        'current_stock': 50,
        'selling_price': 95,
        'created_at': now,
      });
      await seedLocationStock(database, holderId, stock: 50, openingStock: 50);

      final linkedId = await database.insert('raw_materials', {
        'name': 'Krusty Bites',
        'sub_item': 'chicken 65',
        'location_id': 1,
        'qty_needed': 1,
        'opening_stock': 0,
        'current_stock': 0,
        'selling_price': 99,
        'created_at': now,
      });
      await seedLocationStock(database, linkedId, stock: 0, openingStock: 0);

      final existing = (await Repository.instance.rawMaterialById(linkedId))!;
      final savedId = await Repository.instance.saveRawMaterial(
        MenuItemEditHelpers.buildForSave(
          existing: existing,
          barcodeText: '',
          itemName: 'Krusty Bites',
          subItemText: 'chicken 65',
          qtyPerSaleText: '1',
          packetsText: '0',
          unitsPerPacketText: '90',
          openingPiecesText: '',
          stockText: '0',
          costPriceText: '',
          sellingPriceText: '99',
          unitId: 2,
          stockSourceId: holderId,
        ),
        fromGridSave: true,
      );

      final row = (await database.query(
        'raw_materials',
        where: 'id = ?',
        whereArgs: [savedId],
      ))
          .single;
      expect(row['stock_source_id'], holderId);

      final reloaded = await Repository.instance.rawMaterialById(savedId);
      expect(reloaded?.stockSourceId, holderId);

      await tearDownStockTestSession(database);
    });
  });

  group('combo list reload', () {
    test('returns each combo once for the active location', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);
      final now = DateTime.now().toIso8601String();

      await database.insert('combos', {
        'name': 'Big juicy burger',
        'price': 199,
        'selling_price': 199,
        'is_active': 1,
        'location_id': 1,
        'created_at': now,
      });

      final first = await Repository.instance.combosWithItems();
      final second = await Repository.instance.combosWithItems();
      expect(first.length, 1);
      expect(second.length, 1);
      expect(first.first.name, 'Big juicy burger');

      await tearDownStockTestSession(database);
    });
  });

  group('location-scoped menu catalogs', () {
    test('editing location A does not change location B menu rows', () async {
      final database = await openStockTestDatabase();
      await seedSecondLocation(database);
      final now = DateTime.now().toIso8601String();

      final locAItem = await database.insert('raw_materials', {
        'name': 'Tea',
        'sub_item': 'Tea',
        'location_id': 1,
        'selling_price': 10,
        'created_at': now,
      });
      final locBItem = await database.insert('raw_materials', {
        'name': 'Tea',
        'sub_item': 'Tea',
        'location_id': 2,
        'selling_price': 10,
        'created_at': now,
      });
      await seedLocationStock(database, locAItem, stock: 5, openingStock: 5);
      await database.insert('location_stock', {
        'location_id': 2,
        'raw_material_id': locBItem,
        'current_stock': 8,
        'opening_stock': 8,
        'reorder_level': 0,
      });

      bindStockTestSession(database);
      final locA = (await Repository.instance.rawMaterialById(locAItem))!;
      await Repository.instance.saveRawMaterial(
        RawMaterial(
          id: locA.id,
          name: locA.name,
          subItem: locA.subItem,
          sellingPrice: 25,
          locationId: 1,
          currentStock: locA.currentStock,
          openingStock: locA.openingStock,
          createdAt: locA.createdAt,
        ),
        fromGridSave: true,
      );

      final locBRow = (await database.query(
        'raw_materials',
        where: 'id = ?',
        whereArgs: [locBItem],
      ))
          .single;
      expect((locBRow['selling_price'] as num).toDouble(), 10);

      await tearDownStockTestSession(database);
    });
  });

  group('save reload cycle', () {
    test('grid stock, stock source, and combo price match database after reload',
        () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);
      final now = DateTime.now().toIso8601String();

      final holderId = await database.insert('raw_materials', {
        'name': 'Chicken 65',
        'sub_item': 'Chicken 65',
        'location_id': 1,
        'opening_stock': 40,
        'current_stock': 40,
        'created_at': now,
      });
      await seedLocationStock(database, holderId, stock: 40, openingStock: 40);

      final itemId = await database.insert('raw_materials', {
        'name': 'Krusty Bites',
        'sub_item': 'chicken 65',
        'location_id': 1,
        'opening_stock': 0,
        'current_stock': 0,
        'created_at': now,
      });
      await seedLocationStock(database, itemId, stock: 0, openingStock: 0);

      final existing = (await Repository.instance.rawMaterialById(itemId))!;
      await Repository.instance.saveRawMaterial(
        MenuItemEditHelpers.buildForSave(
          existing: existing,
          barcodeText: '',
          itemName: 'Krusty Bites',
          subItemText: 'chicken 65',
          qtyPerSaleText: '1',
          packetsText: '2',
          unitsPerPacketText: '10',
          openingPiecesText: '',
          stockText: '20',
          costPriceText: '',
          sellingPriceText: '99',
          unitId: 2,
          stockSourceId: holderId,
        ),
        fromGridSave: true,
      );

      final comboId = await database.insert('combos', {
        'name': 'Value meal',
        'price': 150,
        'selling_price': 150,
        'is_active': 1,
        'location_id': 1,
        'created_at': now,
      });
      await Repository.instance.saveCombo(
        Combo(
          id: comboId,
          name: 'Value meal',
          price: 175,
          locationId: 1,
        ),
        [
          ComboRawMaterial(
            comboId: comboId,
            rawMaterialId: itemId,
            qty: 1,
          ),
        ],
      );

      final itemRow = (await database.query(
        'raw_materials',
        where: 'id = ?',
        whereArgs: [itemId],
      ))
          .single;
      expect(itemRow['stock_source_id'], holderId);

      final comboRow = (await database.query(
        'combos',
        where: 'id = ?',
        whereArgs: [comboId],
      ))
          .single;
      expect((comboRow['price'] as num).toDouble(), 175);

      final reloadedItem = await Repository.instance.rawMaterialById(itemId);
      expect(reloadedItem?.stockSourceId, holderId);

      final reloadedCombos = await Repository.instance.combos();
      expect(reloadedCombos.single.price, 175);

      final holderRow = (await database.query(
        'raw_materials',
        where: 'id = ?',
        whereArgs: [holderId],
      ))
          .single;
      expect((holderRow['opening_stock'] as num).toDouble(), 40);

      await tearDownStockTestSession(database);
    });
  });

  group('variant label uniqueness', () {
    test('allows same variant label at different locations', () async {
      final database = await openStockTestDatabase();
      await seedSecondLocation(database);
      final now = DateTime.now().toIso8601String();

      await database.insert('categories', {
        'name': 'Buckets',
        'type': 'raw_material',
      });

      final loc1Id = await database.insert('raw_materials', {
        'name': 'Big Buckets',
        'sub_item': 'Thai Crispy',
        'variant_label': 'Buckets',
        'category_id': 1,
        'location_id': 1,
        'listed': 1,
        'created_at': now,
      });
      await seedLocationStock(database, loc1Id);

      final loc2Id = await database.insert('raw_materials', {
        'name': 'Big Buckets',
        'sub_item': 'Thai Crispy',
        'variant_label': 'Buckets',
        'category_id': 1,
        'location_id': 2,
        'listed': 0,
        'created_at': now,
      });
      await database.insert('location_stock', {
        'location_id': 2,
        'raw_material_id': loc2Id,
        'current_stock': 0,
        'opening_stock': 0,
        'reorder_level': 0,
      });

      bindStockTestSession(database);
      Repository.instance.bindSession(
        role: 'location',
        locationId: 2,
        locationName: 'Magadi road',
      );

      final existing = (await Repository.instance.rawMaterialById(loc2Id))!;
      await Repository.instance.saveRawMaterial(
        RawMaterial(
          id: existing.id,
          name: existing.name,
          subItem: existing.subItem,
          variantLabel: 'Buckets',
          categoryId: 1,
          locationId: 2,
          listed: true,
          sellingPrice: 199,
        ),
      );

      final row = (await database.query(
        'raw_materials',
        where: 'id = ?',
        whereArgs: [loc2Id],
      ))
          .single;
      expect(row['listed'], 1);

      await tearDownStockTestSession(database);
    });

    test('still rejects duplicate variant label within one location', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);
      final now = DateTime.now().toIso8601String();

      await database.insert('categories', {
        'name': 'Buckets',
        'type': 'raw_material',
      });

      await database.insert('raw_materials', {
        'name': 'Big Buckets',
        'sub_item': 'Thai Crispy',
        'variant_label': 'Buckets',
        'category_id': 1,
        'location_id': 1,
        'listed': 1,
        'created_at': now,
      });
      final secondId = await database.insert('raw_materials', {
        'name': 'Mini Buckets',
        'sub_item': 'Thai Crispy',
        'variant_label': 'Buckets',
        'category_id': 1,
        'location_id': 1,
        'listed': 0,
        'created_at': now,
      });
      await seedLocationStock(database, 1);
      await seedLocationStock(database, secondId);

      await expectLater(
        Repository.instance.saveRawMaterial(
          RawMaterial(
            id: secondId,
            name: 'Mini Buckets',
            subItem: 'Thai Crispy',
            variantLabel: 'Buckets',
            categoryId: 1,
            locationId: 1,
            listed: true,
          ),
        ),
        throwsA(isA<InvalidInventoryException>()),
      );

      await tearDownStockTestSession(database);
    });
  });
}
