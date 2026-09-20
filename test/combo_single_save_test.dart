import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/category_cleanup.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/combo_catalog_sync.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/stock_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('combo single-record save', () {
    test('saveCombo updates only the edited combo', () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);
      final now = DateTime.now().toIso8601String();

      await database.insert('categories', {
        'name': 'Rolls',
        'type': 'raw_material',
      });
      final rollsCat = (await database.query(
        'categories',
        where: 'name = ?',
        whereArgs: ['Rolls'],
      ))
          .single['id'] as int;

      final pattyId = await database.insert('raw_materials', {
        'name': 'Veg roll',
        'sub_item': 'Patty',
        'category_id': rollsCat,
        'location_id': 1,
        'listed': 1,
        'created_at': now,
      });

      final vegComboId = await Repository.instance.saveCombo(
        Combo(
          name: 'Veg Roll',
          categoryId: rollsCat,
          price: 100,
          locationId: 1,
        ),
        [ComboRawMaterial(comboId: 0, rawMaterialId: pattyId, qty: 1)],
      );

      final krisperComboId = await Repository.instance.saveCombo(
        Combo(
          name: 'Krisper Roll',
          categoryId: rollsCat,
          price: 90,
          locationId: 1,
        ),
        [ComboRawMaterial(comboId: 0, rawMaterialId: pattyId, qty: 1)],
      );

      await Repository.instance.saveCombo(
        Combo(
          id: krisperComboId,
          name: 'Krisper Roll',
          categoryId: rollsCat,
          price: 110,
          locationId: 1,
        ),
        [ComboRawMaterial(comboId: krisperComboId, rawMaterialId: pattyId, qty: 1)],
      );

      final rows = await database.query('combos', orderBy: 'name ASC');
      expect(rows, hasLength(2));
      final veg = rows.firstWhere((r) => r['id'] == vegComboId);
      final krisper = rows.firstWhere((r) => r['id'] == krisperComboId);
      expect(veg['price'], 100);
      expect(krisper['price'], 110);

      await tearDownStockTestSession(database);
    });

    test('maintainCatalog does not reset manual combo prices via auto-sync',
        () async {
      final database = await openStockTestDatabase();
      bindStockTestSession(database);
      final now = DateTime.now().toIso8601String();

      await database.insert('categories', {
        'name': 'Rolls',
        'type': 'raw_material',
      });
      final rollsCat = (await database.query(
        'categories',
        where: 'name = ?',
        whereArgs: ['Rolls'],
      ))
          .single['id'] as int;

      final menuRowId = await database.insert('raw_materials', {
        'name': 'Veg roll',
        'sub_item': 'Patty',
        'category_id': rollsCat,
        'location_id': 1,
        'selling_price': 0,
        'listed': 1,
        'created_at': now,
      });

      final comboId = await Repository.instance.saveCombo(
        Combo(
          name: 'Veg roll',
          categoryId: rollsCat,
          price: 100,
          locationId: 1,
        ),
        [ComboRawMaterial(comboId: 0, rawMaterialId: menuRowId, qty: 1)],
      );

      await runCatalogMaintenance(SqliteAppDb(database));

      final row = await database.query(
        'combos',
        where: 'id = ?',
        whereArgs: [comboId],
      );
      expect(row.single['price'], 100);

      await tearDownStockTestSession(database);
    });

    test('syncBurgerRollCombos skips existing combos (no price overwrite)',
        () async {
      final database = await openStockTestDatabase();
      final now = DateTime.now().toIso8601String();

      await database.insert('categories', {
        'name': 'Rolls',
        'type': 'raw_material',
      });
      final rollsCat = (await database.query(
        'categories',
        where: 'name = ?',
        whereArgs: ['Rolls'],
      ))
          .single['id'] as int;

      final menuRowId = await database.insert('raw_materials', {
        'name': 'Veg roll',
        'sub_item': 'Patty',
        'category_id': rollsCat,
        'location_id': 1,
        'selling_price': 0,
        'qty_needed': 1,
        'listed': 1,
        'created_at': now,
      });

      final comboId = await database.insert('combos', {
        'name': 'Veg roll',
        'category_id': rollsCat,
        'location_id': 1,
        'price': 100,
        'selling_price': 100,
        'is_active': 1,
        'created_at': now,
      });

      await syncBurgerRollCombos(SqliteAppDb(database));

      final row = await database.query(
        'combos',
        where: 'id = ?',
        whereArgs: [comboId],
      );
      expect(row.single['price'], 100);
      expect(
        await database.query('combos'),
        hasLength(1),
        reason: 'must not recreate deleted auto-combos when one already exists',
      );

      await database.close();
    });
  });
}
