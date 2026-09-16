import 'package:foodstock/database/app_db.dart';

/// Merges duplicate "Others" categories into Uncategorized and removes
/// true duplicate catalog rows (same name + sub-item in both groups).
Future<int> mergeOthersCategoryIntoUncategorized(AppDb db) async {
  var removedDuplicates = 0;

  final categories = await db.query(
    'categories',
    columns: ['id', 'name'],
    where: "type = 'raw_material'",
  );

  int? uncategorizedId;
  final othersCategoryIds = <int>[];

  for (final row in categories) {
    final id = row['id'] as int?;
    final name = (row['name'] as String?)?.trim().toLowerCase() ?? '';
    if (id == null) continue;
    if (name == 'uncategorized') {
      uncategorizedId = id;
    } else if (name == 'others' || name == 'other') {
      othersCategoryIds.add(id);
    }
  }

  if (othersCategoryIds.isEmpty) return 0;

  String normalizeKey(String? name, String? subItem) {
    final n = (name ?? '').trim().toLowerCase();
    final s = (subItem ?? '').trim().toLowerCase();
    final label = s.isNotEmpty ? s : n;
    return label.replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<Map<String, int>> existingKeysForCategory(int? categoryId) async {
    final rows = categoryId == null
        ? await db.query(
            'raw_materials',
            columns: ['id', 'name', 'sub_item'],
            where: 'category_id IS NULL',
          )
        : await db.query(
            'raw_materials',
            columns: ['id', 'name', 'sub_item'],
            where: 'category_id = ?',
            whereArgs: [categoryId],
          );
    return {
      for (final row in rows)
        if (row['id'] != null)
          normalizeKey(row['name'] as String?, row['sub_item'] as String?):
              row['id'] as int,
    };
  }

  final targetKeys = await existingKeysForCategory(uncategorizedId);

  for (final othersId in othersCategoryIds) {
    final othersRows = await db.query(
      'raw_materials',
      columns: ['id', 'name', 'sub_item'],
      where: 'category_id = ?',
      whereArgs: [othersId],
    );

    for (final row in othersRows) {
      final id = row['id'] as int?;
      if (id == null) continue;
      final key = normalizeKey(row['name'] as String?, row['sub_item'] as String?);
      final existingId = targetKeys[key];
      if (existingId != null && existingId != id) {
        await db.update(
          'raw_materials',
          {'listed': 0},
          where: 'id = ?',
          whereArgs: [id],
        );
        removedDuplicates++;
        continue;
      }

      await db.update(
        'raw_materials',
        {'category_id': uncategorizedId},
        where: 'id = ?',
        whereArgs: [id],
      );
      targetKeys[key] = id;
    }

    await db.delete(
      'categories',
      where: 'id = ?',
      whereArgs: [othersId],
    );
  }

  return removedDuplicates;
}
