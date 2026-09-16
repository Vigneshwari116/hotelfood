import 'package:foodstock/database/app_db.dart';
import 'package:foodstock/services/item_import_service.dart';

/// Creates POS combo records from imported burger/roll menu rows.
Future<int> syncBurgerRollCombos(AppDb db) async {
  final categories = await db.query(
    'categories',
    columns: ['id', 'name'],
    where: "type = 'raw_material'",
  );

  final categoryIdByName = <String, int>{};
  for (final row in categories) {
    final id = row['id'] as int?;
    final name = row['name'] as String?;
    if (id == null || name == null) continue;
    final canonical = ItemImportService.canonicalMenuCategory(name) ?? name;
    categoryIdByName[canonical.toLowerCase()] = id;
  }

  final burgersId = categoryIdByName['burgers'];
  final rollsId = categoryIdByName['rolls'];
  if (burgersId == null && rollsId == null) return 0;

  final targetCategoryIds = {
    if (burgersId != null) burgersId,
    if (rollsId != null) rollsId,
  };

  final materials = await db.query('raw_materials');
  final byName = <String, int>{};
  for (final row in materials) {
    final id = row['id'] as int?;
    if (id == null) continue;
    final name = (row['name'] as String?)?.trim().toLowerCase() ?? '';
    if (name.isNotEmpty) {
      byName[name] = id;
    }
    final sub = (row['sub_item'] as String?)?.trim().toLowerCase() ?? '';
    if (sub.isNotEmpty) {
      byName.putIfAbsent(sub, () => id);
    }
  }

  final existingCombos = await db.query('combos');
  final comboIdByKey = <String, int>{};
  for (final row in existingCombos) {
    final id = row['id'] as int?;
    if (id == null) continue;
    final name = (row['name'] as String?)?.trim().toLowerCase() ?? '';
    final categoryId = row['category_id'] as int?;
    comboIdByKey['$categoryId|$name'] = id;
  }

  var synced = 0;

  for (final row in materials) {
    final materialId = row['id'] as int?;
    final categoryId = row['category_id'] as int?;
    if (materialId == null || categoryId == null) continue;
    if (!targetCategoryIds.contains(categoryId)) continue;

    final itemName = (row['name'] as String?)?.trim() ?? '';
    final subItem = (row['sub_item'] as String?)?.trim() ?? '';
    if (itemName.isEmpty || subItem.isEmpty) continue;
    if (itemName.toLowerCase() == subItem.toLowerCase()) continue;

    final componentName = subItem.toLowerCase();
    final componentId = byName[componentName];
    if (componentId == null) continue;

    final qty = (row['qty_needed'] as num?)?.toDouble() ?? 1;
    if (qty <= 0) continue;

    final price = (row['selling_price'] as num?)?.toDouble() ?? 0;
    final comboKey = '$categoryId|${itemName.toLowerCase()}';
    final existingComboId = comboIdByKey[comboKey];

    int comboId;
    if (existingComboId == null) {
      comboId = await db.insert('combos', {
        'name': itemName,
        'barcode': null,
        'category_id': categoryId,
        'price': price,
        'selling_price': price,
        'image_path': row['image_path'],
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
      comboIdByKey[comboKey] = comboId;
      synced++;
    } else {
      comboId = existingComboId;
      await db.update(
        'combos',
        {
          'price': price,
          'selling_price': price,
          'category_id': categoryId,
          'is_active': 1,
        },
        where: 'id = ?',
        whereArgs: [comboId],
      );
      await db.delete(
        'combo_raw_materials',
        where: 'combo_id = ?',
        whereArgs: [comboId],
      );
      synced++;
    }

    await db.insert('combo_raw_materials', {
      'combo_id': comboId,
      'raw_material_id': componentId,
      'qty': qty,
    });

    await db.update(
      'raw_materials',
      {'listed': 0},
      where: 'id = ?',
      whereArgs: [materialId],
    );
  }

  return synced;
}
