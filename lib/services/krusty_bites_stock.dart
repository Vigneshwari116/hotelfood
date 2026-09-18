import 'package:foodstock/model/models.dart';

/// Krusty Bites–specific stock pooling rules.
///
/// When this item has a stock source, it must not track its own stock — sales
/// deduct from the source item (e.g. Chicken 65) only.
class KrustyBitesStock {
  KrustyBitesStock._();

  static bool isKrustyBites(RawMaterial item) {
    return item.name.trim().toLowerCase() == 'krusty bites';
  }

  static bool isKrustyBitesName(String name) {
    return name.trim().toLowerCase() == 'krusty bites';
  }

  /// True when Krusty Bites should not maintain its own stock row.
  static bool usesStockSourcePool(
    RawMaterial item, {
    String stockSourceName = '',
  }) {
    if (!isKrustyBites(item)) return false;
    if (item.stockSourceId != null) return true;
    return stockSourceName.trim().isNotEmpty;
  }

  /// Returns [item] with own stock fields cleared for persistence/display.
  static RawMaterial withZeroOwnStock(RawMaterial item) {
    if (!isKrustyBites(item)) return item;
    return RawMaterial(
      id: item.id,
      barcode: item.barcode,
      name: item.name,
      subItem: item.subItem,
      qtyNeeded: item.qtyNeeded,
      categoryId: item.categoryId,
      unitId: item.unitId,
      openingStock: 0,
      openingPieces: 0,
      currentStock: 0,
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
}
