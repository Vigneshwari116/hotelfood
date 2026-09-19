import 'package:foodstock/model/models.dart';

/// Shared menu-item field logic for the Edit Item dialog and grid view.
class MenuItemEditHelpers {
  MenuItemEditHelpers._();

  static String formatNumber(double value) {
    return value % 1 == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  static String? packetsTextFromStock(
    double stock,
    double? unitsPerPacket, {
    double openingPieces = 0,
  }) {
    if (unitsPerPacket == null || unitsPerPacket <= 0) {
      return null;
    }
    final packetStock = stock - openingPieces;
    if (packetStock <= 0) {
      return '0';
    }
    return formatNumber(packetStock / unitsPerPacket);
  }

  static double? stockFromPacketsAndUnitsPerPacket({
    required String packetsText,
    required String unitsPerPacketText,
    String openingPiecesText = '',
  }) {
    final packets = double.tryParse(packetsText.trim()) ?? 0;
    final unitsPerPacket = double.tryParse(unitsPerPacketText.trim()) ?? 0;
    final openingPieces = double.tryParse(openingPiecesText.trim()) ?? 0;
    if (unitsPerPacket <= 0 && packets <= 0 && openingPieces <= 0) {
      return null;
    }
    return (packets * unitsPerPacket) + openingPieces;
  }

  /// Stable field snapshot for grid dirty-state tracking (also used in tests).
  static String captureGridRowSnapshot({
    required String barcodeText,
    required String itemName,
    required String subItemText,
    required String variantGroupText,
    required String variantLabelText,
    required String stockSourceNameText,
    required String qtyPerSaleText,
    required String packetsText,
    required String openingPiecesText,
    required String unitsPerPacketText,
    required String stockText,
    required String costPriceText,
    required String sellingPriceText,
    required int? unitId,
  }) {
    return [
      barcodeText,
      itemName,
      subItemText,
      variantGroupText,
      variantLabelText,
      stockSourceNameText,
      qtyPerSaleText,
      packetsText,
      openingPiecesText,
      unitsPerPacketText,
      stockText,
      costPriceText,
      sellingPriceText,
      unitId?.toString() ?? '',
    ].join('\u0001');
  }

  static RawMaterial buildForSave({
    required RawMaterial existing,
    required String barcodeText,
    required String itemName,
    required String subItemText,
    required String qtyPerSaleText,
    required String packetsText,
    required String unitsPerPacketText,
    required String openingPiecesText,
    required String stockText,
    required String costPriceText,
    required String sellingPriceText,
    required int? unitId,
    String? variantGroupText,
    String? variantLabelText,
    int? stockSourceId,
    bool clearStockSource = false,
  }) {
    final name = itemName.trim();
    final subItem = subItemText.trim().isEmpty ? name : subItemText.trim();

    final unitsPerPacket = unitsPerPacketText.trim().isEmpty
        ? null
        : double.tryParse(unitsPerPacketText.trim());

    final openingPieces = double.tryParse(openingPiecesText.trim()) ?? 0;

    final recalculatedStock = stockFromPacketsAndUnitsPerPacket(
      packetsText: packetsText,
      unitsPerPacketText: unitsPerPacketText,
      openingPiecesText: openingPiecesText,
    );

    final parsedStock = double.tryParse(stockText.trim()) ?? 0;
    final currentStock = recalculatedStock ?? parsedStock;

    final variantGroup = (variantGroupText ?? existing.variantGroup ?? '')
        .trim();
    final variantLabel = (variantLabelText ?? existing.variantLabel ?? '')
        .trim();

    return RawMaterial(
      id: existing.id,
      barcode: barcodeText.trim().isEmpty ? null : barcodeText.trim(),
      name: name,
      subItem: subItem.isEmpty ? null : subItem,
      qtyNeeded: double.tryParse(qtyPerSaleText.trim()) ?? 1,
      categoryId: existing.categoryId,
      unitId: unitId,
      openingStock: currentStock,
      openingPieces: openingPieces,
      currentStock: currentStock,
      reorderLevel: existing.reorderLevel,
      shelfLifeDays: existing.shelfLifeDays,
      unitsPerPacket: unitsPerPacket,
      entryPasswordHash: existing.entryPasswordHash,
      costPrice: costPriceText.trim().isEmpty
          ? null
          : double.tryParse(costPriceText.trim()),
      sellingPrice: sellingPriceText.trim().isEmpty
          ? null
          : double.tryParse(sellingPriceText.trim()),
      imagePath: existing.imagePath,
      listed: existing.listed,
      createdAt: existing.createdAt,
      menuSortOrder: existing.menuSortOrder,
      variantGroup: variantGroup.isEmpty ? null : variantGroup,
      variantLabel: variantLabel.isEmpty ? null : variantLabel,
      stockSourceId:
          clearStockSource ? null : (stockSourceId ?? existing.stockSourceId),
      locationId: existing.locationId,
    );
  }

  /// Resolves a grid stock-source name to a raw material id within the grid.
  static int? resolveStockSourceIdFromGrid({
    required String stockSourceNameText,
    required int? selfItemId,
    required Iterable<RawMaterial> menuItems,
  }) {
    final sourceName = stockSourceNameText.trim().toLowerCase();
    if (sourceName.isEmpty) return null;

    for (final item in menuItems) {
      if (item.id == null || item.id == selfItemId) continue;
      if (item.name.trim().toLowerCase() == sourceName) {
        return item.id;
      }
      final sub = item.subItem?.trim().toLowerCase();
      if (sub != null && sub.isNotEmpty && sub == sourceName) {
        return item.id;
      }
      if (item.staffLabel.trim().toLowerCase() == sourceName) {
        return item.id;
      }
    }
    return null;
  }
}
