import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/sub_item_stock.dart';

/// Builds a deduplicated raw-material list for combo component pickers.
List<RawMaterial> materialsForComboPicker(
  Iterable<RawMaterial> all, {
  Iterable<String> comboNames = const [],
}) {
  final comboNameKeys = comboNames
      .map((name) => name.trim().toLowerCase())
      .where((name) => name.isNotEmpty)
      .toSet();

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

  bool isComboSourceMenuRow(RawMaterial material) {
    final sub = material.subItem?.trim() ?? '';
    final name = material.name.trim();
    if (sub.isEmpty) return false;
    if (sub.toLowerCase() == name.toLowerCase()) return false;
    if (!material.listed) return false;
    return true;
  }

  bool shouldInclude(RawMaterial material) {
    final nameKey = material.name.trim().toLowerCase();
    if (comboNameKeys.contains(nameKey)) return false;
    if (isComboSourceMenuRow(material)) return false;
    if (isStockComponent(material)) return true;
    if (!material.listed) return true;
    return false;
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

/// Resolves combo ingredient dropdown options for one line, including any
/// already-saved ingredient that is no longer in the default picker list.
List<RawMaterial> comboDropdownMaterials({
  required Iterable<RawMaterial> pickerMaterials,
  required Map<int, RawMaterial> allMaterialsById,
  required int? selectedMaterialId,
  required Iterable<int> usedMaterialIds,
}) {
  final byId = <int, RawMaterial>{
    for (final material in pickerMaterials)
      if (material.id != null) material.id!: material,
  };

  if (selectedMaterialId != null) {
    final selected = allMaterialsById[selectedMaterialId];
    if (selected != null) {
      byId.putIfAbsent(selectedMaterialId, () => selected);
    }
  }

  final used = usedMaterialIds.toSet();
  return byId.values
      .where(
        (material) =>
            material.id == selectedMaterialId || !used.contains(material.id),
      )
      .toList()
    ..sort(
      (a, b) =>
          a.staffLabel.toLowerCase().compareTo(b.staffLabel.toLowerCase()),
    );
}

/// Whether a material is a valid combo ingredient (not a finished menu/combo row).
bool isValidComboIngredient(
  RawMaterial material, {
  required String comboName,
  Iterable<String> comboNames = const [],
}) {
  final comboKey = comboName.trim().toLowerCase();
  final nameKey = material.name.trim().toLowerCase();
  if (comboKey.isNotEmpty && nameKey == comboKey) return false;

  final allComboNames = comboNames
      .map((name) => name.trim().toLowerCase())
      .where((name) => name.isNotEmpty)
      .toSet();
  if (allComboNames.contains(nameKey)) return false;

  final sub = material.subItem?.trim() ?? '';
  final name = material.name.trim();
  if (material.listed && sub.isNotEmpty && sub.toLowerCase() != name.toLowerCase()) {
    return false;
  }

  return materialsForComboPicker(
    [material],
    comboNames: comboNames,
  ).any((item) => item.id == material.id);
}
