import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/database/sqlite_app_db.dart';
import 'package:foodstock/services/app_bootstrap.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('startup bootstrap', () {
    test('does not auto-import bundled menus on launch', () {
      final source = File('lib/services/app_bootstrap.dart').readAsStringSync();
      expect(source.contains('menuSeedVersion'), isFalse);
      expect(source.contains('locationMenuSeed'), isFalse);
      expect(source.contains('importCsvText'), isFalse);
      expect(source.contains('importXlsxBytes'), isFalse);
      expect(source.contains('rootBundle'), isFalse);
    });

    test('essential user seeding stays fast with a large catalog', () async {
      final database = await openDatabase(
        '${inMemoryDatabasePath}_essential_seed',
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
          await db.execute('''
            CREATE TABLE users (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              username TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL,
              role TEXT NOT NULL DEFAULT 'admin',
              location_id INTEGER,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE raw_materials (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              reorder_level REAL NOT NULL DEFAULT 0,
              opening_stock REAL NOT NULL DEFAULT 0,
              current_stock REAL NOT NULL DEFAULT 0,
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

          for (var i = 1; i <= 3; i++) {
            await db.insert('locations', {
              'name': 'Location $i',
              'created_at': now,
            });
          }

          final batch = db.batch();
          for (var i = 1; i <= 500; i++) {
            batch.insert('raw_materials', {
              'name': 'Menu item $i',
              'reorder_level': 0,
              'opening_stock': 0,
              'current_stock': 0,
              'created_at': now,
            });
          }
          await batch.commit(noResult: true);
        },
      );

      final appDb = SqliteAppDb(database);
      Repository.instance.setAppDbForTesting(appDb);
      addTearDown(() async {
        Repository.instance.setAppDbForTesting(null);
        await database.close();
      });

      final stopwatch = Stopwatch()..start();
      await Repository.instance.ensureDefaultUsers();
      stopwatch.stop();

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(2000),
        reason: 'Login should not wait for per-location stock sync '
            '(500 items x 3 locations).',
      );
    });

    test('location stock sync runs in deferred init and stays bounded', () async {
      final database = await openDatabase(
        '${inMemoryDatabasePath}_location_stock',
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
          await db.execute('''
            CREATE TABLE raw_materials (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              reorder_level REAL NOT NULL DEFAULT 0,
              opening_stock REAL NOT NULL DEFAULT 0,
              current_stock REAL NOT NULL DEFAULT 0,
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

          for (var i = 1; i <= 3; i++) {
            await db.insert('locations', {
              'name': 'Location $i',
              'created_at': now,
            });
          }

          final batch = db.batch();
          for (var i = 1; i <= 500; i++) {
            batch.insert('raw_materials', {
              'name': 'Menu item $i',
              'reorder_level': 0,
              'opening_stock': 0,
              'current_stock': 0,
              'created_at': now,
            });
          }
          await batch.commit(noResult: true);
        },
      );

      final appDb = SqliteAppDb(database);
      Repository.instance.setAppDbForTesting(appDb);
      addTearDown(() async {
        Repository.instance.setAppDbForTesting(null);
        await database.close();
      });

      final stopwatch = Stopwatch()..start();
      await Repository.instance.ensureLocationStockRows();
      stopwatch.stop();

      final locationRows =
          await database.rawQuery('SELECT COUNT(*) AS cnt FROM locations');
      final materialRows =
          await database.rawQuery('SELECT COUNT(*) AS cnt FROM raw_materials');
      final locationCount = (locationRows.first['cnt'] as num).toInt();
      final materialCount = (materialRows.first['cnt'] as num).toInt();
      final rows =
          await database.rawQuery('SELECT COUNT(*) AS cnt FROM location_stock');
      expect((rows.first['cnt'] as num).toInt(), locationCount * materialCount);
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(5000),
        reason: 'Bulk location stock sync should finish quickly even '
            'with 500 items x 3 locations.',
      );
    });

    test('deferred init includes location stock sync after first frame path', () {
      final source = File('lib/services/app_bootstrap.dart').readAsStringSync();
      final essential = source.substring(
        source.indexOf('runEssentialInit'),
        source.indexOf('runDeferredInit'),
      );
      final deferred = source.substring(source.indexOf('runDeferredInit'));

      expect(essential.contains('ensureLocationStockRows'), isFalse);
      expect(deferred.contains('ensureLocationStockRows'), isTrue);
      expect(deferred.contains('writeOffExpiredStock'), isTrue);
    });
  });
}
