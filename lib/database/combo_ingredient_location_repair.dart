import 'package:sqflite/sqflite.dart';

import 'menu_catalog_match.dart';

/// Tracks one-time repair of combo ingredient FKs after per-location menu clone.
const comboIngredientLocationRepairV1 = 'combo_ingredient_location_repair_v1';

class ComboIngredientRepairResult {
  const ComboIngredientRepairResult({
    required this.mismatchedBefore,
    required this.linksUpdated,
    required this.mismatchedAfter,
    required this.unresolvedLinks,
  });

  final int mismatchedBefore;
  final int linksUpdated;
  final int mismatchedAfter;
  final int unresolvedLinks;

  bool get isClean => mismatchedAfter == 0;
}

/// Counts [combo_raw_materials] rows whose ingredient [location_id] differs from
/// the parent combo's [location_id].
Future<int> countCrossLocationComboIngredientLinks(DatabaseExecutor db) async {
  final rows = await db.rawQuery('''
    SELECT COUNT(*) AS c
    FROM combo_raw_materials crm
    JOIN combos c ON c.id = crm.combo_id
    JOIN raw_materials rm ON rm.id = crm.raw_material_id
    WHERE c.location_id IS NOT NULL
      AND rm.location_id IS NOT NULL
      AND c.location_id != rm.location_id
  ''');
  return (rows.first['c'] as num?)?.toInt() ?? 0;
}

/// Remaps mismatched combo ingredient IDs to the cloned row at the combo's
/// location (matched by catalog key). Idempotent: safe to re-run; already-correct
/// links are untouched.
Future<ComboIngredientRepairResult> migrateComboIngredientLocationRepair(
  Database db,
) async {
  await _ensureSchemaMigrationsTable(db);
  if (await _migrationApplied(db, comboIngredientLocationRepairV1)) {
    final remaining = await countCrossLocationComboIngredientLinks(db);
    return ComboIngredientRepairResult(
      mismatchedBefore: 0,
      linksUpdated: 0,
      mismatchedAfter: remaining,
      unresolvedLinks: remaining,
    );
  }

  return db.transaction((txn) async {
    final before = await countCrossLocationComboIngredientLinks(txn);

    final updated = await txn.rawUpdate('''
      UPDATE combo_raw_materials
      SET raw_material_id = (
        SELECT rm_target.id
        FROM combos c
        JOIN raw_materials rm_wrong ON rm_wrong.id = combo_raw_materials.raw_material_id
        JOIN raw_materials rm_target ON rm_target.location_id = c.location_id
          AND lower(trim(rm_target.name)) = lower(trim(rm_wrong.name))
          AND lower(trim(coalesce(nullif(trim(rm_target.sub_item), ''), rm_target.name)))
            = lower(trim(coalesce(nullif(trim(rm_wrong.sub_item), ''), rm_wrong.name)))
          AND (
            rm_wrong.barcode IS NULL
            OR trim(rm_wrong.barcode) = ''
            OR rm_target.barcode IS rm_wrong.barcode
          )
          AND (
            rm_wrong.category_id IS NULL
            OR rm_target.category_id = rm_wrong.category_id
          )
        WHERE c.id = combo_raw_materials.combo_id
        ORDER BY rm_target.id ASC
        LIMIT 1
      )
      WHERE EXISTS (
        SELECT 1
        FROM combos c
        JOIN raw_materials rm_wrong ON rm_wrong.id = combo_raw_materials.raw_material_id
        WHERE c.id = combo_raw_materials.combo_id
          AND c.location_id IS NOT NULL
          AND rm_wrong.location_id IS NOT NULL
          AND c.location_id != rm_wrong.location_id
      )
      AND (
        SELECT rm_target.id
        FROM combos c
        JOIN raw_materials rm_wrong ON rm_wrong.id = combo_raw_materials.raw_material_id
        JOIN raw_materials rm_target ON rm_target.location_id = c.location_id
          AND lower(trim(rm_target.name)) = lower(trim(rm_wrong.name))
          AND lower(trim(coalesce(nullif(trim(rm_target.sub_item), ''), rm_target.name)))
            = lower(trim(coalesce(nullif(trim(rm_wrong.sub_item), ''), rm_wrong.name)))
          AND (
            rm_wrong.barcode IS NULL
            OR trim(rm_wrong.barcode) = ''
            OR rm_target.barcode IS rm_wrong.barcode
          )
          AND (
            rm_wrong.category_id IS NULL
            OR rm_target.category_id = rm_wrong.category_id
          )
        WHERE c.id = combo_raw_materials.combo_id
        ORDER BY rm_target.id ASC
        LIMIT 1
      ) IS NOT NULL
    ''');

    final after = await countCrossLocationComboIngredientLinks(txn);

    await txn.insert('schema_migrations', {
      'name': comboIngredientLocationRepairV1,
      'applied_at': DateTime.now().toIso8601String(),
    });

    return ComboIngredientRepairResult(
      mismatchedBefore: before,
      linksUpdated: updated,
      mismatchedAfter: after,
      unresolvedLinks: after,
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
