import 'app_db.dart';
import 'postgres_app_db.dart';

const _migrationName = 'location_menu_catalog_scope_v1';

Future<void> _pgExecute(
  AppDb db,
  String sql, [
  List<Object?>? arguments,
]) async {
  if (db is PostgresAppDb) {
    await db.execute(sql, arguments);
    return;
  }
  await db.rawQuery(sql, arguments);
}

/// Clones legacy shared menu rows into every shop location (Postgres VPS).
Future<void> migrateMenuCatalogToLocationScope(AppDb db) async {
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
          await txn.insert('location_stock', {
            'location_id': locationId,
            'raw_material_id': newId,
            'current_stock': stock['current_stock'],
            'opening_stock': stock['opening_stock'],
            'reorder_level': stock['reorder_level'],
          });
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
          await txn.insert('combo_raw_materials', {
            'combo_id': newComboId,
            'raw_material_id': mappedMaterialId,
            'qty': link['qty'],
          });
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

Future<void> _ensureSchemaMigrationsTable(AppDb db) async {
  await _pgExecute(db, '''
    CREATE TABLE IF NOT EXISTS schema_migrations (
      id INTEGER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
      name TEXT NOT NULL UNIQUE,
      applied_at TEXT NOT NULL
    )
  ''');
}

Future<bool> _migrationApplied(AppDb db, String name) async {
  final rows = await db.query(
    'schema_migrations',
    columns: ['id'],
    where: 'name = ?',
    whereArgs: [name],
    limit: 1,
  );
  return rows.isNotEmpty;
}

Future<void> _recordMigration(AppDb db, String name) async {
  await db.insert('schema_migrations', {
    'name': name,
    'applied_at': DateTime.now().toIso8601String(),
  });
}

Future<void> _recordMigrationTxn(AppDb txn, String name) async {
  await txn.insert('schema_migrations', {
    'name': name,
    'applied_at': DateTime.now().toIso8601String(),
  });
}

Future<void> _createPreMigrationBackups(AppDb db) async {
  await db.transaction((txn) async {
    await _pgExecute(txn, 'DROP TABLE IF EXISTS raw_materials_pre_migration_backup');
    await _pgExecute(
      txn,
      'CREATE TABLE raw_materials_pre_migration_backup AS '
      'SELECT * FROM raw_materials',
    );

    await _pgExecute(txn, 'DROP TABLE IF EXISTS combos_pre_migration_backup');
    await _pgExecute(
      txn,
      'CREATE TABLE combos_pre_migration_backup AS SELECT * FROM combos',
    );

    await _pgExecute(
      txn,
      'DROP TABLE IF EXISTS combo_raw_materials_pre_migration_backup',
    );
    await _pgExecute(
      txn,
      'CREATE TABLE combo_raw_materials_pre_migration_backup AS '
      'SELECT * FROM combo_raw_materials',
    );

    final comboItems = await txn.rawQuery('''
      SELECT table_name FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = 'combo_items'
    ''');
    if (comboItems.isNotEmpty) {
      await _pgExecute(
        txn,
        'DROP TABLE IF EXISTS combo_items_pre_migration_backup',
      );
      await _pgExecute(
        txn,
        'CREATE TABLE combo_items_pre_migration_backup AS '
        'SELECT * FROM combo_items',
      );
    }
  });
}

/// Legacy schema enforced globally unique combo names and barcodes. Per-location
/// clones need the same display names/barcodes at each shop.
Future<void> _relaxGlobalMenuUniqueConstraintsForLocationClone(AppDb txn) async {
  await _pgExecute(
    txn,
    'ALTER TABLE raw_materials DROP CONSTRAINT IF EXISTS raw_materials_barcode_key',
  );
  await _pgExecute(
    txn,
    'ALTER TABLE combos DROP CONSTRAINT IF EXISTS combos_name_key',
  );
  await _pgExecute(
    txn,
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_combos_location_name '
    'ON combos (location_id, name)',
  );
}

Future<void> _remapTransactionalMaterialIds(
  AppDb txn, {
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

    await txn.rawQuery(
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

    await txn.rawQuery(
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
  AppDb txn, {
  required int locationId,
  required Map<int, int> comboIdMap,
}) async {
  for (final entry in comboIdMap.entries) {
    final oldId = entry.key;
    final newId = entry.value;

    await txn.rawQuery(
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

Future<void> _ensureLocationColumns(AppDb db) async {
  await _pgExecute(
    db,
    'ALTER TABLE raw_materials ADD COLUMN IF NOT EXISTS location_id INTEGER '
    'REFERENCES locations (id)',
  );
  await _pgExecute(
    db,
    'ALTER TABLE combos ADD COLUMN IF NOT EXISTS location_id INTEGER '
    'REFERENCES locations (id)',
  );
  await _pgExecute(
    db,
    'CREATE INDEX IF NOT EXISTS idx_raw_materials_location '
    'ON raw_materials (location_id)',
  );
  await _pgExecute(
    db,
    'CREATE INDEX IF NOT EXISTS idx_combos_location ON combos (location_id)',
  );
  await _pgExecute(db, '''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_raw_materials_location_barcode
    ON raw_materials (location_id, barcode)
    WHERE barcode IS NOT NULL AND trim(barcode::text) <> ''
  ''');
}
