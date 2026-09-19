import 'package:sqflite/sqflite.dart';

const _migrationName = 'location_menu_catalog_scope_v1';

/// Adds per-location menu catalogs (raw materials + combos), clones legacy
/// shared rows into every shop location, and remaps transactional FKs for
/// locations other than the lowest [locations.id].
Future<void> migrateMenuCatalogToLocationScope(Database db) async {
  await _ensureSchemaMigrationsTable(db);
  if (await _migrationApplied(db, _migrationName)) {
    return;
  }

  await _ensureLocationColumns(db);

  final locations = await db.query('locations', orderBy: 'id ASC');
  if (locations.isEmpty) {
    await _recordMigration(db, _migrationName);
    return;
  }

  await _createPreMigrationBackups(db);

  await db.transaction((txn) async {
    final legacyMaterials = await txn.query(
      'raw_materials',
      orderBy: 'id ASC',
    );
    final legacyCombos = await txn.query(
      'combos',
      orderBy: 'id ASC',
    );

    if (legacyMaterials.isEmpty && legacyCombos.isEmpty) {
      final firstLoc = locations.first['id'] as int;
      await txn.update(
        'raw_materials',
        {'location_id': firstLoc},
        where: 'location_id IS NULL',
      );
      await txn.update(
        'combos',
        {'location_id': firstLoc},
        where: 'location_id IS NULL',
      );
      await _recordMigrationTxn(txn, _migrationName);
      return;
    }

    final firstLocationId = locations.first['id'] as int;
    await txn.update(
      'raw_materials',
      {'location_id': firstLocationId},
      where: 'location_id IS NULL',
    );
    await txn.update(
      'combos',
      {'location_id': firstLocationId},
      where: 'location_id IS NULL',
    );

    await _relaxGlobalMenuUniqueConstraintsForLocationClone(txn);

    for (var locIndex = 1; locIndex < locations.length; locIndex++) {
      final locationId = locations[locIndex]['id'] as int;
      final materialIdMap = <int, int>{};
      final comboIdMap = <int, int>{};

      for (final row in legacyMaterials) {
        final oldId = row['id'] as int;
        final copy = Map<String, Object?>.from(row)
          ..remove('id')
          ..['location_id'] = locationId
          ..['stock_source_id'] = null;
        final newId = await txn.insert('raw_materials', copy);
        materialIdMap[oldId] = newId;

        final stockRows = await txn.query(
          'location_stock',
          where: 'location_id = ? AND raw_material_id = ?',
          whereArgs: [locationId, oldId],
        );
        for (final stock in stockRows) {
          await txn.insert(
            'location_stock',
            {
              'location_id': locationId,
              'raw_material_id': newId,
              'current_stock': stock['current_stock'],
              'opening_stock': stock['opening_stock'],
              'reorder_level': stock['reorder_level'],
            },
          );
          await txn.delete(
            'location_stock',
            where: 'id = ?',
            whereArgs: [stock['id']],
          );
        }
      }

      for (final entry in materialIdMap.entries) {
        final oldRow = legacyMaterials.firstWhere(
          (row) => row['id'] == entry.key,
        );
        final oldSource = oldRow['stock_source_id'] as int?;
        if (oldSource == null) continue;
        final mapped = materialIdMap[oldSource];
        if (mapped == null) continue;
        await txn.update(
          'raw_materials',
          {'stock_source_id': mapped},
          where: 'id = ?',
          whereArgs: [entry.value],
        );
      }

      for (final combo in legacyCombos) {
        final oldComboId = combo['id'] as int;
        final comboCopy = Map<String, Object?>.from(combo)
          ..remove('id')
          ..['location_id'] = locationId;
        final newComboId = await txn.insert('combos', comboCopy);
        comboIdMap[oldComboId] = newComboId;

        final links = await txn.query(
          'combo_raw_materials',
          where: 'combo_id = ?',
          whereArgs: [oldComboId],
        );
        for (final link in links) {
          final oldMaterialId = link['raw_material_id'] as int;
          final mappedMaterialId = materialIdMap[oldMaterialId];
          if (mappedMaterialId == null) continue;
          await txn.insert(
            'combo_raw_materials',
            {
              'combo_id': newComboId,
              'raw_material_id': mappedMaterialId,
              'qty': link['qty'],
            },
          );
        }
      }

      await _remapTransactionalMaterialIds(
        txn,
        locationId: locationId,
        materialIdMap: materialIdMap,
      );
      await _remapTransactionalComboIds(
        txn,
        locationId: locationId,
        comboIdMap: comboIdMap,
      );
    }

    await _recordMigrationTxn(txn, _migrationName);
  });
}

Future<void> _ensureSchemaMigrationsTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS schema_migrations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      applied_at TEXT NOT NULL
    )
  ''');
}

Future<bool> _migrationApplied(Database db, String name) async {
  final rows = await db.query(
    'schema_migrations',
    columns: ['id'],
    where: 'name = ?',
    whereArgs: [name],
    limit: 1,
  );
  return rows.isNotEmpty;
}

Future<void> _recordMigration(Database db, String name) async {
  await db.insert('schema_migrations', {
    'name': name,
    'applied_at': DateTime.now().toIso8601String(),
  });
}

Future<void> _recordMigrationTxn(DatabaseExecutor txn, String name) async {
  await txn.insert('schema_migrations', {
    'name': name,
    'applied_at': DateTime.now().toIso8601String(),
  });
}

Future<void> _createPreMigrationBackups(Database db) async {
  await db.transaction((txn) async {
    await txn.execute('DROP TABLE IF EXISTS raw_materials_pre_migration_backup');
    await txn.execute(
      'CREATE TABLE raw_materials_pre_migration_backup AS '
      'SELECT * FROM raw_materials',
    );

    await txn.execute('DROP TABLE IF EXISTS combos_pre_migration_backup');
    await txn.execute(
      'CREATE TABLE combos_pre_migration_backup AS SELECT * FROM combos',
    );

    await txn.execute(
      'DROP TABLE IF EXISTS combo_raw_materials_pre_migration_backup',
    );
    await txn.execute(
      'CREATE TABLE combo_raw_materials_pre_migration_backup AS '
      'SELECT * FROM combo_raw_materials',
    );

    final comboItems = await txn.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type='table' AND name='combo_items'",
    );
    if (comboItems.isNotEmpty) {
      await txn.execute('DROP TABLE IF EXISTS combo_items_pre_migration_backup');
      await txn.execute(
        'CREATE TABLE combo_items_pre_migration_backup AS '
        'SELECT * FROM combo_items',
      );
    }
  });
}

Future<void> _remapTransactionalMaterialIds(
  DatabaseExecutor txn, {
  required int locationId,
  required Map<int, int> materialIdMap,
}) async {
  for (final entry in materialIdMap.entries) {
    final oldId = entry.key;
    final newId = entry.value;

    await txn.update(
      'stock_ledger',
      {'raw_material_id': newId},
      where: 'location_id = ? AND raw_material_id = ?',
      whereArgs: [locationId, oldId],
    );

    await txn.update(
      'stock_batches',
      {'raw_material_id': newId},
      where: 'location_id = ? AND raw_material_id = ?',
      whereArgs: [locationId, oldId],
    );

    await txn.update(
      'stock_adjustments',
      {'raw_material_id': newId},
      where: 'location_id = ? AND raw_material_id = ?',
      whereArgs: [locationId, oldId],
    );

    await txn.rawUpdate(
      '''
      UPDATE purchase_items
      SET raw_material_id = ?
      WHERE raw_material_id = ?
        AND purchase_id IN (
          SELECT id FROM purchases WHERE location_id = ?
        )
      ''',
      [newId, oldId, locationId],
    );

    await txn.rawUpdate(
      '''
      UPDATE sale_items
      SET raw_material_id = ?
      WHERE raw_material_id = ?
        AND sale_id IN (
          SELECT id FROM sales WHERE location_id = ?
        )
      ''',
      [newId, oldId, locationId],
    );
  }
}

Future<void> _remapTransactionalComboIds(
  DatabaseExecutor txn, {
  required int locationId,
  required Map<int, int> comboIdMap,
}) async {
  for (final entry in comboIdMap.entries) {
    final oldId = entry.key;
    final newId = entry.value;

    await txn.rawUpdate(
      '''
      UPDATE sale_items
      SET combo_id = ?
      WHERE combo_id = ?
        AND sale_id IN (
          SELECT id FROM sales WHERE location_id = ?
        )
      ''',
      [newId, oldId, locationId],
    );
  }
}

/// Recreates menu tables without legacy global UNIQUE constraints (SQLite
/// cannot DROP autoindexes backing UNIQUE columns).
Future<void> _relaxGlobalMenuUniqueConstraintsForLocationClone(
  DatabaseExecutor txn,
) async {
  await txn.execute('PRAGMA foreign_keys = OFF');

  await txn.execute('''
    CREATE TABLE raw_materials__loc_scope (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      barcode TEXT,
      name TEXT NOT NULL,
      sub_item TEXT,
      qty_needed REAL NOT NULL DEFAULT 1,
      category_id INTEGER,
      unit_id INTEGER,
      image_path TEXT,
      opening_stock REAL NOT NULL DEFAULT 0,
      opening_pieces REAL NOT NULL DEFAULT 0,
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
      variant_group TEXT,
      variant_label TEXT,
      stock_source_id INTEGER,
      location_id INTEGER,
      created_at TEXT NOT NULL
    )
  ''');
  await txn.execute('''
    INSERT INTO raw_materials__loc_scope SELECT * FROM raw_materials
  ''');
  await txn.execute('DROP TABLE raw_materials');
  await txn.execute(
    'ALTER TABLE raw_materials__loc_scope RENAME TO raw_materials',
  );

  await txn.execute('''
    CREATE TABLE combos__loc_scope (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      barcode TEXT,
      price REAL NOT NULL DEFAULT 0,
      selling_price REAL NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      category_id INTEGER,
      image_path TEXT,
      location_id INTEGER,
      created_at TEXT NOT NULL
    )
  ''');
  await txn.execute('''
    INSERT INTO combos__loc_scope (
      id, name, barcode, price, selling_price, is_active,
      category_id, image_path, location_id, created_at
    )
    SELECT
      id, name, barcode, price, selling_price, is_active,
      category_id, image_path, location_id, created_at
    FROM combos
  ''');
  await txn.execute('DROP TABLE combos');
  await txn.execute('ALTER TABLE combos__loc_scope RENAME TO combos');

  await txn.execute('PRAGMA foreign_keys = ON');

  await txn.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_combos_location_name '
    'ON combos (location_id, name)',
  );
  await txn.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_raw_materials_location_barcode '
    'ON raw_materials (location_id, barcode) '
    "WHERE barcode IS NOT NULL AND trim(barcode) <> ''",
  );
}

Future<void> _ensureLocationColumns(Database db) async {
  final materialInfo = await db.rawQuery('PRAGMA table_info(raw_materials)');
  final materialNames = materialInfo
      .map((row) => row['name']?.toString() ?? '')
      .toSet();
  if (!materialNames.contains('location_id')) {
    await db.execute(
      'ALTER TABLE raw_materials ADD COLUMN location_id INTEGER '
      'REFERENCES locations (id)',
    );
  }

  final comboInfo = await db.rawQuery('PRAGMA table_info(combos)');
  final comboNames =
      comboInfo.map((row) => row['name']?.toString() ?? '').toSet();
  if (!comboNames.contains('location_id')) {
    await db.execute(
      'ALTER TABLE combos ADD COLUMN location_id INTEGER '
      'REFERENCES locations (id)',
    );
  }

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_raw_materials_location '
    'ON raw_materials (location_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_combos_location ON combos (location_id)',
  );
  await db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_raw_materials_location_barcode '
    'ON raw_materials (location_id, barcode) '
    'WHERE barcode IS NOT NULL AND trim(barcode) <> \'\'',
  );
}
