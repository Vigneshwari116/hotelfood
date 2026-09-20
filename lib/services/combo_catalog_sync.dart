import 'package:foodstock/database/app_db.dart';
import 'package:foodstock/database/menu_catalog_match.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/item_import_service.dart';

/// Creates POS combo records from imported burger/roll menu rows per location.
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
  final locationIds = await _comboSyncLocationIds(db);

  final existingCombos = await db.query('combos');
  final comboIdByKey = <String, int>{};
  for (final row in existingCombos) {
    final id = row['id'] as int?;
    if (id == null) continue;
    final name = (row['name'] as String?)?.trim().toLowerCase() ?? '';
    final categoryId = row['category_id'] as int?;
    final locationId = row['location_id'] as int?;
    comboIdByKey['${locationId ?? 0}|$categoryId|$name'] = id;
  }

  var synced = 0;

  for (final locationId in locationIds) {
    final locationMaterials = materials.where((row) {
      final rowLocation = row['location_id'] as int?;
      if (locationId == null) {
        return rowLocation == null;
      }
      return rowLocation == locationId;
    }).toList();

    if (locationMaterials.isEmpty) continue;

    for (final row in locationMaterials) {
      final materialId = row['id'] as int?;
      final categoryId = row['category_id'] as int?;
      if (materialId == null || categoryId == null) continue;
      if (!targetCategoryIds.contains(categoryId)) continue;

      final itemName = (row['name'] as String?)?.trim() ?? '';
      final subItem = (row['sub_item'] as String?)?.trim() ?? '';
      if (itemName.isEmpty || subItem.isEmpty) continue;
      if (itemName.toLowerCase() == subItem.toLowerCase()) continue;

      final componentId = _resolveIngredientIdAtLocation(
        locationMaterials,
        subItem,
        templateRow: row,
      );
      if (componentId == null) continue;

      final qty = (row['qty_needed'] as num?)?.toDouble() ?? 1;
      if (qty <= 0) continue;

      final price = (row['selling_price'] as num?)?.toDouble() ?? 0;
      final comboKey = '${locationId ?? 0}|$categoryId|${itemName.toLowerCase()}';
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
          if (locationId != null) 'location_id': locationId,
          'created_at': DateTime.now().toIso8601String(),
        });
        comboIdByKey[comboKey] = comboId;
        synced++;
      } else {
        // Existing combos are edited only via saveCombo — never overwrite from menu rows.
        continue;
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
  }

  return synced;
}

/// Location ids to sync burger/roll combos for. Legacy DBs without a
/// [locations] table (or with no rows) use a single pass with null location.
Future<List<int?>> _comboSyncLocationIds(AppDb db) async {
  try {
    final locations = await db.query('locations', orderBy: 'id ASC');
    if (locations.isEmpty) {
      return [null];
    }
    return locations.map((row) => row['id'] as int?).toList();
  } catch (_) {
    return [null];
  }
}

int? _resolveIngredientIdAtLocation(
  List<Map<String, Object?>> locationMaterials,
  String componentName, {
  required Map<String, Object?> templateRow,
}) {
  final normalizedComponent = componentName.trim().toLowerCase();
  int? bestId;
  var bestScore = -1;

  for (final row in locationMaterials) {
    final id = row['id'] as int?;
    if (id == null) continue;

    final name = (row['name'] as String?)?.trim().toLowerCase() ?? '';
    final sub = (row['sub_item'] as String?)?.trim().toLowerCase() ?? '';
    final listed = (row['listed'] as num?)?.toInt() ?? 1;
    final matches = name == normalizedComponent || sub == normalizedComponent;
    if (!matches) continue;

    var score = 0;
    if (listed == 0) score += 10;
    if (name == normalizedComponent) score += 5;
    if (score > bestScore) {
      bestScore = score;
      bestId = id;
    }
  }

  if (bestId != null) return bestId;

  final template = RawMaterial.fromMap(templateRow);
  final templateKey = rawMaterialCatalogMatchKey(
    name: template.name,
    subItem: normalizedComponent,
    barcode: null,
    categoryId: template.categoryId,
  );

  for (final row in locationMaterials) {
    final candidate = RawMaterial.fromMap(row);
    final candidateKey = rawMaterialCatalogMatchKey(
      name: candidate.name,
      subItem: candidate.subItem,
      barcode: candidate.barcode,
      categoryId: candidate.categoryId,
    );
    if (candidateKey != templateKey) continue;
    final id = candidate.id;
    if (id == null) continue;
    if (bestId == null || id < bestId) {
      bestId = id;
    }
  }

  return bestId;
}
