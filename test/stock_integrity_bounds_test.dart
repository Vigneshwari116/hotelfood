import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/stock_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('stock integrity bounds', () {
    test('saveRawMaterial rejects absurd current stock', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      await expectLater(
        Repository.instance.saveRawMaterial(
          RawMaterial(
            name: 'Test Item',
            subItem: 'Test Item',
            currentStock: 150000,
          ),
        ),
        throwsA(isA<InvalidInventoryException>()),
      );

      await tearDownStockTestSession(database);
    });

    test('saveRawMaterial rejects mismatched units_per_packet in group', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);
      final now = DateTime.now().toIso8601String();

      await database.insert('raw_materials', {
        'name': 'Thai Crispy Regular',
        'sub_item': 'Thai Crispy',
        'unit_id': 1,
        'units_per_packet': 10,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });
      await database.insert('raw_materials', {
        'name': 'Thai Crispy Buckets',
        'sub_item': 'Thai Crispy',
        'unit_id': 1,
        'stock_source_id': 1,
        'current_stock': 0,
        'opening_stock': 0,
        'created_at': now,
      });

      await expectLater(
        Repository.instance.saveRawMaterial(
          RawMaterial(
            id: 2,
            name: 'Thai Crispy Buckets',
            subItem: 'Thai Crispy',
            unitId: 1,
            stockSourceId: 1,
            unitsPerPacket: null,
          ),
        ),
        throwsA(isA<InvalidInventoryException>()),
      );

      await tearDownStockTestSession(database);
    });
  });
}
