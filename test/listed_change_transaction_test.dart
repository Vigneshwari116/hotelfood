import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/listed_change_source.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/import_test_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('hideRawMaterial requires a declared source and logs the change', () async {
    final database = await openImportTestDatabase();
    bindImportTestSession(database);
    final now = DateTime.now().toIso8601String();

    final id = await database.insert('raw_materials', {
      'name': 'Krusty Bites',
      'sub_item': 'Krusty Bites',
      'listed': 1,
      'barcode': 'KB1',
      'current_stock': 0,
      'opening_stock': 0,
      'created_at': now,
    });

    await Repository.instance.hideRawMaterial(
      id,
      source: ListedChangeSource.importVariantDedup,
    );

    final row = (await database.query(
      'raw_materials',
      where: 'id = ?',
      whereArgs: [id],
    ))
        .single;
    expect(row['listed'], 0);
    expect(row['barcode'], isNull);

    final logs = await database.query(
      'inventory_save_log',
      where: 'operation LIKE ?',
      whereArgs: ['listed_change:%'],
    );
    expect(logs, isNotEmpty);
    expect(logs.first['operation'], 'listed_change:import_variant_dedup');

    await tearDownImportTestSession(database);
  });

  test('unlistRawMaterial clears listed without clearing barcode', () async {
    final database = await openImportTestDatabase();
    bindImportTestSession(database);
    final now = DateTime.now().toIso8601String();

    final id = await database.insert('raw_materials', {
      'name': 'Crunchy Masala Big Bucket',
      'sub_item': 'Crunchy Masala',
      'listed': 1,
      'barcode': 'KEEP',
      'current_stock': 0,
      'opening_stock': 0,
      'created_at': now,
    });

    await Repository.instance.unlistRawMaterial(
      id,
      source: ListedChangeSource.importCatalogDedupName,
    );

    final row = (await database.query(
      'raw_materials',
      where: 'id = ?',
      whereArgs: [id],
    ))
        .single;
    expect(row['listed'], 0);
    expect(row['barcode'], 'KEEP');

    await tearDownImportTestSession(database);
  });

  test('setRawMaterialListed runs in a transaction with source', () async {
    final database = await openImportTestDatabase();
    bindImportTestSession(database);
    final now = DateTime.now().toIso8601String();

    final id = await database.insert('raw_materials', {
      'name': 'Crunchy Masala Big Bucket',
      'sub_item': 'Crunchy Masala',
      'listed': 1,
      'current_stock': 0,
      'opening_stock': 0,
      'created_at': now,
    });

    await Repository.instance.setRawMaterialListed(
      id,
      false,
      source: ListedChangeSource.userToggle,
    );

    final row = (await database.query(
      'raw_materials',
      where: 'id = ?',
      whereArgs: [id],
    ))
        .single;
    expect(row['listed'], 0);

    await tearDownImportTestSession(database);
  });
}
