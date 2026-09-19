import 'package:sqflite/sqflite.dart';

/// Adds per-location menu catalogs (raw materials + combos) and clones legacy
/// shared rows into every shop location.
Future<void> migrateMenuCatalogToLocationScope(Database db) async {
  await _ensureLocationColumns(db);

  final already = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM raw_materials WHERE location_id IS NOT NULL',
  );
  if (((already.first['c'] as num?)?.toInt() ?? 0) > 0) {
    return;
  }

  final locations = await db.query('locations', orderBy: 'id ASC');
  if (locations.isEmpty) {
    return;
  }

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

    for (var locIndex = 1; locIndex < locations.length; locIndex++) {
      final locationId = locations[locIndex]['id'] as int;
      final idMap = <int, int>{};

      for (final row in legacyMaterials) {
        final oldId = row['id'] as int;
        final copy = Map<String, Object?>.from(row)
          ..remove('id')
          ..['location_id'] = locationId
          ..['stock_source_id'] = null;
        final newId = await txn.insert('raw_materials', copy);
        idMap[oldId] = newId;

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

      for (final entry in idMap.entries) {
        final oldRow = legacyMaterials.firstWhere(
          (row) => row['id'] == entry.key,
        );
        final oldSource = oldRow['stock_source_id'] as int?;
        if (oldSource == null) continue;
        final mapped = idMap[oldSource];
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

        final links = await txn.query(
          'combo_raw_materials',
          where: 'combo_id = ?',
          whereArgs: [oldComboId],
        );
        for (final link in links) {
          final oldMaterialId = link['raw_material_id'] as int;
          final mappedMaterialId = idMap[oldMaterialId];
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
    }
  });
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
