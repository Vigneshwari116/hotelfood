import 'package:foodstock/database/app_db.dart';

/// Result of a one-time orphaned-reference audit/repair pass.
class RawMaterialIntegrityReport {
  const RawMaterialIntegrityReport({
    this.clearedInvalidStockSources = 0,
    this.removedOrphanComboComponents = 0,
    this.removedOrphanStockBatches = 0,
    this.removedOrphanPendingItems = 0,
    this.removedOrphanLocationStock = 0,
  });

  final int clearedInvalidStockSources;
  final int removedOrphanComboComponents;
  final int removedOrphanStockBatches;
  final int removedOrphanPendingItems;
  final int removedOrphanLocationStock;

  int get totalRepairs =>
      clearedInvalidStockSources +
      removedOrphanComboComponents +
      removedOrphanStockBatches +
      removedOrphanPendingItems +
      removedOrphanLocationStock;

  bool get hasIssues => totalRepairs > 0;
}

Future<int> _deleteRowsById(AppDb db, String table, List<Map<String, Object?>> rows) async {
  var removed = 0;
  for (final row in rows) {
    final id = row['id'];
    if (id == null) continue;
    removed += await db.delete(
      table,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  return removed;
}

/// Finds and repairs dangling raw_material foreign-key references left behind
/// when catalog rows were deleted or merged without updating dependents.
Future<RawMaterialIntegrityReport> repairOrphanedRawMaterialReferences(
  AppDb db,
) async {
  var clearedInvalidStockSources = 0;
  var removedOrphanComboComponents = 0;
  var removedOrphanStockBatches = 0;
  var removedOrphanPendingItems = 0;
  var removedOrphanLocationStock = 0;

  final invalidStockSources = await db.rawQuery('''
    SELECT id FROM raw_materials
    WHERE stock_source_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM raw_materials src WHERE src.id = stock_source_id
      )
  ''');
  for (final row in invalidStockSources) {
    final id = row['id'];
    if (id == null) continue;
    clearedInvalidStockSources += await db.update(
      'raw_materials',
      {'stock_source_id': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  removedOrphanComboComponents = await _deleteRowsById(
    db,
    'combo_raw_materials',
    await db.rawQuery('''
      SELECT id FROM combo_raw_materials
      WHERE NOT EXISTS (
        SELECT 1 FROM raw_materials rm WHERE rm.id = raw_material_id
      )
    '''),
  );

  removedOrphanStockBatches = await _deleteRowsById(
    db,
    'stock_batches',
    await db.rawQuery('''
      SELECT id FROM stock_batches
      WHERE NOT EXISTS (
        SELECT 1 FROM raw_materials rm WHERE rm.id = raw_material_id
      )
    '''),
  );

  removedOrphanPendingItems = await _deleteRowsById(
    db,
    'pending_order_items',
    await db.rawQuery('''
      SELECT id FROM pending_order_items
      WHERE raw_material_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM raw_materials rm WHERE rm.id = raw_material_id
        )
    '''),
  );

  removedOrphanLocationStock = await _deleteRowsById(
    db,
    'location_stock',
    await db.rawQuery('''
      SELECT id FROM location_stock
      WHERE NOT EXISTS (
        SELECT 1 FROM raw_materials rm WHERE rm.id = raw_material_id
      )
    '''),
  );

  return RawMaterialIntegrityReport(
    clearedInvalidStockSources: clearedInvalidStockSources,
    removedOrphanComboComponents: removedOrphanComboComponents,
    removedOrphanStockBatches: removedOrphanStockBatches,
    removedOrphanPendingItems: removedOrphanPendingItems,
    removedOrphanLocationStock: removedOrphanLocationStock,
  );
}

/// Read-only audit counts for diagnostics.
Future<Map<String, int>> auditOrphanedRawMaterialReferences(
  AppDb db,
) async {
  Future<int> count(String sql) async {
    final rows = await db.rawQuery(sql);
    if (rows.isEmpty) return 0;
    return (rows.first.values.first as num?)?.toInt() ?? 0;
  }

  return {
    'invalid_stock_sources': await count('''
      SELECT COUNT(*) AS c FROM raw_materials
      WHERE stock_source_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM raw_materials src WHERE src.id = stock_source_id
        )
    '''),
    'orphan_combo_components': await count('''
      SELECT COUNT(*) AS c FROM combo_raw_materials
      WHERE NOT EXISTS (
        SELECT 1 FROM raw_materials rm WHERE rm.id = raw_material_id
      )
    '''),
    'orphan_stock_batches': await count('''
      SELECT COUNT(*) AS c FROM stock_batches
      WHERE NOT EXISTS (
        SELECT 1 FROM raw_materials rm WHERE rm.id = raw_material_id
      )
    '''),
    'orphan_pending_items': await count('''
      SELECT COUNT(*) AS c FROM pending_order_items
      WHERE raw_material_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM raw_materials rm WHERE rm.id = raw_material_id
        )
    '''),
  };
}
