import 'package:foodstock/services/always_visible_menu_categories.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:sqflite/sqflite.dart';

/// One-time: force [listed=1] for Sauces, Fried Items, Snacks, Uncategorized.
const alwaysVisibleCategoryListedRepairV1 =
    'always_visible_category_listed_repair_v1';

class AlwaysVisibleCategoryListedRepairResult {
  const AlwaysVisibleCategoryListedRepairResult({
    required this.rowsUpdated,
    required this.hiddenRemaining,
  });

  final int rowsUpdated;
  final int hiddenRemaining;
}

Future<int> countHiddenAlwaysVisibleCategoryMaterials(DatabaseExecutor db) async {
  final categories = await db.query(
    'categories',
    columns: ['id', 'name'],
    where: "type = 'raw_material'",
  );
  final categoryIds = <int>[];
  for (final row in categories) {
    final id = row['id'] as int?;
    if (id == null) continue;
    final name = row['name'] as String?;
    if (isAlwaysVisibleInSalesCategoryName(name)) {
      categoryIds.add(id);
    }
  }
  if (categoryIds.isEmpty) return 0;

  final placeholders = List.filled(categoryIds.length, '?').join(', ');
  final rows = await db.rawQuery(
    '''
    SELECT COUNT(*) AS c
    FROM raw_materials
    WHERE category_id IN ($placeholders)
      AND COALESCE(listed, 1) = 0
    ''',
    categoryIds,
  );
  return (rows.first['c'] as num?)?.toInt() ?? 0;
}

Future<AlwaysVisibleCategoryListedRepairResult>
    migrateAlwaysVisibleCategoryListedRepair(Database db) async {
  await _ensureSchemaMigrationsTable(db);
  if (await _migrationApplied(db, alwaysVisibleCategoryListedRepairV1)) {
    final remaining = await countHiddenAlwaysVisibleCategoryMaterials(db);
    return AlwaysVisibleCategoryListedRepairResult(
      rowsUpdated: 0,
      hiddenRemaining: remaining,
    );
  }

  return db.transaction((txn) async {
    final categories = await txn.query(
      'categories',
      columns: ['id', 'name'],
      where: "type = 'raw_material'",
    );

    var updated = 0;
    for (final row in categories) {
      final id = row['id'] as int?;
      if (id == null) continue;
      final canonical =
          ItemImportService.canonicalMenuCategory(row['name'] as String?) ?? '';
      if (!alwaysVisibleInSalesCategoryNames.contains(canonical)) continue;
      updated += await txn.update(
        'raw_materials',
        {'listed': 1},
        where: 'category_id = ? AND COALESCE(listed, 1) = 0',
        whereArgs: [id],
      );
    }

    await txn.insert('schema_migrations', {
      'name': alwaysVisibleCategoryListedRepairV1,
      'applied_at': DateTime.now().toIso8601String(),
    });

    final remaining = await countHiddenAlwaysVisibleCategoryMaterials(txn);
    return AlwaysVisibleCategoryListedRepairResult(
      rowsUpdated: updated,
      hiddenRemaining: remaining,
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
