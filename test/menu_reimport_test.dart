import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'support/menu_item_import.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/import_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database database;

  const seedMenuCsv = '''
category,item_name,sub_item,barcode,qty_per_sale,packets,units_per_packet,unit,opening stock,cost_price,selling_price
SNACKS,Chicken 65,Chicken 65,,1,,,pc,0,,85
SNACKS,French Fries,French Fries Small,,80,,,g,0,,50
''';

  Future<void> openImportDb() async {
    database = await openImportTestDatabase();
    bindImportTestSession(database);
  }

  tearDown(() async {
    await tearDownImportTestSession(database);
  });

  RawMaterial? findItem(List<RawMaterial> items, String name) {
    return items.cast<RawMaterial?>().firstWhere(
      (item) => item!.name == name,
      orElse: () => null,
    );
  }

  group('location menu re-import', () {
    test('re-import overwrites manual price edits with Excel values', () async {
      await openImportDb();
      final service = MenuItemImportService();

      await service.importCsvText(seedMenuCsv);

      final afterSeed = await Repository.instance.rawMaterials(includeHidden: true);
      final chicken65 = findItem(afterSeed, 'Chicken 65');
      expect(chicken65, isNotNull);
      expect(chicken65!.sellingPrice, 85);

      await Repository.instance.saveRawMaterial(
        RawMaterial(
          id: chicken65!.id,
          name: chicken65.name,
          subItem: chicken65.subItem,
          qtyNeeded: chicken65.qtyNeeded,
          categoryId: chicken65.categoryId,
          unitId: chicken65.unitId,
          openingStock: chicken65.openingStock,
          currentStock: chicken65.currentStock,
          sellingPrice: 99,
          listed: chicken65.listed,
          createdAt: chicken65.createdAt,
        ),
      );

      final afterManualEdit =
          await Repository.instance.rawMaterials(includeHidden: true);
      expect(findItem(afterManualEdit, 'Chicken 65')!.sellingPrice, 99);

      final reimport = await service.importCsvText(
        seedMenuCsv,
        updateExisting: true,
      );
      expect(reimport.updated, greaterThan(0));

      final afterReimport =
          await Repository.instance.rawMaterials(includeHidden: true);
      expect(
        findItem(afterReimport, 'Chicken 65')!.sellingPrice,
        85,
        reason: 'Location re-import updates matching rows from Excel',
      );
    });

    test('re-import does not delete items missing from the Excel file', () async {
      await openImportDb();
      final service = MenuItemImportService();

      await service.importCsvText(seedMenuCsv, updateExisting: true);

      final extraId = await Repository.instance.saveRawMaterial(
        RawMaterial(
          name: 'Staff Only Item',
          subItem: 'Staff Only Item',
          qtyNeeded: 1,
          openingStock: 0,
          currentStock: 0,
          sellingPrice: 25,
          listed: true,
        ),
      );
      expect(extraId, greaterThan(0));

      final before = await Repository.instance.rawMaterials(includeHidden: true);
      expect(before.any((item) => item.name == 'Staff Only Item'), isTrue);
      expect(before.length, 3);

      await service.importCsvText(
        seedMenuCsv,
        updateExisting: true,
      );

      final after = await Repository.instance.rawMaterials(includeHidden: true);
      expect(after.any((item) => item.name == 'Staff Only Item'), isTrue);
      expect(after.length, 3);
    });

    test('location importFile uses merge mode (replaceCatalog false)', () async {
      await openImportDb();
      final service = MenuItemImportService();

      await service.importCsvText(seedMenuCsv);
      await Repository.instance.saveRawMaterial(
        RawMaterial(
          name: 'Only In App',
          subItem: 'Only In App',
          qtyNeeded: 1,
          openingStock: 0,
          currentStock: 0,
          sellingPrice: 40,
        ),
      );

      final result = await service.importCsvText(
        seedMenuCsv,
        updateExisting: true,
        replaceCatalog: false,
      );

      final items = await Repository.instance.rawMaterials(includeHidden: true);
      expect(items.any((item) => item.name == 'Only In App'), isTrue);
      expect(result.updated, greaterThan(0));
    });

    test('replaceCatalog true hides leftovers when delete is blocked', () async {
      await openImportDb();
      final service = MenuItemImportService();

      await service.importCsvText(seedMenuCsv);
      final onlyInAppId = await Repository.instance.saveRawMaterial(
        RawMaterial(
          name: 'Only In App',
          subItem: 'Only In App',
          qtyNeeded: 1,
          openingStock: 0,
          currentStock: 0,
          sellingPrice: 40,
        ),
      );
      await database.insert('sale_items', {
        'raw_material_id': onlyInAppId,
      });

      await service.importCsvText(
        seedMenuCsv,
        updateExisting: true,
        replaceCatalog: true,
      );

      final items = await Repository.instance.rawMaterials(includeHidden: true);
      final orphan = items.where((item) => item.name == 'Only In App').toList();
      expect(orphan, hasLength(1));
      expect(
        orphan.first.listed,
        isFalse,
        reason: 'Leftover items are hidden when hard delete is not possible',
      );
      expect(items.where((item) => item.listed).length, 2);
    });
  });
}
