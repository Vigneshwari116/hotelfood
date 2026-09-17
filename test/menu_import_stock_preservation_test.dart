import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/import_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('menu re-import preserves existing live stock', () async {
    final database = await openImportTestDatabase();
    bindImportTestSession(database);

    const seedCsv = '''
category,item_name,sub_item,barcode,qty_per_sale,packets,units_per_packet,unit,opening stock,cost_price,selling_price
SNACKS,Chicken 65,Chicken 65,,8,,90,pc,0,,85
''';

    final service = ItemImportService();
    final firstImport = await service.importCsvText(seedCsv);
    expect(firstImport.errors, isEmpty);

    final items = await Repository.instance.rawMaterials(includeHidden: true);
    expect(items, isNotEmpty);
    final chickenId = items.first.id!;

    await database.update(
      'location_stock',
      {'current_stock': 36, 'opening_stock': 10},
      where: 'location_id = ? AND raw_material_id = ?',
      whereArgs: [1, chickenId],
    );
    await database.update(
      'raw_materials',
      {'current_stock': 36, 'opening_stock': 10, 'selling_price': 99},
      where: 'id = ?',
      whereArgs: [chickenId],
    );

    await service.importCsvText(seedCsv, updateExisting: true);

    final row = await database.query(
      'location_stock',
      where: 'location_id = ? AND raw_material_id = ?',
      whereArgs: [1, chickenId],
    );
    expect((row.first['current_stock'] as num).toDouble(), 36);
    expect((row.first['opening_stock'] as num).toDouble(), 10);

    final item = await Repository.instance.rawMaterialById(chickenId);
    expect(item!.sellingPrice, 85);

    await tearDownImportTestSession(database);
  });
}
