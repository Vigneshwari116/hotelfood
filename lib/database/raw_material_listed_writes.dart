import 'package:foodstock/database/app_db.dart';
import 'package:foodstock/database/inventory_save_log.dart';
import 'package:foodstock/services/listed_change_source.dart';

/// Atomic listed-field write with declared source (shared by repository + catalog cleanup).
Future<void> writeRawMaterialListed(
  AppDb db, {
  required int rawMaterialId,
  required bool listed,
  required String source,
  bool clearBarcode = false,
}) async {
  ListedChangeSource.requireDeclared(source);
  final operation = 'listed_change:$source';

  await db.transaction((txn) async {
    await txn.annotateChangeSource(source);
    final updateMap = <String, Object?>{
      'listed': listed ? 1 : 0,
    };
    if (clearBarcode && !listed) {
      updateMap['barcode'] = null;
    }
    await txn.update(
      'raw_materials',
      updateMap,
      where: 'id = ?',
      whereArgs: [rawMaterialId],
    );
  });

  await logInventorySave(
    db,
    operation: operation,
    rawMaterialId: rawMaterialId,
    success: true,
  );
}
