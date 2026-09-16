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

  test('withEffectiveStock follows stock_source_id for display', () {
    final holder = RawMaterial(
      id: 1,
      name: 'Chicken Fingers',
      subItem: 'chicken finger',
      currentStock: 42,
    );
    final variant = RawMaterial(
      id: 2,
      name: 'Chicken roll',
      subItem: 'chicken finger',
      stockSourceId: 1,
      currentStock: 0,
    );

    final display = VariantHelpers.withEffectiveStock([holder, variant]);
    final roll = display.firstWhere((item) => item.id == 2);
    expect(roll.currentStock, 42);
  });

  test('recordPurchase credits pooled stock holder', () async {
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
        {
          'raw_material_id': 2,
          'qty': 10,
          'rate': 5,
        },
      ],
    );

    final holder = await Repository.instance.rawMaterialById(1);
    final variant = await Repository.instance.rawMaterialById(2);
    expect(holder!.currentStock, 10);
    expect(variant!.currentStock, 10);

    final display = await Repository.instance.rawMaterialsForDisplay(
      includeHidden: true,
    );
    final roll = display.firstWhere((item) => item.id == 2);
    expect(roll.currentStock, 10);

    await tearDownStockTestSession(database);
  });
}
