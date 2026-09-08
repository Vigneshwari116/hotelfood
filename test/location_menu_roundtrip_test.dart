import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('location menu import/export round-trip', () {
    late Database database;
    late SqliteAppDb appDb;
    late ItemImportService service;

    const fixturePath =
        'test/fixtures/Shilpa_Enterprise_menu_items_CLIENT_FINAL.xlsx';

    Future<void> openRoundTripDb() async {
      database = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (db, version) async {
          final now = DateTime.now().toIso8601String();
          await db.execute('''
            CREATE TABLE locations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              created_at TEXT NOT NULL
            )
          ''');
          await db.insert('locations', {
            'name': 'Gt world mall',
            'created_at': now,
          });

          await db.execute('''
            CREATE TABLE categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              type TEXT NOT NULL DEFAULT 'raw_material'
            )
          ''');

          await db.execute('''
            CREATE TABLE units (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              short_code TEXT NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE raw_materials (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              barcode TEXT,
              name TEXT NOT NULL,
              sub_item TEXT,
              qty_needed REAL NOT NULL DEFAULT 1,
              category_id INTEGER,
              unit_id INTEGER,
              image_path TEXT,
              opening_stock REAL NOT NULL DEFAULT 0,
              current_stock REAL NOT NULL DEFAULT 0,
              reorder_level REAL NOT NULL DEFAULT 0,
              shelf_life_days INTEGER,
              units_per_packet REAL,
              entry_password_hash TEXT,
              cost_price REAL,
              selling_price REAL,
              listed INTEGER NOT NULL DEFAULT 1,
              menu_sort_order INTEGER,
              menu_export_row TEXT,
              created_at TEXT NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE location_stock (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              location_id INTEGER NOT NULL,
              raw_material_id INTEGER NOT NULL,
              current_stock REAL NOT NULL DEFAULT 0,
              opening_stock REAL NOT NULL DEFAULT 0,
              reorder_level REAL NOT NULL DEFAULT 0,
              UNIQUE(location_id, raw_material_id)
            )
          ''');

          await db.execute('''
            CREATE TABLE stock_batches (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              raw_material_id INTEGER NOT NULL,
              qty_remaining REAL NOT NULL,
              rate REAL,
              expiry_date TEXT,
              purchase_item_id INTEGER,
              location_id INTEGER,
              created_at TEXT NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE stock_ledger (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              raw_material_id INTEGER NOT NULL,
              entry_date TEXT NOT NULL,
              ref_type TEXT NOT NULL,
              ref_id INTEGER,
              qty_in REAL NOT NULL DEFAULT 0,
              qty_out REAL NOT NULL DEFAULT 0,
              unit_cost REAL,
              balance_after REAL NOT NULL,
              location_id INTEGER
            )
          ''');

          await db.execute('''
            CREATE TABLE stock_adjustments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              raw_material_id INTEGER NOT NULL,
              adjust_date TEXT NOT NULL,
              qty REAL NOT NULL,
              reason TEXT,
              location_id INTEGER
            )
          ''');

          await db.execute('''
            CREATE TABLE combo_raw_materials (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              combo_id INTEGER NOT NULL,
              raw_material_id INTEGER NOT NULL,
              qty REAL NOT NULL DEFAULT 1
            )
          ''');

          await db.execute('''
            CREATE TABLE purchase_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              raw_material_id INTEGER
            )
          ''');

          await db.execute('''
            CREATE TABLE sale_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              raw_material_id INTEGER
            )
          ''');
        },
      );

      appDb = SqliteAppDb(database);
      Repository.instance.setAppDbForTesting(appDb);
      Repository.instance.bindSession(
        role: 'location',
        locationId: 1,
        locationName: 'Gt world mall',
      );
      service = ItemImportService();
    }

    tearDown(() async {
      Repository.instance.setAppDbForTesting(null);
      Repository.instance.bindSession(role: 'admin');
      await database.close();
    });

    List<List<String>> normalizedGrid(List<List<String>> rows) {
      if (rows.isEmpty) return rows;
      final width = ItemImportService.menuHeaders.length;
      return rows.map((row) {
        return [
          for (var i = 0; i < width; i++)
            i < row.length ? row[i] : '',
        ];
      }).toList();
    }

    test('export after location import matches client seed row-for-row', () async {
      await openRoundTripDb();

      final seedBytes = await File(fixturePath).readAsBytes();
      final originalRows = service.parseSpreadsheetBytes(seedBytes);

      final tempDir = await Directory.systemTemp.createTemp('menu-import-');
      final importPath = '${tempDir.path}/Gt world mall.xlsx';
      await File(importPath).writeAsBytes(seedBytes);

      final result = await service.importFile(
        importPath,
        expectedLocationName: 'Gt world mall',
      );
      expect(result.errors, isEmpty);

      final exportedBytes = await service.exportXlsxForLocation(1);
      final exportedRows = service.parseSpreadsheetBytes(exportedBytes);

      expect(
        normalizedGrid(exportedRows),
        normalizedGrid(originalRows),
        reason: 'Downloaded menu must match imported client file exactly',
      );
    });

    test('all location template files are byte-identical to client seed', () async {
      final seedBytes =
          await File(fixturePath).readAsBytes();
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
