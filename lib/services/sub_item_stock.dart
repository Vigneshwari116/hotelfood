import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/item_import_service.dart';

/// Stock pooling and POS grouping keyed by [RawMaterial.subItem].
class SubItemStock {
  SubItemStock._();

  static String? stockKey(RawMaterial item) => ingredientPoolKey(item);

  /// Normalized identity for one physical ingredient (paratha, patty, bun, etc.).
  static String? ingredientPoolKey(RawMaterial item) {
    final sub = item.subItem?.trim();
    if (sub != null && sub.isNotEmpty) {
      return normalizeIngredientKey(sub);
    }
    final name = item.name.trim();
    if (name.isEmpty) return null;
    return normalizeIngredientKey(name);
  }

  /// Case-insensitive ingredient key with common spelling/plural fixes.
  static String normalizeIngredientKey(String value) {
    var key = normalizeGroupKey(value).replaceAll('panner', 'paneer');
    const blockedSingularization = {
      'fries',
      'sauce',
      'masala',
      'rice',
      'cheese',
    };
    if (blockedSingularization.contains(key)) return key;
    if (key.endsWith('s') && key.length > 4 && !key.endsWith('ss')) {
      return key.substring(0, key.length - 1);
    }
    return key;
  }

  /// Whether duplicate rows for this ingredient should be merged into one stock pool.
  static bool isMergeableIngredientRow(
    RawMaterial item, {
    required Set<int> comboComponentIds,
  }) {
    if (item.id != null && comboComponentIds.contains(item.id)) return true;
    if (!item.listed) return true;

    final poolKey = ingredientPoolKey(item);
    if (poolKey == null || poolKey.isEmpty) return false;

    final nameKey = normalizeIngredientKey(item.name);
    if (nameKey == poolKey) return true;

    if (ItemImportService.hiddenByDefaultNames.contains(nameKey)) return true;
    if (nameKey.contains('patty')) return true;
    if (nameKey.contains('finger')) return true;
    if (nameKey.contains('bun')) return true;

    return false;
  }

  /// Case-insensitive, trimmed comparison key for stock pools.
  static String normalizeGroupKey(String value) {
    return value.trim().toLowerCase();
  }

  /// Returns the existing label when [input] matches a group case-insensitively.
  static String resolveCanonicalLabel(
    String input,
    Iterable<String> existingLabels,
  ) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;

    final key = normalizeGroupKey(trimmed);
    for (final label in existingLabels) {
      final candidate = label.trim();
      if (candidate.isEmpty) continue;
      if (normalizeGroupKey(candidate) == key) return candidate;
    }
    return trimmed;
  }

  /// Unique grouping labels sorted A–Z (case-insensitive dedupe).
  static List<String> distinctGroupLabels(Iterable<String?> values) {
    final byKey = <String, String>{};
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed == null || trimmed.isEmpty) continue;
      final key = normalizeGroupKey(trimmed);
      byKey.putIfAbsent(key, () => trimmed);
    }

    final labels = byKey.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return labels;
  }

  /// Maps raw_material row ids to the canonical sub_item label when a family
  /// has case/whitespace duplicates that should share one stock pool.
  static Map<int, String> canonicalLabelUpdatesForRows(
    Iterable<Map<String, dynamic>> rows,
  ) {
    final byKey = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final sub = row['sub_item']?.toString().trim();
      final name = row['name']?.toString().trim() ?? '';
      final label = (sub == null || sub.isEmpty) ? name : sub;
      if (label.isEmpty) continue;
      byKey.putIfAbsent(normalizeGroupKey(label), () => []).add(row);
    }

    final updates = <int, String>{};
    for (final familyRows in byKey.values) {
      if (familyRows.length < 2) continue;

      final family = familyRows
          .map(
            (row) => RawMaterial(
              id: row['id'] as int?,
              name: row['name']?.toString() ?? '',
              subItem: row['sub_item']?.toString(),
            ),
          )
          .toList();
      final canonical = canonicalLabelForFamily(family);
      if (canonical.isEmpty) continue;

      for (final row in familyRows) {
        final id = row['id'] as int?;
        if (id == null) continue;
        final stored = row['sub_item']?.toString() ?? '';
        if (stored != canonical) {
          updates[id] = canonical;
        }
      }
    }

    return updates;
  }

  /// Picks one display label for a pool of items that share a stock key.
  static String canonicalLabelForFamily(List<RawMaterial> family) {
    if (family.isEmpty) return '';

    final stockKeyValue = stockKey(family.first);
    if (stockKeyValue == null || stockKeyValue.isEmpty) {
      return family.first.trimmedSubItem ?? family.first.name.trim();
    }

    final subLabels = <String>{};
    for (final item in family) {
      final sub = item.subItem?.trim();
      if (sub != null &&
          sub.isNotEmpty &&
          normalizeGroupKey(sub) == stockKeyValue) {
        subLabels.add(sub);
      }
    }
    if (subLabels.isNotEmpty) {
      final sorted = subLabels.toList()
        ..sort((a, b) {
          final byLower = a.toLowerCase().compareTo(b.toLowerCase());
          if (byLower != 0) return byLower;
          return a.compareTo(b);
        });
      for (final label in sorted) {
        if (label.toLowerCase() == stockKeyValue) return label;
      }
      return sorted.first;
    }

    for (final item in family) {
      if (normalizeGroupKey(item.name) == stockKeyValue) {
        return item.name.trim();
      }
    }

    final holder = canonicalHolder(family, stockKey: stockKeyValue);
    if (holder != null) {
      return holder.trimmedSubItem ?? holder.name.trim();
    }

    return family.first.trimmedSubItem ?? family.first.name.trim();
  }

  /// Patty/component references on burger rows are not shared product pools.
  static bool isComponentReference(RawMaterial item, String? categoryName) {
    final sub = item.subItem?.trim().toLowerCase() ?? '';
    if (sub.contains('patty')) return true;
    if (sub.contains('bun')) return true;
    final category = categoryName?.trim().toLowerCase() ?? '';
    return category == 'burgers' || category == 'burger';
  }

  /// Resolves [material] to the canonical stock-holder id for purchases and sales.
  /// Items that share the same sub_item pool (e.g. Paratha in different categories)
  /// always debit/credit the same physical stock row.
  static int resolveCanonicalStockHolderId(
    RawMaterial material,
    Map<int, RawMaterial> byId,
  ) {
    final startId = material.id;
    if (startId == null) return startId ?? 0;

    var resolvedId = startId;
    final visited = <int>{resolvedId};
    while (true) {
      final current = byId[resolvedId];
      if (current == null) break;
      final sourceId = current.stockSourceId;
      if (sourceId == null ||
          sourceId == resolvedId ||
          visited.contains(sourceId)) {
        break;
      }
      visited.add(sourceId);
      resolvedId = sourceId;
    }

    final resolved = byId[resolvedId];
    if (resolved == null) return resolvedId;

    final key = ingredientPoolKey(resolved);
    if (key == null || key.isEmpty) return resolvedId;

    final family = byId.values
        .where((item) => ingredientPoolKey(item) == key)
        .toList();
    if (family.length < 2) return resolvedId;

    final holder = canonicalHolder(family, stockKey: key);
    return holder?.id ?? resolvedId;
  }

  static RawMaterial? canonicalHolder(
    List<RawMaterial> family, {
    required String stockKey,
  }) {
    if (family.isEmpty) return null;

    for (final item in family) {
      if (item.name.trim().toLowerCase() == stockKey) {
        return item;
      }
    }

    for (final item in family) {
      final sub = item.subItem?.trim().toLowerCase();
      if (sub == stockKey) {
        return item;
      }
    }

    family.sort((a, b) {
      final orderA = a.menuSortOrder ?? 1 << 30;
      final orderB = b.menuSortOrder ?? 1 << 30;
      final byOrder = orderA.compareTo(orderB);
      if (byOrder != 0) return byOrder;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return family.first;
  }

  static String posGroupKey(RawMaterial item) {
    final sub = item.subItem?.trim();
    if (sub != null && sub.isNotEmpty) {
      return 'sub:${sub.toLowerCase()}:cat:${item.categoryId ?? -1}';
    }
    return 'solo:${item.id}';
  }

  /// Items that share sub_item within the same category appear on one POS card.
  static bool shouldGroupOnPos(List<RawMaterial> family) {
    if (family.length < 2) return false;
    final keys = family.map(stockKey).toSet();
    if (keys.length != 1 || keys.first == null) return false;
    final categoryIds = family.map((item) => item.categoryId).toSet();
    return categoryIds.length == 1;
  }

  /// Normalizes a variant label for duplicate detection (case/whitespace).
  static String normalizeVariantLabel(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static Map<int, int> buildCanonicalStockIdMap(
    Iterable<RawMaterial> materials,
  ) {
    final byId = {
      for (final material in materials)
        if (material.id != null) material.id!: material,
    };
    return {
      for (final id in byId.keys)
        id: resolveCanonicalStockHolderId(byId[id]!, byId),
    };
  }

  /// One row per physical stock pool for purchase/combo/sub-item pickers.
  static List<RawMaterial> deduplicateToCanonicalStockHolders(
    Iterable<RawMaterial> materials,
  ) {
    final list = materials.toList();
    final stockMap = buildCanonicalStockIdMap(list);
    final byId = {
      for (final material in list)
        if (material.id != null) material.id!: material,
    };
    final seen = <int>{};
    final result = <RawMaterial>[];

    for (final material in list) {
      final id = material.id;
      if (id == null) continue;
      final holderId = stockMap[id] ?? id;
      if (!seen.add(holderId)) continue;
      result.add(byId[holderId] ?? material);
    }

    result.sort(
      (a, b) =>
          a.staffLabel.toLowerCase().compareTo(b.staffLabel.toLowerCase()),
    );
    return result;
  }

  /// Hides listed shadow rows when another row already owns the same stock pool.
  static bool isListedStockShadow(
    RawMaterial material,
    Map<int, RawMaterial> byId,
  ) {
    final id = material.id;
    if (id == null || !material.listed) return false;

    // POS sellable variants (Mini Bucket, Big Buckets, large, etc.) share stock
    // with a holder row but must stay visible for the size/portion selector.
    final variantGroup = material.variantGroup?.trim();
    if (variantGroup != null && variantGroup.isNotEmpty) return false;

    final variantLabel = material.variantLabel?.trim();
    if (variantLabel != null &&
        variantLabel.isNotEmpty &&
        material.stockSourceId != null) {
      return false;
    }

    final holderId = resolveCanonicalStockHolderId(material, byId);
    if (holderId == id) return false;
    return isMergeableIngredientRow(material, comboComponentIds: const {});
  }
}
