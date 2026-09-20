import 'package:foodstock/database/app_db.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/combo_catalog_sync.dart';
import 'package:foodstock/services/always_visible_menu_categories.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/sub_item_stock.dart';

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

/// Makes always-visible menu categories (Sauces, Fried Items, Snacks,
/// Uncategorized) visible on Sales/POS.
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
    if (!isAlwaysVisibleInSalesCategoryName(row['name'] as String?)) {
      continue;
    }
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

String _locationScopeKey(int? locationId) => '${locationId ?? 0}';

Future<bool> _rawMaterialsHaveLocationId(AppDb db) async {
  try {
    await db.query('raw_materials', columns: ['location_id'], limit: 1);
    return true;
  } catch (_) {
    return false;
  }
}

int? _rowLocationId(Map<String, Object?> row, bool hasLocationColumn) {
  if (!hasLocationColumn) return null;
  return (row['location_id'] as num?)?.toInt();
}

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
  final hasLocationColumn = await _rawMaterialsHaveLocationId(db);
  final rows = await db.query(
    'raw_materials',
    columns: [
      'id',
      'name',
      'sub_item',
      'category_id',
      if (hasLocationColumn) 'location_id',
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
        '${_locationScopeKey(_rowLocationId(row, hasLocationColumn))}|${_categoryKey(row['category_id'] as int?)}|${_normalizeItemKey(row['name'] as String?, row['sub_item'] as String?)}';
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
  final hasLocationColumn = await _rawMaterialsHaveLocationId(db);
  final rows = await db.query(
    'raw_materials',
    columns: [
      'id',
      'name',
      'sub_item',
      'category_id',
      if (hasLocationColumn) 'location_id',
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
    final key =
        '${_locationScopeKey(_rowLocationId(row, hasLocationColumn))}|${_categoryKey(row['category_id'] as int?)}|$name';
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
  final hasLocationColumn = await _rawMaterialsHaveLocationId(db);
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
    columns: [
      'id',
      'name',
      'category_id',
      if (hasLocationColumn) 'location_id',
      'listed',
    ],
  );

  final friedPopcornAtLocation = <int>{};
  for (final row in rows) {
    if (!isPopcornLarge(row['name'] as String?)) continue;
    if (categoryName(row['category_id'] as int?) != 'fried items') continue;
    friedPopcornAtLocation.add(_rowLocationId(row, hasLocationColumn) ?? 0);
  }
  if (friedPopcornAtLocation.isEmpty) return 0;

  var hidden = 0;
  for (final row in rows) {
    final id = row['id'] as int?;
    if (id == null || (row['listed'] as int? ?? 1) == 0) continue;
    if (!isPopcornLarge(row['name'] as String?)) continue;
    if (categoryName(row['category_id'] as int?) != 'snacks') continue;
    final locationKey = _rowLocationId(row, hasLocationColumn) ?? 0;
    if (!friedPopcornAtLocation.contains(locationKey)) continue;
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

/// Merges duplicate ingredient rows (patty, bun, paratha, veg finger, etc.)
/// that share one physical stock pool across categories.
Future<int> mergeGlobalStockDuplicateRows(AppDb db) async {
  final hasLocationColumn = await _rawMaterialsHaveLocationId(db);
  final rows = await db.query(
    'raw_materials',
    columns: [
      'id',
      'name',
      'sub_item',
      'category_id',
      if (hasLocationColumn) 'location_id',
      'listed',
      'current_stock',
      'opening_stock',
      'units_per_packet',
      'variant_group',
      'variant_label',
      'menu_sort_order',
    ],
  );
  if (rows.length < 2) return 0;

  final comboRows = await db.query(
    'combo_raw_materials',
    columns: ['raw_material_id'],
  );
  final comboComponentIds = comboRows
      .map((row) => row['raw_material_id'] as int?)
      .whereType<int>()
      .toSet();

  final byKey = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final material = RawMaterial(
      id: row['id'] as int?,
      name: row['name']?.toString() ?? '',
      subItem: row['sub_item']?.toString(),
      categoryId: (row['category_id'] as num?)?.toInt(),
      listed: (row['listed'] as int? ?? 1) != 0,
      currentStock: (row['current_stock'] as num?)?.toDouble() ?? 0,
      menuSortOrder: (row['menu_sort_order'] as num?)?.toInt(),
    );
    if (!SubItemStock.isMergeableIngredientRow(
      material,
      comboComponentIds: comboComponentIds,
    )) {
      continue;
    }

    final poolKey = SubItemStock.ingredientPoolKey(material);
    if (poolKey == null || poolKey.isEmpty) continue;

    final key =
        '${_locationScopeKey(_rowLocationId(row, hasLocationColumn))}|$poolKey';
    byKey.putIfAbsent(key, () => []).add(row);
  }

  var merged = 0;
  for (final group in byKey.values) {
    if (group.length < 2) continue;
    final keeper = _pickKeeper(group);
    final keeperId = keeper['id'] as int;
    for (final row in group) {
      final id = row['id'] as int?;
      if (id == null || id == keeperId) continue;
      await _mergeMaterialIntoKeeper(db, duplicateId: id, keeperId: keeperId);
      merged++;
    }
  }
  return merged;
}

Future<void> _mergeMaterialIntoKeeper(
  AppDb db, {
  required int duplicateId,
  required int keeperId,
}) async {
  final duplicateRows = await db.query(
    'location_stock',
    where: 'raw_material_id = ?',
    whereArgs: [duplicateId],
  );
  for (final row in duplicateRows) {
    final locationId = row['location_id'] as int?;
    if (locationId == null) continue;
    final qty = (row['current_stock'] as num?)?.toDouble() ?? 0;
    final opening = (row['opening_stock'] as num?)?.toDouble() ?? 0;

    final keeperRows = await db.query(
      'location_stock',
      where: 'location_id = ? AND raw_material_id = ?',
      whereArgs: [locationId, keeperId],
      limit: 1,
    );
    if (keeperRows.isEmpty) {
      await db.insert('location_stock', {
        'location_id': locationId,
        'raw_material_id': keeperId,
        'current_stock': qty,
        'opening_stock': opening,
        'reorder_level': row['reorder_level'] ?? 0,
      });
    } else {
      final keeperQty =
          (keeperRows.first['current_stock'] as num?)?.toDouble() ?? 0;
      final keeperOpening =
          (keeperRows.first['opening_stock'] as num?)?.toDouble() ?? 0;
      await db.update(
        'location_stock',
        {
          'current_stock': keeperQty + qty,
          'opening_stock': keeperOpening + opening,
        },
        where: 'id = ?',
        whereArgs: [keeperRows.first['id']],
      );
    }
    await db.delete(
      'location_stock',
      where: 'id = ?',
      whereArgs: [row['id']],
    );
  }

  final duplicateMaterial = await db.query(
    'raw_materials',
    columns: ['current_stock', 'opening_stock'],
    where: 'id = ?',
    whereArgs: [duplicateId],
    limit: 1,
  );
  if (duplicateMaterial.isNotEmpty) {
    final dupStock =
        (duplicateMaterial.first['current_stock'] as num?)?.toDouble() ?? 0;
    final dupOpening =
        (duplicateMaterial.first['opening_stock'] as num?)?.toDouble() ?? 0;
    final keeperMaterial = await db.query(
      'raw_materials',
      columns: ['current_stock', 'opening_stock'],
      where: 'id = ?',
      whereArgs: [keeperId],
      limit: 1,
    );
    if (keeperMaterial.isNotEmpty) {
      final keeperStock =
          (keeperMaterial.first['current_stock'] as num?)?.toDouble() ?? 0;
      final keeperOpening =
          (keeperMaterial.first['opening_stock'] as num?)?.toDouble() ?? 0;
      await db.update(
        'raw_materials',
        {
          'current_stock': keeperStock + dupStock,
          'opening_stock': keeperOpening + dupOpening,
        },
        where: 'id = ?',
        whereArgs: [keeperId],
      );
    }
  }

  await db.update(
    'combo_raw_materials',
    {'raw_material_id': keeperId},
    where: 'raw_material_id = ?',
    whereArgs: [duplicateId],
  );

  await db.update(
    'raw_materials',
    {'stock_source_id': keeperId},
    where: 'stock_source_id = ?',
    whereArgs: [duplicateId],
  );

  await db.update(
    'stock_batches',
    {'raw_material_id': keeperId},
    where: 'raw_material_id = ?',
    whereArgs: [duplicateId],
  );

  await db.update(
    'stock_ledger',
    {'raw_material_id': keeperId},
    where: 'raw_material_id = ?',
    whereArgs: [duplicateId],
  );

  await db.update(
    'purchase_items',
    {'raw_material_id': keeperId},
    where: 'raw_material_id = ?',
    whereArgs: [duplicateId],
  );

  await db.update(
    'raw_materials',
    {
      'listed': 0,
      'current_stock': 0,
      'opening_stock': 0,
    },
    where: 'id = ?',
    whereArgs: [duplicateId],
  );
}

/// Runs post-import catalog maintenance (dedupe, categories, optional auto-combos).
///
/// [aggressiveDedup] touches [listed] and merges rows — run only on menu import,
/// not on every app login ([maintainCatalog]).
Future<void> runCatalogMaintenance(
  AppDb db, {
  bool aggressiveDedup = false,
  bool syncAutoCombos = false,
}) async {
  if (aggressiveDedup) {
    await mergeGlobalStockDuplicateRows(db);
    await dedupeDuplicateRowsInCategory(db);
    await dedupeDuplicateItemNamesInCategory(db);
    await hideSnacksPopcornLargeDuplicates(db);
  }
  await assignStockComponentCategories(db);
  if (syncAutoCombos) {
    await syncBurgerRollCombos(db);
  }
}
