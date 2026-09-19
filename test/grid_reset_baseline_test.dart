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

  group('grid save reset baseline', () {
    test('reset keeps stock saved from menu grid instead of original import', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);
      final now = DateTime.now().toIso8601String();

      await database.insert('raw_materials', {
        'name': 'Chicken 65',
        'sub_item': 'Chicken 65',
        'qty_needed': 1,
        'unit_id': 2,
        'units_per_packet': 15,
        'opening_stock': 90,
        'current_stock': 90,
        'cost_price': 10,
        'selling_price': 85,
        'created_at': now,
      });
      await seedLocationStock(
        database,
        1,
        stock: 90,
        openingStock: 90,
      );

      final existing = (await Repository.instance.rawMaterialById(1))!;
      final saved = MenuItemEditHelpers.buildForSave(
        existing: existing,
        barcodeText: '',
        itemName: 'Chicken 65',
        subItemText: 'Chicken 65',
        qtyPerSaleText: '1',
        packetsText: '10',
        unitsPerPacketText: '15',
        openingPiecesText: '',
        stockText: '150',
        costPriceText: '10',
        sellingPriceText: '85',
        unitId: 2,
      );

      await Repository.instance.saveRawMaterial(
        saved,
        fromGridSave: true,
      );

      await database.update(
        'location_stock',
        {'current_stock': 120},
        where: 'location_id = ? AND raw_material_id = ?',
        whereArgs: [1, 1],
      );

      await Repository.instance.resetDemoTransactionData(locationId: 1);

      final row = (await database.query(
        'location_stock',
        where: 'location_id = ? AND raw_material_id = ?',
        whereArgs: [1, 1],
      ))
          .single;

      expect((row['opening_stock'] as num).toDouble(), 150);
      expect((row['current_stock'] as num).toDouble(), 150);

      await tearDownStockTestSession(database);
    });

    test('grid save updates reset baseline from displayed stock after sales', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);
      final now = DateTime.now().toIso8601String();

      await database.insert('raw_materials', {
        'name': 'Tea',
        'sub_item': 'Tea',
        'qty_needed': 1,
        'opening_stock': 100,
        'current_stock': 60,
        'selling_price': 10,
        'created_at': now,
      });
      await seedLocationStock(
        database,
        1,
        stock: 60,
        openingStock: 100,
      );

      final existing = (await Repository.instance.rawMaterialById(1))!;
      final saved = MenuItemEditHelpers.buildForSave(
        existing: existing,
        barcodeText: '',
        itemName: 'Tea',
        subItemText: 'Tea',
        qtyPerSaleText: '1',
        packetsText: '',
        unitsPerPacketText: '',
        openingPiecesText: '',
        stockText: '60',
        costPriceText: '',
        sellingPriceText: '15',
        unitId: null,
      );

      await Repository.instance.saveRawMaterial(
        saved,
        fromGridSave: true,
      );

      await Repository.instance.resetDemoTransactionData(locationId: 1);

      final row = (await database.query(
        'location_stock',
        where: 'location_id = ? AND raw_material_id = ?',
        whereArgs: [1, 1],
      ))
          .single;

      expect((row['opening_stock'] as num).toDouble(), 60);
      expect((row['current_stock'] as num).toDouble(), 60);

      await tearDownStockTestSession(database);
    });
  });
}
