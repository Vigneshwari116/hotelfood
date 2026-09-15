import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/sub_item_stock.dart';

/// A family of sellable menu items that share one stock pool and appear as
/// a single POS card with a size/portion selector.
class VariantGroup {
  const VariantGroup({
    required this.key,
    required this.displayName,
    required this.variants,
    required this.stockSource,
  });

  final String key;
  final String displayName;
  final List<RawMaterial> variants;
  final RawMaterial stockSource;

  /// POS card title — variant group name when set, otherwise stock source label.
  String get posTitle {
    final trimmed = displayName.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return stockSource.salesLabel;
  }
}

/// Shared logic for size/portion variants and stock pooling.
class VariantHelpers {
  VariantHelpers._();

  static final RegExp _sizeVariantPattern = RegExp(
    r'(popcorn\s+(small|large)|masala\s+fries\s+(small|large)|\b(small|large|mini\s+bucket|big\s+bucket|buckets?)\b)',
    caseSensitive: false,
  );

  /// Resolves which raw material row holds the physical stock count.
  static int stockMaterialId(RawMaterial material) {
    return material.stockSourceId ?? material.id!;
  }

  /// Stock count used for POS display and sellable-unit math.
  static double stockCount(
    RawMaterial material,
    Map<int, RawMaterial> byId,
  ) {
    final sourceId = material.stockSourceId;
    if (sourceId != null) {
      return byId[sourceId]?.currentStock ?? 0;
    }
    return material.currentStock;
  }

  /// How many units of [material] can be sold from the shared pool.
  static double sellableUnits(
    RawMaterial material,
    Map<int, RawMaterial> byId,
  ) {
    final stock = stockCount(material, byId);
    final perSale = material.qtyNeeded <= 0 ? 1.0 : material.qtyNeeded;
    return stock / perSale;
  }

  /// Label shown on the POS size/portion selector.
  static String variantSelectorLabel(RawMaterial material) {
    final label = material.variantLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    return material.salesLabel;
  }

  static String _normalizedFamilyKey(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll(
          RegExp(r'\s+(small|sm|large|lg|mini|big|bucket|buckets)\b.*$'),
          '',
        )
        .trim();
  }

  static String? productFamilyKey(RawMaterial item) {
    final sub = item.subItem?.trim();
    if (sub != null && sub.isNotEmpty) {
      final key = _normalizedFamilyKey(sub);
      if (key.isNotEmpty) return key;
    }

    final name = item.name.trim();
    if (name.isEmpty) return null;
    return _normalizedFamilyKey(name);
  }

  /// Returns [materials] with [currentStock] resolved through shared stock pools.
  static List<RawMaterial> withEffectiveStock(List<RawMaterial> materials) {
    final linked = withSyncedLinks(materials);
    final byId = {
      for (final material in linked)
        if (material.id != null) material.id!: material,
    };
    return linked
        .map(
          (material) => _copyWithStock(
            material,
            stockCount(material, byId),
          ),
        )
        .toList();
  }

  static RawMaterial _copyWithStock(RawMaterial item, double currentStock) {
    return RawMaterial(
      id: item.id,
      barcode: item.barcode,
      name: item.name,
      subItem: item.subItem,
      qtyNeeded: item.qtyNeeded,
      categoryId: item.categoryId,
      unitId: item.unitId,
      openingStock: item.openingStock,
      currentStock: currentStock,
      reorderLevel: item.reorderLevel,
      shelfLifeDays: item.shelfLifeDays,
      unitsPerPacket: item.unitsPerPacket,
      entryPasswordHash: item.entryPasswordHash,
      costPrice: item.costPrice,
      sellingPrice: item.sellingPrice,
      imagePath: item.imagePath,
      listed: item.listed,
      createdAt: item.createdAt,
      menuSortOrder: item.menuSortOrder,
      variantGroup: item.variantGroup,
      variantLabel: item.variantLabel,
      stockSourceId: item.stockSourceId,
    );
  }

  /// Returns [materials] with variant_group / stock_source_id applied in memory.
  static List<RawMaterial> withSyncedLinks(List<RawMaterial> materials) {
    final updates = syncVariantLinks(materials);
    if (updates.isEmpty) return materials;

    final byId = {
      for (final material in materials)
        if (material.id != null) material.id!: material,
    };
    for (final update in updates) {
      if (update.id != null) {
        byId[update.id!] = update;
      }
    }
    return materials
        .map(
          (material) => material.id != null
              ? (byId[material.id!] ?? material)
              : material,
        )
        .toList();
  }

  /// Splits [materials] into standalone tiles and multi-variant groups.
  static ({
    List<RawMaterial> singles,
    List<VariantGroup> groups,
  }) partitionForPos(List<RawMaterial> materials) {
    final linked = withSyncedLinks(materials);
    final assigned = <int>{};
    final byGroup = <String, List<RawMaterial>>{};
    final singles = <RawMaterial>[];

    for (final material in linked) {
      if (material.id == null) continue;
      final groupKey = material.variantGroup?.trim();
      if (groupKey == null || groupKey.isEmpty) continue;
      byGroup.putIfAbsent(groupKey, () => []).add(material);
      assigned.add(material.id!);
    }

    final bySubItem = <String, List<RawMaterial>>{};
    for (final material in linked) {
      if (material.id == null || assigned.contains(material.id)) continue;
      final key = SubItemStock.posGroupKey(material);
      bySubItem.putIfAbsent(key, () => []).add(material);
    }

    for (final entry in bySubItem.entries) {
      final variants = List<RawMaterial>.from(entry.value);
      final isComponentFamily = variants.any(
        (item) => SubItemStock.isComponentReference(item, null),
      );
      if (isComponentFamily ||
          !SubItemStock.shouldGroupOnPos(variants)) {
        for (final variant in variants) {
          if (variant.id != null) assigned.add(variant.id!);
        }
        singles.addAll(variants);
        continue;
      }
      for (final variant in variants) {
        if (variant.id != null) assigned.add(variant.id!);
      }
      byGroup.putIfAbsent(entry.key, () => variants);
    }

    for (final material in linked) {
      if (material.id == null || assigned.contains(material.id)) continue;
      singles.add(material);
    }

    final groups = <VariantGroup>[];
    for (final entry in byGroup.entries) {
      final variants = List<RawMaterial>.from(entry.value);
      final isComponentFamily = variants.any(
        (item) => SubItemStock.isComponentReference(item, null),
      );
      final canGroup = !isComponentFamily &&
          (SubItemStock.shouldGroupOnPos(variants) ||
              shouldAutoLinkFamily(variants));
      if (variants.length < 2 || !canGroup) {
        singles.addAll(variants);
        continue;
      }

      variants.sort((a, b) {
        final orderA = a.menuSortOrder ?? 1 << 30;
        final orderB = b.menuSortOrder ?? 1 << 30;
        final byOrder = orderA.compareTo(orderB);
        if (byOrder != 0) return byOrder;
        return a.salesLabel.toLowerCase().compareTo(b.salesLabel.toLowerCase());
      });

      final stockKey = SubItemStock.stockKey(variants.first) ?? '';
      final stockSource = SubItemStock.canonicalHolder(
            variants,
            stockKey: stockKey,
          ) ??
          variants.firstWhere(
            (v) => v.stockSourceId == null,
            orElse: () => variants.first,
          );

      groups.add(
        VariantGroup(
          key: entry.key,
          displayName: stockSource.salesLabel,
          variants: variants,
          stockSource: stockSource,
        ),
      );
    }

    groups.sort(
      (a, b) => a.posTitle.toLowerCase().compareTo(b.posTitle.toLowerCase()),
    );

    return (singles: singles, groups: groups);
  }

  /// Picks the canonical stock owner for a size-variant family.
  static RawMaterial? canonicalStockSource(
    List<RawMaterial> family, {
    String? familyKey,
  }) {
    if (family.isEmpty) return null;

    final key = familyKey ?? productFamilyKey(family.first);
    if (key == null || key.isEmpty) return null;

    for (final item in family) {
      if (item.name.trim().toLowerCase() == key) {
        return item;
      }
    }

    for (final item in family) {
      final sub = productFamilyKey(item);
      if (sub == key && !looksLikeSizeVariant(item)) {
        return item;
      }
    }

    return null;
  }

  static bool looksLikeSizeVariant(RawMaterial item) {
    final text = '${item.variantLabel ?? ''} ${item.name}';
    return _sizeVariantPattern.hasMatch(text);
  }

  /// Only link items that share a stock sub-item when one row is the base
  /// product and the others are clearly size/portion variants (small/large/etc).
  /// Different burgers sharing the same patty sub-item stay separate.
  static bool shouldAutoLinkFamily(List<RawMaterial> family) {
    if (family.length < 2) return false;

    final familyKey = productFamilyKey(family.first);
    if (familyKey == null || familyKey.isEmpty) return false;

    if (family.any((item) => productFamilyKey(item) != familyKey)) {
      return false;
    }

    final source = canonicalStockSource(family, familyKey: familyKey);
    if (source == null) return false;

    final sourceSub = productFamilyKey(source);
    if (sourceSub != familyKey) return false;

    final categoryIds = family.map((item) => item.categoryId).toSet();
    if (categoryIds.length > 1) return false;

    for (final item in family) {
      if (item.id == source.id) continue;
      if (!looksLikeSizeVariant(item)) return false;
    }

    return true;
  }

  static List<RawMaterial> _familyForKey(
    String familyKey,
    List<RawMaterial> items,
  ) {
    final matches = <RawMaterial>[];
    for (final item in items) {
      final key = productFamilyKey(item);
      if (key == familyKey) {
        matches.add(item);
      }
    }
    return matches;
  }

  static Map<int, String> _categoryNameById(List<RawMaterial> items) {
    return {};
  }

  static RawMaterial _copyWithLinks(
    RawMaterial item, {
    String? variantGroup,
    String? variantLabel,
    int? stockSourceId,
    bool clearVariantGroup = false,
    bool clearVariantLabel = false,
    bool clearStockSource = false,
  }) {
    return RawMaterial(
      id: item.id,
      barcode: item.barcode,
      name: item.name,
      subItem: item.subItem,
      qtyNeeded: item.qtyNeeded,
      categoryId: item.categoryId,
      unitId: item.unitId,
      openingStock: item.openingStock,
      currentStock: item.currentStock,
      reorderLevel: item.reorderLevel,
      shelfLifeDays: item.shelfLifeDays,
      unitsPerPacket: item.unitsPerPacket,
      entryPasswordHash: item.entryPasswordHash,
      costPrice: item.costPrice,
      sellingPrice: item.sellingPrice,
      imagePath: item.imagePath,
      listed: item.listed,
      createdAt: item.createdAt,
      menuSortOrder: item.menuSortOrder,
      variantGroup:
          clearVariantGroup ? null : (variantGroup ?? item.variantGroup),
      variantLabel:
          clearVariantLabel ? null : (variantLabel ?? item.variantLabel),
      stockSourceId:
          clearStockSource ? null : (stockSourceId ?? item.stockSourceId),
    );
  }

  /// Applies sub_item stock pools, POS variant groups, and stock_source_id.
  static List<RawMaterial> syncVariantLinks(
    List<RawMaterial> items, {
    Map<int, String>? categoryNameById,
  }) {
    final categories = categoryNameById ?? _categoryNameById(items);

    final planned = <int, RawMaterial>{};
    for (final item in items) {
      if (item.id != null) planned[item.id!] = item;
    }

    final stockPools = <String, List<RawMaterial>>{};
    for (final item in items) {
      final key = SubItemStock.stockKey(item);
      if (key == null || key.isEmpty) continue;
      final categoryName = categories[item.categoryId];
      if (SubItemStock.isComponentReference(item, categoryName)) continue;
      stockPools.putIfAbsent(key, () => []).add(item);
    }

    for (final entry in stockPools.entries) {
      final family = entry.value;
      if (family.length < 2) continue;
      final source = SubItemStock.canonicalHolder(
        family,
        stockKey: entry.key,
      );
      if (source == null || source.id == null) continue;

      for (final item in family) {
        if (item.id == null) continue;
        final isSource = item.id == source.id;
        planned[item.id!] = _copyWithLinks(
          planned[item.id!] ?? item,
          stockSourceId: isSource ? null : source.id,
          clearStockSource: isSource,
        );
      }
    }

    for (final item in items) {
      final categoryName = categories[item.categoryId];
      if (!SubItemStock.isComponentReference(item, categoryName)) continue;
      final sub = item.subItem?.trim().toLowerCase() ?? '';
      if (sub.isEmpty) continue;
      final patty = items.where(
        (candidate) =>
            candidate.name.trim().toLowerCase() == sub &&
            candidate.id != item.id,
      );
      final holder = patty.isNotEmpty ? patty.first : null;
      if (holder?.id == null || item.id == null) continue;
      planned[item.id!] = _copyWithLinks(
        planned[item.id!] ?? item,
        stockSourceId: holder!.id,
      );
    }

    final posGroups = <String, List<RawMaterial>>{};
    for (final item in planned.values) {
      if (!item.listed) continue;
      final key = SubItemStock.posGroupKey(item);
      posGroups.putIfAbsent(key, () => []).add(item);
    }

    for (final entry in posGroups.entries) {
      final family = entry.value;
      if (family.any(
        (item) => SubItemStock.isComponentReference(
          item,
          categories[item.categoryId],
        ),
      )) {
        continue;
      }
      if (!SubItemStock.shouldGroupOnPos(family)) continue;

      final stockKey = SubItemStock.stockKey(family.first) ?? '';
      final source = SubItemStock.canonicalHolder(
        family,
        stockKey: stockKey,
      );
      if (source == null) continue;

      final groupName = source.name.trim().isNotEmpty
          ? source.name.trim()
          : (source.subItem?.trim() ?? stockKey);
      if (groupName.isEmpty) continue;

      for (final item in family) {
        if (item.id == null) continue;
        final isSource = item.id == source.id;
        final sizeLabel = item.variantLabel?.trim();
        final derivedLabel = looksLikeSizeVariant(item) && !isSource
            ? _sizeLabel(item)
            : null;
        planned[item.id!] = _copyWithLinks(
          planned[item.id!] ?? item,
          variantGroup: groupName,
          variantLabel: isSource
              ? (sizeLabel ?? 'Regular')
              : (sizeLabel ?? derivedLabel ?? item.name),
          stockSourceId: planned[item.id!]?.stockSourceId,
        );
      }
    }

    final familyKeys = <String>{};
    for (final item in planned.values) {
      final key = productFamilyKey(item);
      if (key != null && key.isNotEmpty) familyKeys.add(key);
    }

    for (final familyKey in familyKeys) {
      final family = _familyForKey(familyKey, planned.values.toList());
      if (!shouldAutoLinkFamily(family)) continue;

      final source = canonicalStockSource(family, familyKey: familyKey);
      if (source == null || source.id == null) continue;

      final groupName = source.name.trim().isNotEmpty
          ? source.name.trim()
          : (source.subItem?.trim() ?? familyKey);
      if (groupName.isEmpty) continue;

      for (final item in family) {
        if (item.id == null) continue;
        final isSource = item.id == source.id;
        final sizeLabel = item.variantLabel?.trim();
        final derivedLabel = looksLikeSizeVariant(item) && !isSource
            ? _sizeLabel(item)
            : null;
        planned[item.id!] = _copyWithLinks(
          planned[item.id!] ?? item,
          variantGroup: groupName,
          variantLabel: isSource
              ? (sizeLabel ?? 'Regular')
              : (sizeLabel ?? derivedLabel ?? item.name),
          stockSourceId: isSource
              ? null
              : (planned[item.id!]?.stockSourceId ?? source.id),
          clearStockSource: isSource,
        );
      }
    }

    final groupedIds = <int>{};
    for (final entry in posGroups.entries) {
      final family = entry.value;
      if (family.any(
        (item) => SubItemStock.isComponentReference(
          item,
          categories[item.categoryId],
        ),
      )) {
        continue;
      }
      if (!SubItemStock.shouldGroupOnPos(family)) continue;
      for (final item in family) {
        if (item.id != null) groupedIds.add(item.id!);
      }
    }
    for (final familyKey in familyKeys) {
      final family = _familyForKey(familyKey, planned.values.toList());
      if (!shouldAutoLinkFamily(family)) continue;
      for (final item in family) {
        if (item.id != null) groupedIds.add(item.id!);
      }
    }

    for (final item in items) {
      if (item.id == null) continue;
      if (groupedIds.contains(item.id)) continue;
      planned[item.id!] = _copyWithLinks(
        planned[item.id!] ?? item,
        clearVariantGroup: true,
        clearVariantLabel: true,
      );
    }

    final updates = <RawMaterial>[];
    for (final item in items) {
      if (item.id == null) continue;
      final next = planned[item.id!] ?? item;
      if (next.variantGroup != item.variantGroup ||
          next.variantLabel != item.variantLabel ||
          next.stockSourceId != item.stockSourceId) {
        updates.add(next);
      }
    }

    return updates;
  }

  static String _sizeLabel(RawMaterial item) {
    final name = item.name.trim();
    final match = _sizeVariantPattern.firstMatch(name.toLowerCase());
    if (match == null) return name;
    final start = match.start;
    return name.substring(start).trim();
  }

  @Deprecated('Use syncVariantLinks')
  static List<RawMaterial> applyAutoVariantLinking(List<RawMaterial> items) {
    return syncVariantLinks(items);
  }
}
