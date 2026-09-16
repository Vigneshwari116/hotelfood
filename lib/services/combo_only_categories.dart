import 'package:foodstock/model/models.dart';

/// Categories whose listed items are all combo components — hidden from direct POS sale.
class ComboOnlyCategories {
  ComboOnlyCategories._();

  static Set<int?> categoryIds({
    required Iterable<RawMaterial> materials,
    required Iterable<Combo> combos,
  }) {
    final componentIds = <int>{};
    for (final combo in combos) {
      if (!combo.isActive) continue;
      for (final item in combo.items) {
        if (item.rawMaterialId != null) {
          componentIds.add(item.rawMaterialId!);
        }
      }
    }

    final listedByCategory = <int?, List<RawMaterial>>{};
    for (final material in materials) {
      if (!material.listed) continue;
      listedByCategory.putIfAbsent(material.categoryId, () => []).add(material);
    }

    final comboOnly = <int?>{};
    for (final entry in listedByCategory.entries) {
      final listed = entry.value;
      if (listed.isEmpty) continue;
      final allComponents = listed.every(
        (material) =>
            material.id != null && componentIds.contains(material.id),
      );
      if (allComponents) {
        comboOnly.add(entry.key);
      }
    }

    return comboOnly;
  }

  static bool isDirectSaleMaterial(
    RawMaterial material, {
    required Set<int?> comboOnlyCategoryIds,
  }) {
    return !comboOnlyCategoryIds.contains(material.categoryId);
  }
}
