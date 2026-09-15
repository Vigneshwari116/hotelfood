import 'package:foodstock/model/models.dart';

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
    final byGroup = <String, List<RawMaterial>>{};
    final singles = <RawMaterial>[];

    for (final material in linked) {
      final groupKey = material.variantGroup?.trim();
      if (groupKey == null || groupKey.isEmpty) {
        singles.add(material);
        continue;
      }
      byGroup.putIfAbsent(groupKey, () => []).add(material);
    }

    final groups = <VariantGroup>[];
    for (final entry in byGroup.entries) {
      final variants = List<RawMaterial>.from(entry.value);
      if (variants.length < 2 || !shouldAutoLinkFamily(variants)) {
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

      final stockSource = variants.firstWhere(
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

  /// Applies or clears variant_group / stock_source_id / variant_label.
  static List<RawMaterial> syncVariantLinks(List<RawMaterial> items) {
    final familyKeys = <String>{};
    for (final item in items) {
      final key = productFamilyKey(item);
      if (key != null && key.isNotEmpty) {
        familyKeys.add(key);
      }
    }

    final updates = <RawMaterial>[];
    final linkedIds = <int>{};

    for (final familyKey in familyKeys) {
      final family = _familyForKey(familyKey, items);
      if (!shouldAutoLinkFamily(family)) continue;

      final source = canonicalStockSource(family, familyKey: familyKey);
      if (source == null || source.id == null) continue;

      final groupName = source.name.trim().isNotEmpty
          ? source.name.trim()
          : (source.subItem?.trim() ?? familyKey);
      if (groupName.isEmpty) continue;

      for (final item in family) {
        if (item.id == null) continue;
        linkedIds.add(item.id!);

        final isSource = item.id == source.id;
        final sizeLabel = item.variantLabel?.trim();
        final derivedLabel = looksLikeSizeVariant(item) && !isSource
            ? _sizeLabel(item)
            : null;
        final next = RawMaterial(
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
          variantGroup: groupName,
          variantLabel: isSource
              ? (sizeLabel ?? 'Regular')
              : (sizeLabel ?? derivedLabel ?? item.name),
          stockSourceId: isSource ? null : source.id,
        );

        if (next.variantGroup != item.variantGroup ||
            next.variantLabel != item.variantLabel ||
            next.stockSourceId != item.stockSourceId) {
          updates.add(next);
        }
      }
    }

    for (final item in items) {
      if (item.id == null) continue;
      if (item.variantGroup == null && item.stockSourceId == null) continue;
      if (linkedIds.contains(item.id)) continue;

      updates.add(
        RawMaterial(
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
          variantGroup: null,
          variantLabel: null,
          stockSourceId: null,
        ),
      );
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
