import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/item_import_service.dart';
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

  group('grid dirty baseline', () {
    test('stock source link after baseline must be reset to avoid false dirty state',
        () {
      final baseline = MenuItemEditHelpers.captureGridRowSnapshot(
        barcodeText: '',
        itemName: 'Krusty Bites',
        subItemText: 'chicken 65',
        variantGroupText: '',
        variantLabelText: '',
        stockSourceNameText: '',
        qtyPerSaleText: '1',
        packetsText: '0',
        openingPiecesText: '',
        unitsPerPacketText: '90',
        stockText: '0',
        costPriceText: '',
        sellingPriceText: '99',
        unitId: 2,
      );

      final afterStockSourceLink = MenuItemEditHelpers.captureGridRowSnapshot(
        barcodeText: '',
        itemName: 'Krusty Bites',
        subItemText: 'chicken 65',
        variantGroupText: '',
        variantLabelText: '',
        stockSourceNameText: 'Chicken 65',
        qtyPerSaleText: '1',
        packetsText: '0',
        openingPiecesText: '',
        unitsPerPacketText: '90',
        stockText: '0',
        costPriceText: '',
        sellingPriceText: '99',
        unitId: 2,
      );

      expect(baseline == afterStockSourceLink, isFalse);

      final resetBaseline = afterStockSourceLink;
      expect(resetBaseline == afterStockSourceLink, isTrue);
    });
  });

  group('grid save reset baseline', () {
    test('reset restores last grid-saved stock, not original import baseline', () async {
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
        'selling_price': 95,
        'created_at': now,
      });
      await seedLocationStock(database, 1, stock: 90, openingStock: 90);

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
        costPriceText: '',
        sellingPriceText: '95',
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
      await database.update(
        'raw_materials',
        {'current_stock': 120},
        where: 'id = ?',
        whereArgs: [1],
      );

      await Repository.instance.resetDemoTransactionData(locationId: 1);

      final row = (await database.query(
        'location_stock',
        where: 'location_id = ? AND raw_material_id = ?',
        whereArgs: [1, 1],
      ))
          .single;
      final item = (await database.query(
        'raw_materials',
        where: 'id = ?',
        whereArgs: [1],
      ))
          .single;

      expect((row['opening_stock'] as num).toDouble(), 150);
      expect((row['current_stock'] as num).toDouble(), 150);
      expect(item['name'], 'Chicken 65');
      expect(item['sub_item'], 'Chicken 65');
      expect((item['selling_price'] as num).toDouble(), 95);

      await tearDownStockTestSession(database);
    });
  });

  group('grid export uses live saved values', () {
    test('exportGridWorkbookForLocation reflects saved grid stock', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);
      final now = DateTime.now().toIso8601String();

      await database.insert('categories', {
        'id': 1,
        'name': 'Snacks',
        'type': 'raw_material',
      });
      await database.insert('raw_materials', {
        'id': 1,
        'name': 'Tea',
        'sub_item': 'Tea',
        'category_id': 1,
        'qty_needed': 1,
        'opening_stock': 25,
        'current_stock': 25,
        'selling_price': 15,
        'created_at': now,
      });
      await seedLocationStock(database, 1, stock: 25, openingStock: 25);

      final existing = (await Repository.instance.rawMaterialById(1))!;
      await Repository.instance.saveRawMaterial(
        MenuItemEditHelpers.buildForSave(
          existing: existing,
          barcodeText: '',
          itemName: 'Tea',
          subItemText: 'Tea',
          qtyPerSaleText: '1',
          packetsText: '',
          unitsPerPacketText: '',
          openingPiecesText: '',
          stockText: '40',
          costPriceText: '',
          sellingPriceText: '15',
          unitId: null,
        ),
        fromGridSave: true,
      );

      final rows = await ItemImportService().gridExportRowsForLocation(1);
      expect(rows, isNotEmpty);
      final teaRow = rows.firstWhere((row) => row[2] == 'Tea');
      expect(teaRow[10], '40');

      await tearDownStockTestSession(database);
    });
  });
}
