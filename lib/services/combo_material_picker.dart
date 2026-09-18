import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/sub_item_stock.dart';

/// Builds a deduplicated raw-material list for combo component pickers.
List<RawMaterial> materialsForComboPicker(Iterable<RawMaterial> all) {
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

  final list = all.where((material) => material.id != null).toList();
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

  final deduped = SubItemStock.deduplicateToCanonicalStockHolders(winners.values);
  final uniqueById = <int, RawMaterial>{};
  for (final material in deduped) {
    final id = material.id;
    if (id == null) continue;
    uniqueById[id] = material;
  }
  return uniqueById.values.toList()
    ..sort(
      (a, b) =>
          a.staffLabel.toLowerCase().compareTo(b.staffLabel.toLowerCase()),
    );
}
