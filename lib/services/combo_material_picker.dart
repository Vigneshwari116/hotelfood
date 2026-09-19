import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/sub_item_stock.dart';

/// Builds a deduplicated raw-material list for combo component pickers.
List<RawMaterial> materialsForComboPicker(
  Iterable<RawMaterial> all, {
  int? catalogLocationId,
}) {
  Iterable<RawMaterial> scoped = all;
  if (catalogLocationId != null) {
    scoped = all.where(
      (material) => material.locationId == catalogLocationId,
    );
  }
  bool isStockComponent(RawMaterial material) {
    final labels = [
      material.name.trim().toLowerCase(),
      (material.subItem ?? '').trim().toLowerCase(),
    ];
    for (final label in labels) {
      if (label.isEmpty) continue;
      if (ItemImportService.hiddenByDefaultNames.contains(label)) return true;
      if (label.contains('patty')) return true;
      if (label.contains('bun')) return true;
      if (label.contains('finger')) return true;
    }
    return false;
  }

  int score(RawMaterial material) {
    var value = 0;
    if (!material.listed) value += 8;
    if (isStockComponent(material)) value += 4;
    if (material.currentStock != 0) value += 2;
    if (material.unitsPerPacket != null) value += 1;
    return value;
  }

  bool shouldInclude(RawMaterial material) {
    if (isStockComponent(material)) return true;
    if (!material.listed) return true;
    final sub = material.subItem?.trim();
    return sub != null && sub.isNotEmpty;
  }

  final list = scoped.where((material) => material.id != null).toList();
  final byPool = <String, List<RawMaterial>>{};
  for (final material in list) {
    if (!shouldInclude(material)) continue;
    final poolKey = SubItemStock.ingredientPoolKey(material) ??
        '${material.categoryId}|${material.staffLabel.trim().toLowerCase()}';
    byPool.putIfAbsent(poolKey, () => []).add(material);
  }

  final winners = <String, RawMaterial>{};
  for (final entry in byPool.entries) {
    final family = List<RawMaterial>.from(entry.value);
    family.sort((a, b) => score(b).compareTo(score(a)));
    winners[entry.key] = family.first;
  }

  final byId = {
    for (final material in list) if (material.id != null) material.id!: material,
  };
  final canonicalIdByMaterialId = SubItemStock.buildCanonicalStockIdMap(list);

  final canonicalByHolderId = <int, RawMaterial>{};
  for (final material in winners.values) {
    final id = material.id;
    if (id == null) continue;
    final holderId = canonicalIdByMaterialId[id] ?? id;
    canonicalByHolderId.putIfAbsent(
      holderId,
      () => byId[holderId] ?? material,
    );
  }

  return canonicalByHolderId.values.toList()
    ..sort(
      (a, b) =>
          a.staffLabel.toLowerCase().compareTo(b.staffLabel.toLowerCase()),
    );
}
