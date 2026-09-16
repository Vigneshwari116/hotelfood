import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/item_import_service.dart';

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
    }
    return false;
  }

  int score(RawMaterial material) {
    var value = 0;
    if (material.listed) value += 4;
    if (material.currentStock != 0) value += 2;
    if (material.unitsPerPacket != null) value += 1;
    return value;
  }

  final winners = <String, RawMaterial>{};
  for (final material in all) {
    if (material.id == null) continue;
    if (!material.listed && !isStockComponent(material)) continue;

    final key =
        '${material.categoryId}|${material.staffLabel.trim().toLowerCase()}';
    final existing = winners[key];
    if (existing == null || score(material) > score(existing)) {
      winners[key] = material;
    }
  }

  final result = winners.values.toList()
    ..sort(
      (a, b) =>
          a.staffLabel.toLowerCase().compareTo(b.staffLabel.toLowerCase()),
    );
  return result;
}
