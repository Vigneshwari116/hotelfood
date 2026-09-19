import 'package:sqflite/sqflite.dart';

import 'menu_catalog_match.dart';

/// One-time fix: cloned rows at locations 2+ lost [listed=1] after global dedup.
const listedLocationCloneRepairV1 = 'listed_location_clone_repair_v1';

class ListedLocationCloneRepairResult {
  const ListedLocationCloneRepairResult({
    required this.templateLocationId,
    required this.materialRowsUpdated,
    required this.comboRowsUpdated,
    required this.mismatchedListedAfter,
  });

  final int templateLocationId;
  final int materialRowsUpdated;
  final int comboRowsUpdated;
  final int mismatchedListedAfter;
}

Future<int> templateLocationId(DatabaseExecutor db) async {
  final rows = await db.query(
    'locations',
    columns: ['id'],
    orderBy: 'id ASC',
    limit: 1,
  );
  if (rows.isEmpty) return 1;
  return (rows.first['id'] as num).toInt();
}

/// Rows at non-template locations whose [listed] differs from the template match.
Future<int> countListedMismatchesAgainstTemplate(DatabaseExecutor db) async {
  final templateId = await templateLocationId(db);
  final match = rawMaterialCatalogMatchSql(
    targetAlias: 'target',
    sourceAlias: 'source',
  );
  final rows = await db.rawQuery(
    '''
    SELECT COUNT(*) AS c
    FROM raw_materials target
    JOIN raw_materials source
      ON source.location_id = ?
      AND $match
    WHERE target.location_id IS NOT NULL
      AND target.location_id != ?
      AND target.listed != source.listed
    ''',
    [templateId, templateId],
  );
  return (rows.first['c'] as num?)?.toInt() ?? 0;
}

Future<ListedLocationCloneRepairResult> migrateListedLocationCloneRepair(
  Database db,
) async {
  await _ensureSchemaMigrationsTable(db);
  if (await _migrationApplied(db, listedLocationCloneRepairV1)) {
    final templateId = await templateLocationId(db);
    final remaining = await countListedMismatchesAgainstTemplate(db);
    return ListedLocationCloneRepairResult(
      templateLocationId: templateId,
      materialRowsUpdated: 0,
      comboRowsUpdated: 0,
      mismatchedListedAfter: remaining,
    );
  }

  return db.transaction((txn) async {
    final templateId = await templateLocationId(txn);
    final materialMatch = rawMaterialCatalogMatchSql(
      targetAlias: 'target',
      sourceAlias: 'source',
    );
    final comboMatch = comboCatalogMatchSql(
      targetAlias: 'target',
      sourceAlias: 'source',
    );

    final materialsUpdated = await txn.rawUpdate(
      '''
      UPDATE raw_materials AS target
      SET listed = (
        SELECT source.listed
        FROM raw_materials source
        WHERE source.location_id = ?
          AND $materialMatch
        ORDER BY source.id ASC
        LIMIT 1
      )
      WHERE target.location_id IS NOT NULL
        AND target.location_id != ?
        AND EXISTS (
          SELECT 1
          FROM raw_materials source
          WHERE source.location_id = ?
            AND $materialMatch
            AND target.listed != source.listed
        )
      ''',
      [templateId, templateId, templateId],
    );

    final combosUpdated = await txn.rawUpdate(
      '''
      UPDATE combos AS target
      SET is_active = (
        SELECT source.is_active
        FROM combos source
        WHERE source.location_id = ?
          AND $comboMatch
        ORDER BY source.id ASC
        LIMIT 1
      )
      WHERE target.location_id IS NOT NULL
        AND target.location_id != ?
        AND EXISTS (
          SELECT 1
          FROM combos source
          WHERE source.location_id = ?
            AND $comboMatch
            AND target.is_active != source.is_active
        )
      ''',
      [templateId, templateId, templateId],
    );

    await txn.insert('schema_migrations', {
      'name': listedLocationCloneRepairV1,
      'applied_at': DateTime.now().toIso8601String(),
    });

    final remaining = await countListedMismatchesAgainstTemplate(txn);

    return ListedLocationCloneRepairResult(
      templateLocationId: templateId,
      materialRowsUpdated: materialsUpdated,
      comboRowsUpdated: combosUpdated,
      mismatchedListedAfter: remaining,
    );
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
