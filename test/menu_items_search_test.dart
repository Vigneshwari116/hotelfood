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

  group('Menu Items management search', () {
    test('finds Krisper roll by multi-word query', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('categories', {
        'id': 3,
        'name': 'Rolls',
        'type': 'raw_material',
      });
      await database.insert('raw_materials', {
        'id': 1,
        'name': 'Krisper roll',
        'sub_item': 'chicken strips',
        'category_id': 3,
        'listed': 1,
        'opening_stock': 0,
        'current_stock': 0,
        'created_at': now,
      });
      await seedLocationStock(database, 1);

      final byPhrase = await Repository.instance.rawMaterials(
        search: 'krisper roll',
        includeHidden: true,
      );
      expect(byPhrase, hasLength(1));
      expect(byPhrase.single.name, 'Krisper roll');

      final byCategoryWord = await Repository.instance.rawMaterials(
        search: 'rolls krisper',
        includeHidden: true,
      );
      expect(byCategoryWord, hasLength(1));

      await tearDownStockTestSession(database);
    });

    test('finds hidden listed=0 items when includeHidden is true', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);

      final now = DateTime.now().toIso8601String();
      await database.insert('raw_materials', {
        'id': 2,
        'name': 'Burger Bun With Sesame',
        'sub_item': 'Burger Bun With Sesame',
        'listed': 0,
        'opening_stock': 0,
        'current_stock': 0,
        'created_at': now,
      });
      await seedLocationStock(database, 2);

      final results = await Repository.instance.rawMaterials(
        search: 'burger bun',
        includeHidden: true,
      );
      expect(results, hasLength(1));

      await tearDownStockTestSession(database);
    });
  });
}
