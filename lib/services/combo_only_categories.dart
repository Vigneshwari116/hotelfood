import 'package:foodstock/model/models.dart';

/// Categories whose listed items are all combo components — hidden from direct POS sale.
class ComboOnlyCategories {
  ComboOnlyCategories._();

  /// Categories sold only through combos (not as standalone POS/grid cards).
  static const comboSaleOnlyCategoryNames = {'burgers', 'rolls'};

  static bool isComboSaleOnlyCategoryName(String? name) {
    final key = name?.trim().toLowerCase() ?? '';
    return comboSaleOnlyCategoryNames.contains(key);
  }

  static bool shouldHideStandaloneMenuItem(
    RawMaterial material, {
    required String? Function(int? categoryId) categoryNameFor,
    required Set<int?> comboOnlyCategoryIds,
  }) {
    if (isComboSaleOnlyCategoryName(categoryNameFor(material.categoryId))) {
      return true;
    }
    return !isDirectSaleMaterial(
      material,
      comboOnlyCategoryIds: comboOnlyCategoryIds,
    );
  }

  static bool isPosStandaloneMaterial(
    RawMaterial material, {
    required Set<int?> comboOnlyCategoryIds,
    required String? Function(int? categoryId) categoryNameFor,
  }) {
    if (!isDirectSaleMaterial(
      material,
      comboOnlyCategoryIds: comboOnlyCategoryIds,
    )) {
      return false;
    }
    return !isComboSaleOnlyCategoryName(
      categoryNameFor(material.categoryId),
    );
  }

  static Set<int?> categoryIds({
    required Iterable<RawMaterial> materials,
    required Iterable<Combo> combos,
  }) {
    final componentIds = <int>{};
    for (final combo in combos) {
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

  /// Category filter chips on POS — combo-only categories stay visible when they
  /// still have active combos (e.g. Burgers), but hide when empty.
  static Set<int?> posVisibleCategoryIds({
    required Iterable<RawMaterial> materials,
    required Iterable<Combo> combos,
    String? Function(int? categoryId)? categoryNameFor,
  }) {
    final comboOnly = categoryIds(materials: materials, combos: combos);
    final activeCombos = combos.where(
      (combo) => combo.isActive && combo.id != null && combo.items.isNotEmpty,
    );
    final comboCategoryIds = {
      for (final combo in activeCombos) combo.categoryId,
    };
    final nameFor = categoryNameFor ?? (_) => null;

    final ids = <int?>{
      for (final material in materials)
        if (isPosStandaloneMaterial(
          material,
          comboOnlyCategoryIds: comboOnly,
          categoryNameFor: nameFor,
        ))
          material.categoryId,
      ...comboCategoryIds,
    };

    ids.removeWhere(
      (id) => comboOnly.contains(id) && !comboCategoryIds.contains(id),
    );
    return ids;
  }
}
