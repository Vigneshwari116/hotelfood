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

  test('running the same import twice does not duplicate rows or stock', () async {
    final database = await openImportTestDatabase();
    bindImportTestSession(database);

    const seedCsv = '''
category,item_name,sub_item,barcode,qty_per_sale,packets,units_per_packet,unit,opening stock,cost_price,selling_price
SNACKS,Chicken 65,Chicken 65,,8,,90,pc,50,,85
''';

    final service = ItemImportService();

    final first = await service.importCsvText(seedCsv);
    expect(first.errors, isEmpty);

    final itemsAfterFirst =
        await Repository.instance.rawMaterials(includeHidden: true);
    expect(itemsAfterFirst.length, 1);
    final id = itemsAfterFirst.first.id!;

    final stockAfterFirst = (await database.query(
      'location_stock',
      where: 'raw_material_id = ?',
      whereArgs: [id],
    ))
        .single;
    expect((stockAfterFirst['current_stock'] as num).toDouble(), 50);

    final second = await service.importCsvText(seedCsv, updateExisting: true);
    expect(second.errors, isEmpty);
    expect(
      second.warnings.any((w) => w.contains('post-processing')),
      isTrue,
      reason: 'Second import should skip duplicate maintenance',
    );

    final itemsAfterSecond =
        await Repository.instance.rawMaterials(includeHidden: true);
    expect(itemsAfterSecond.length, 1);

    final stockAfterSecond = (await database.query(
      'location_stock',
      where: 'raw_material_id = ?',
      whereArgs: [id],
    ))
        .single;
    expect((stockAfterSecond['current_stock'] as num).toDouble(), 50);

    final batchRows = await database.query('menu_import_batches');
    expect(batchRows.length, 1);

    await tearDownImportTestSession(database);
  });
}
