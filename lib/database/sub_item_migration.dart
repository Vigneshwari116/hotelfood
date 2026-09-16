import 'package:foodstock/database/app_db.dart';
import 'package:foodstock/services/sub_item_stock.dart';

/// One-time backfill: merge case/whitespace variants of [sub_item] into one label.
Future<int> normalizeSubItemLabels(AppDb db) async {
  final rows = await db.query(
    'raw_materials',
    columns: ['id', 'name', 'sub_item'],
  );
  if (rows.isEmpty) return 0;

  final updates = SubItemStock.canonicalLabelUpdatesForRows(rows);
  for (final entry in updates.entries) {
    await db.update(
      'raw_materials',
      {'sub_item': entry.value},
      where: 'id = ?',
      whereArgs: [entry.key],
    );
  }
  return updates.length;
}
