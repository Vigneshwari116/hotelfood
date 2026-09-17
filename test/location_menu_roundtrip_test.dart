import 'dart:convert';
import 'dart:io';

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

  group('location menu import/export round-trip', () {
    late Database database;
    late ItemImportService service;

    const approvedMasterPath =
        'assets/templates/shilpa_enterprise_menu_1401.csv';
    const fixturePath =
        'test/fixtures/Shilpa_Enterprise_menu_items_CLIENT_FINAL.xlsx';

    Future<void> openRoundTripDb() async {
      database = await openImportTestDatabase();
      bindImportTestSession(database);
      service = ItemImportService();
    }

    tearDown(() async {
      await tearDownImportTestSession(database);
    });

    List<List<String>> normalizedGrid(List<List<String>> rows) {
      if (rows.isEmpty) return rows;
      final width = ItemImportService.gridExportHeaders.length;
      return rows
          .map((row) {
            return [
              for (var i = 0; i < width; i++)
                i < row.length ? row[i] : '',
            ];
          })
          .where((row) {
            if (row.isEmpty) return false;
            final itemName = row.length > 2 ? row[2].trim() : '';
            if (itemName.isEmpty) return false;
            if (row.first.trim().toLowerCase() == 'category' &&
                itemName.toLowerCase() == 'item_name') {
              return false;
            }
            return true;
          })
          .toList();
    }

    test(
      'export after location import produces a non-empty menu grid',
      () async {
        await openRoundTripDb();

        final approvedCsv = await File(approvedMasterPath).readAsString();
        final tempDir = await Directory.systemTemp.createTemp('menu-import-');
        final importPath = '${tempDir.path}/Gt world mall.csv';
        await File(importPath).writeAsString(approvedCsv);

        final result = await service.importFile(
          importPath,
          expectedLocationName: 'Gt world mall',
        );
        expect(result.errors, isEmpty);

        final exportedBytes = await service.exportXlsxForLocation(1);
        final exportedRows = service.parseSpreadsheetBytes(exportedBytes);
        final normalized = normalizedGrid(exportedRows);

        expect(normalized, isNotEmpty);
        expect(
          normalized.any(
            (row) => row.any(
              (cell) => cell.toLowerCase().contains('chicken 65'),
            ),
          ),
          isTrue,
          reason: 'Approved master import must export core menu rows',
        );
      },
    );

    test('all location template files are byte-identical to client seed', () async {
      final seedBytes = await File(fixturePath).readAsBytes();
      for (final name in [
        'Gt world mall',
        'Magadi road',
        'Subbanna garden',
      ]) {
        final path = 'assets/templates/locations/$name.xlsx';
        final bytes = await File(path).readAsBytes();
        expect(
          bytes,
          seedBytes,
          reason: '$name.xlsx must be an exact copy of the client seed',
        );
      }
    });
  });
}
