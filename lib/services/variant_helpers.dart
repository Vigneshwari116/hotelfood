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

  /// Splits [materials] into standalone tiles and multi-variant groups.
  static ({
    List<RawMaterial> singles,
    List<VariantGroup> groups,
  }) partitionForPos(List<RawMaterial> materials) {
    final byGroup = <String, List<RawMaterial>>{};
    final singles = <RawMaterial>[];

    for (final material in materials) {
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
      if (variants.length < 2) {
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

      final byId = {for (final v in variants) if (v.id != null) v.id!: v};
      final stockSource = variants.firstWhere(
        (v) => v.stockSourceId == null,
        orElse: () => variants.first,
      );

      groups.add(
        VariantGroup(
          key: entry.key,
          displayName: entry.key,
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

  /// Picks the canonical stock owner when several items share a sub-item name.
  static RawMaterial? canonicalStockSource(List<RawMaterial> sameSubItem) {
    if (sameSubItem.isEmpty) return null;

    final subKey = sameSubItem.first.subItem?.trim().toLowerCase();
    if (subKey == null || subKey.isEmpty) return null;

    for (final item in sameSubItem) {
      if (item.name.trim().toLowerCase() == subKey) {
        return item;
      }
    }

    final withUnitStock = sameSubItem.where((item) => item.qtyNeeded == 1);
    if (withUnitStock.isNotEmpty) {
      return withUnitStock.first;
    }

    return sameSubItem.first;
  }

  /// Applies variant_group / stock_source_id / variant_label when multiple
  /// listed items share the same sub-item (e.g. Thai Crispy pieces + buckets).
  static List<RawMaterial> applyAutoVariantLinking(List<RawMaterial> items) {
    final bySubItem = <String, List<RawMaterial>>{};
    for (final item in items) {
      final sub = item.subItem?.trim().toLowerCase();
      if (sub == null || sub.isEmpty) continue;
      bySubItem.putIfAbsent(sub, () => []).add(item);
    }

    final updates = <RawMaterial>[];

    for (final entry in bySubItem.entries) {
      final family = entry.value;
      if (family.length < 2) continue;

      final source = canonicalStockSource(family);
      if (source == null || source.id == null) continue;

      final groupName = source.subItem?.trim() ?? source.name.trim();
      if (groupName.isEmpty) continue;

      for (final item in family) {
        if (item.id == null) continue;

        final isSource = item.id == source.id;
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
          variantLabel: item.variantLabel ?? item.name,
          stockSourceId: isSource ? null : source.id,
        );

        if (next.variantGroup != item.variantGroup ||
            next.variantLabel != item.variantLabel ||
            next.stockSourceId != item.stockSourceId) {
          updates.add(next);
        }
      }
    }

    return updates;
  }
}
