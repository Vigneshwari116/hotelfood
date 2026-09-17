import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
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

  group('menu import with blank selling price', () {
    late Database database;
    late ItemImportService service;

    const fixturePath =
        'test/fixtures/Shilpa_Enterprise_menu_items_CLIENT_FINAL.xlsx';

    Future<void> openDb() async {
      database = await openImportTestDatabase();
      bindImportTestSession(database);
      service = ItemImportService();
    }

    tearDown(() async {
      await tearDownImportTestSession(database);
    });

    test('imports all rows including blank-price items from client menu',
        () async {
      await openDb();

      final seedBytes = await File(fixturePath).readAsBytes();
      final tempDir = await Directory.systemTemp.createTemp('menu-import-');
      final importPath = '${tempDir.path}/Gt world mall.xlsx';
      await File(importPath).writeAsBytes(seedBytes);

      final result = await service.importFile(
        importPath,
        expectedLocationName: 'Gt world mall',
      );

      expect(
        result.errors,
        isEmpty,
        reason: 'Client menu import must complete without row errors',
      );

      final items =
          await Repository.instance.rawMaterials(includeHidden: true);

      RawMaterial? findByName(String name) {
        for (final item in items) {
          if (item.name == name) return item;
        }
        return null;
      }

      final vegRoll = findByName('Veg roll');
      expect(vegRoll, isNotNull);
      expect(vegRoll!.sellingPrice, isNull);
      expect(
        vegRoll.listed,
        isFalse,
        reason: 'Roll rows sync to combos and are hidden from direct POS sales',
      );
      expect(vegRoll.barcode, isNull);

      final pricedRoll = findByName('Chicken roll');
      expect(pricedRoll, isNotNull);
      expect(pricedRoll!.sellingPrice, 75);
      expect(
        pricedRoll.listed,
        isFalse,
        reason: 'Roll rows sync to combos and are hidden from direct POS sales',
      );
    });
  });
}
