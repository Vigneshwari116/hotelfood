import 'package:foodstock/database/database_helper.dart';

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

/// Finds and repairs dangling raw_material foreign-key references left behind
/// when catalog rows were deleted or merged without updating dependents.
Future<RawMaterialIntegrityReport> repairOrphanedRawMaterialReferences(
  SqliteAppDb db,
) async {
  var clearedInvalidStockSources = 0;
  var removedOrphanComboComponents = 0;
  var removedOrphanStockBatches = 0;
  var removedOrphanPendingItems = 0;
  var removedOrphanLocationStock = 0;

  clearedInvalidStockSources = await db.rawUpdate('''
    UPDATE raw_materials
    SET stock_source_id = NULL
    WHERE stock_source_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM raw_materials src WHERE src.id = stock_source_id
      )
  ''');

  removedOrphanComboComponents = await db.rawDelete('''
    DELETE FROM combo_raw_materials
    WHERE NOT EXISTS (
      SELECT 1 FROM raw_materials rm WHERE rm.id = raw_material_id
    )
  ''');

  removedOrphanStockBatches = await db.rawDelete('''
    DELETE FROM stock_batches
    WHERE NOT EXISTS (
      SELECT 1 FROM raw_materials rm WHERE rm.id = raw_material_id
    )
  ''');

  removedOrphanPendingItems = await db.rawDelete('''
    DELETE FROM pending_order_items
    WHERE raw_material_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM raw_materials rm WHERE rm.id = raw_material_id
      )
  ''');

  removedOrphanLocationStock = await db.rawDelete('''
    DELETE FROM location_stock
    WHERE NOT EXISTS (
      SELECT 1 FROM raw_materials rm WHERE rm.id = raw_material_id
    )
  ''');

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
  SqliteAppDb db,
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
