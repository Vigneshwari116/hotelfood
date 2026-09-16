import 'package:foodstock/database/app_db.dart';
import 'package:foodstock/services/item_import_service.dart';

String _normalizeItemKey(String? name, String? subItem) {
  final n = (name ?? '').trim().toLowerCase();
  final s = (subItem ?? '').trim().toLowerCase();
  final label = s.isNotEmpty ? s : n;
  return label.replaceAll(RegExp(r'\s+'), ' ');
}

/// Merges duplicate "Others" categories into Uncategorized and removes
/// true duplicate catalog rows (same name + sub-item across groups).
Future<int> mergeOthersCategoryIntoUncategorized(AppDb db) async {
  var removedDuplicates = 0;

  final categories = await db.query(
    'categories',
    columns: ['id', 'name'],
    where: "type = 'raw_material'",
  );

  final aliasCategoryIds = <int>[];
  int? targetCategoryId;

  for (final row in categories) {
    final id = row['id'] as int?;
    final name = row['name'] as String?;
    if (id == null) continue;
    if (!ItemImportService.isUncategorizedCategoryName(name)) continue;

    aliasCategoryIds.add(id);
    if (name?.trim().toLowerCase() == 'uncategorized') {
      targetCategoryId = id;
    }
  }

  if (aliasCategoryIds.isEmpty) return 0;

  targetCategoryId ??= aliasCategoryIds.first;

  final rows = <Map<String, dynamic>>[
    ...await db.query(
      'raw_materials',
      columns: ['id', 'name', 'sub_item', 'category_id', 'listed'],
      where: 'category_id IS NULL',
    ),
  ];

  for (final categoryId in aliasCategoryIds) {
    rows.addAll(
      await db.query(
        'raw_materials',
        columns: ['id', 'name', 'sub_item', 'category_id', 'listed'],
        where: 'category_id = ?',
        whereArgs: [categoryId],
      ),
    );
  }

  final byKey = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final key = _normalizeItemKey(
      row['name'] as String?,
      row['sub_item'] as String?,
    );
    if (key.isEmpty) continue;
    byKey.putIfAbsent(key, () => []).add(row);
  }

  for (final group in byKey.values) {
    if (group.length == 1) {
      final row = group.first;
      final id = row['id'] as int?;
      if (id == null) continue;
      if ((row['category_id'] as int?) != targetCategoryId) {
        await db.update(
          'raw_materials',
          {'category_id': targetCategoryId},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      continue;
    }

    group.sort(
      (a, b) => (a['id'] as int).compareTo(b['id'] as int),
    );

    Map<String, dynamic> keeper = group.first;
    for (final row in group) {
      final rowCategoryId = row['category_id'] as int?;
      if (rowCategoryId == targetCategoryId) {
        keeper = row;
        break;
      }
    }

    for (final row in group) {
      final id = row['id'] as int?;
      if (id == null) continue;
      if (id == keeper['id']) {
        if ((row['category_id'] as int?) != targetCategoryId) {
          await db.update(
            'raw_materials',
            {'category_id': targetCategoryId},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        continue;
      }

      await db.update(
        'raw_materials',
        {'listed': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      removedDuplicates++;
    }
  }

  for (final aliasId in aliasCategoryIds) {
    if (aliasId == targetCategoryId) continue;
    await db.delete(
      'categories',
      where: 'id = ?',
      whereArgs: [aliasId],
    );
  }

  await db.update(
    'categories',
    {'name': 'Uncategorized'},
    where: 'id = ?',
    whereArgs: [targetCategoryId],
  );

  return removedDuplicates;
}

/// Makes Sauces category items visible on Sales/POS (free add-ons, not hidden).
Future<int> listSaucesCategoryForPos(AppDb db) async {
  final categories = await db.query(
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
    if (canonical.toLowerCase() != 'sauces') continue;
    updated += await db.update(
      'raw_materials',
      {'listed': 1},
      where: 'category_id = ?',
      whereArgs: [id],
    );
  }
  return updated;
}
