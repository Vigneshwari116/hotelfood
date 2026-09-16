import 'package:foodstock/database/app_db.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/combo_catalog_sync.dart';

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

String _normalizeItemName(String? name) {
  return (name ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

String _categoryKey(int? categoryId) => categoryId?.toString() ?? 'null';

int _scoreKeeperRow(Map<String, dynamic> row) {
  var score = 0;
  if ((row['listed'] as int? ?? 1) != 0) score += 8;
  final stock = (row['current_stock'] as num?)?.toDouble() ?? 0;
  if (stock != 0) score += 4;
  if ((row['units_per_packet'] as num?)?.toDouble() != null) score += 2;
  if ((row['variant_group'] as String?)?.trim().isNotEmpty ?? false) {
    score += 2;
  }
  final label = (row['variant_label'] as String?)?.trim().toLowerCase() ?? '';
  if (label == 'regular') score += 1;
  return score;
}

Map<String, dynamic> _pickKeeper(List<Map<String, dynamic>> group) {
  group.sort((a, b) {
    final byScore = _scoreKeeperRow(b).compareTo(_scoreKeeperRow(a));
    if (byScore != 0) return byScore;
    return (a['id'] as int).compareTo(b['id'] as int);
  });
  return group.first;
}

/// Hides duplicate catalog rows with the same category + name + sub-item.
Future<int> dedupeDuplicateRowsInCategory(AppDb db) async {
  final rows = await db.query(
    'raw_materials',
    columns: [
      'id',
      'name',
      'sub_item',
      'category_id',
      'listed',
      'current_stock',
      'units_per_packet',
      'variant_group',
      'variant_label',
    ],
  );

  final byKey = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final key =
        '${_categoryKey(row['category_id'] as int?)}|${_normalizeItemKey(row['name'] as String?, row['sub_item'] as String?)}';
    if (key.endsWith('|')) continue;
    byKey.putIfAbsent(key, () => []).add(row);
  }

  var hidden = 0;
  for (final group in byKey.values) {
    if (group.length < 2) continue;
    final keeper = _pickKeeper(group);
    for (final row in group) {
      final id = row['id'] as int?;
      if (id == null || id == keeper['id']) continue;
      await db.update(
        'raw_materials',
        {'listed': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      hidden++;
    }
  }
  return hidden;
}

/// Hides duplicate item names within the same category (e.g. two Crunchy Masala rows).
Future<int> dedupeDuplicateItemNamesInCategory(AppDb db) async {
  final rows = await db.query(
    'raw_materials',
    columns: [
      'id',
      'name',
      'sub_item',
      'category_id',
      'listed',
      'current_stock',
      'units_per_packet',
      'variant_group',
      'variant_label',
    ],
  );

  final byKey = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final name = _normalizeItemName(row['name'] as String?);
    if (name.isEmpty) continue;
    final key = '${_categoryKey(row['category_id'] as int?)}|$name';
    byKey.putIfAbsent(key, () => []).add(row);
  }

  var hidden = 0;
  for (final group in byKey.values) {
    if (group.length < 2) continue;
    final keeper = _pickKeeper(group);
    for (final row in group) {
      final id = row['id'] as int?;
      if (id == null || id == keeper['id']) continue;
      await db.update(
        'raw_materials',
        {'listed': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      hidden++;
    }
  }
  return hidden;
}

/// Hides SNACKS popcorn-large rows when the FRIED ITEMS row exists.
Future<int> hideSnacksPopcornLargeDuplicates(AppDb db) async {
  final categories = await db.query(
    'categories',
    columns: ['id', 'name'],
    where: "type = 'raw_material'",
  );
  final categoryNameById = {
    for (final row in categories)
      if (row['id'] != null) row['id'] as int: row['name'] as String? ?? '',
  };

  bool isPopcornLarge(String? name) {
    final key = name?.trim().toLowerCase() ?? '';
    return key.contains('popcorn') && key.contains('large');
  }

  String categoryName(int? categoryId) {
    if (categoryId == null) return '';
    return ItemImportService.displayCategoryName(
      categoryNameById[categoryId],
    ).toLowerCase();
  }

  final rows = await db.query(
    'raw_materials',
    columns: ['id', 'name', 'category_id', 'listed'],
  );

  final hasFriedPopcorn = rows.any(
    (row) =>
        isPopcornLarge(row['name'] as String?) &&
        categoryName(row['category_id'] as int?) == 'fried items',
  );
  if (!hasFriedPopcorn) return 0;

  var hidden = 0;
  for (final row in rows) {
    final id = row['id'] as int?;
    if (id == null || (row['listed'] as int? ?? 1) == 0) continue;
    if (!isPopcornLarge(row['name'] as String?)) continue;
    if (categoryName(row['category_id'] as int?) != 'snacks') continue;
    await db.update(
      'raw_materials',
      {'listed': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    hidden++;
  }
  return hidden;
}

/// Assigns stock-only components (e.g. Paratha) to Fried Items for inventory grouping.
Future<int> assignStockComponentCategories(AppDb db) async {
  final categories = await db.query(
    'categories',
    columns: ['id', 'name'],
    where: "type = 'raw_material'",
  );

  int? friedItemsId;
  for (final row in categories) {
    final id = row['id'] as int?;
    final canonical =
        ItemImportService.canonicalMenuCategory(row['name'] as String?) ?? '';
    if (canonical.toLowerCase() == 'fried items') {
      friedItemsId = id;
      break;
    }
  }
  if (friedItemsId == null) return 0;

  const stockNames = {'paratha', 'bun', 'burger bun with sesame'};
  final rows = await db.query(
    'raw_materials',
    columns: ['id', 'name', 'category_id'],
  );

  var updated = 0;
  for (final row in rows) {
    final id = row['id'] as int?;
    if (id == null) continue;
    final name = _normalizeItemName(row['name'] as String?);
    if (!stockNames.contains(name)) continue;
    if (row['category_id'] == friedItemsId) continue;
    await db.update(
      'raw_materials',
      {'category_id': friedItemsId},
      where: 'id = ?',
      whereArgs: [id],
    );
    updated++;
  }
  return updated;
}

/// Runs post-import catalog maintenance (dedupe, combos, categories).
Future<void> runCatalogMaintenance(AppDb db) async {
  await dedupeDuplicateRowsInCategory(db);
  await dedupeDuplicateItemNamesInCategory(db);
  await hideSnacksPopcornLargeDuplicates(db);
  await assignStockComponentCategories(db);
  await syncBurgerRollCombos(db);
}
