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
    double? unitsPerPacket,
  ) {
    if (unitsPerPacket == null ||
        unitsPerPacket <= 0 ||
        stock <= 0) {
      return null;
    }
    return formatNumber(stock / unitsPerPacket);
  }

  static double? stockFromPacketsAndUnitsPerPacket({
    required String packetsText,
    required String unitsPerPacketText,
  }) {
    final packets = double.tryParse(packetsText.trim()) ?? 0;
    final unitsPerPacket = double.tryParse(unitsPerPacketText.trim()) ?? 0;
    if (packets <= 0 || unitsPerPacket <= 0) return null;
    return packets * unitsPerPacket;
  }

  static RawMaterial buildForSave({
    required RawMaterial existing,
    required String barcodeText,
    required String itemName,
    required String subItemText,
    required String qtyPerSaleText,
    required String packetsText,
    required String unitsPerPacketText,
    required String stockText,
    required String costPriceText,
    required String sellingPriceText,
    required int? unitId,
  }) {
    final name = itemName.trim();
    final subItem = subItemText.trim();

    final unitsPerPacket = unitsPerPacketText.trim().isEmpty
        ? null
        : double.tryParse(unitsPerPacketText.trim());

    final recalculatedStock = stockFromPacketsAndUnitsPerPacket(
      packetsText: packetsText,
      unitsPerPacketText: unitsPerPacketText,
    );

    final parsedStock = double.tryParse(stockText.trim()) ?? 0;
    final currentStock = recalculatedStock ?? parsedStock;

    return RawMaterial(
      id: existing.id,
      barcode: barcodeText.trim().isEmpty ? null : barcodeText.trim(),
      name: name,
      subItem: subItem.isEmpty ? null : subItem,
      qtyNeeded: double.tryParse(qtyPerSaleText.trim()) ?? 1,
      categoryId: existing.categoryId,
      unitId: unitId,
      openingStock: existing.openingStock,
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
    );
  }
}
