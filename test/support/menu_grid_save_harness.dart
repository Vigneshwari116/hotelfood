import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/krusty_bites_stock.dart';
import 'package:foodstock/services/menu_item_edit_helpers.dart';
import 'package:foodstock/services/repository.dart';

/// Field snapshot for the Menu Items Grid save path (mirrors [_MenuGridRow.buildItem]).
class MenuGridSaveFields {
  MenuGridSaveFields({
    required this.barcodeText,
    required this.itemName,
    required this.subItemText,
    required this.variantGroupText,
    required this.variantLabelText,
    required this.stockSourceNameText,
    required this.qtyPerSaleText,
    required this.packetsText,
    required this.openingPiecesText,
    required this.unitsPerPacketText,
    required this.stockText,
    required this.costPriceText,
    required this.sellingPriceText,
    required this.unitId,
  });

  factory MenuGridSaveFields.fromMaterial(
    RawMaterial item, {
    required List<RawMaterial> menuItems,
  }) {
    final stockSourceName = _stockSourceName(item, menuItems);
    final displayItem = KrustyBitesStock.usesStockSourcePool(
      item,
      stockSourceName: stockSourceName,
    )
        ? KrustyBitesStock.withZeroOwnStock(item)
        : item;

    return MenuGridSaveFields(
      barcodeText: item.barcode ?? '',
      itemName: item.name,
      subItemText: item.subItem ?? item.name,
      variantGroupText: item.variantGroup ?? '',
      variantLabelText: item.variantLabel ?? '',
      stockSourceNameText: stockSourceName,
      qtyPerSaleText: MenuItemEditHelpers.formatNumber(item.qtyNeeded),
      packetsText: MenuItemEditHelpers.packetsTextFromStock(
            displayItem.currentStock,
            displayItem.unitsPerPacket,
            openingPieces: displayItem.openingPieces,
          ) ??
          '',
      openingPiecesText: displayItem.openingPieces == 0
          ? ''
          : MenuItemEditHelpers.formatNumber(displayItem.openingPieces),
      unitsPerPacketText: item.unitsPerPacket == null
          ? ''
          : MenuItemEditHelpers.formatNumber(item.unitsPerPacket!),
      stockText: MenuItemEditHelpers.formatNumber(displayItem.currentStock),
      costPriceText: item.costPrice == null
          ? ''
          : MenuItemEditHelpers.formatNumber(item.costPrice!),
      sellingPriceText: item.sellingPrice == null
          ? ''
          : MenuItemEditHelpers.formatNumber(item.sellingPrice!),
      unitId: item.unitId,
    );
  }

  final String barcodeText;
  final String itemName;
  final String subItemText;
  final String variantGroupText;
  final String variantLabelText;
  final String stockSourceNameText;
  final String qtyPerSaleText;
  final String packetsText;
  final String openingPiecesText;
  final String unitsPerPacketText;
  final String stockText;
  final String costPriceText;
  final String sellingPriceText;
  final int? unitId;

  MenuGridSaveFields copyWith({
    String? barcodeText,
    String? itemName,
    String? subItemText,
    String? variantGroupText,
    String? variantLabelText,
    String? stockSourceNameText,
    String? qtyPerSaleText,
    String? packetsText,
    String? openingPiecesText,
    String? unitsPerPacketText,
    String? stockText,
    String? costPriceText,
    String? sellingPriceText,
    int? unitId,
  }) {
    return MenuGridSaveFields(
      barcodeText: barcodeText ?? this.barcodeText,
      itemName: itemName ?? this.itemName,
      subItemText: subItemText ?? this.subItemText,
      variantGroupText: variantGroupText ?? this.variantGroupText,
      variantLabelText: variantLabelText ?? this.variantLabelText,
      stockSourceNameText: stockSourceNameText ?? this.stockSourceNameText,
      qtyPerSaleText: qtyPerSaleText ?? this.qtyPerSaleText,
      packetsText: packetsText ?? this.packetsText,
      openingPiecesText: openingPiecesText ?? this.openingPiecesText,
      unitsPerPacketText: unitsPerPacketText ?? this.unitsPerPacketText,
      stockText: stockText ?? this.stockText,
      costPriceText: costPriceText ?? this.costPriceText,
      sellingPriceText: sellingPriceText ?? this.sellingPriceText,
      unitId: unitId ?? this.unitId,
    );
  }
}

String _stockSourceName(RawMaterial item, List<RawMaterial> menuItems) {
  final sourceId = item.stockSourceId;
  if (sourceId == null) return '';
  for (final candidate in menuItems) {
    if (candidate.id == sourceId) {
      return candidate.name;
    }
  }
  return '';
}

/// Builds the [RawMaterial] payload the grid would send to [Repository.saveRawMaterial].
RawMaterial buildMenuGridSavePayload({
  required RawMaterial existing,
  required List<RawMaterial> menuItems,
  required MenuGridSaveFields fields,
}) {
  final sourceName = fields.stockSourceNameText.trim();
  final stockSourceId = MenuItemEditHelpers.resolveStockSourceIdFromGrid(
    stockSourceNameText: sourceName,
    selfItemId: existing.id,
    menuItems: menuItems,
  );
  if (sourceName.isNotEmpty && stockSourceId == null) {
    throw StateError('Stock source "$sourceName" was not found on this menu grid.');
  }

  final built = MenuItemEditHelpers.buildForSave(
    existing: existing,
    barcodeText: fields.barcodeText,
    itemName: fields.itemName,
    subItemText: fields.subItemText,
    qtyPerSaleText: fields.qtyPerSaleText,
    packetsText: fields.packetsText,
    unitsPerPacketText: fields.unitsPerPacketText,
    openingPiecesText: fields.openingPiecesText,
    stockText: fields.stockText,
    costPriceText: fields.costPriceText,
    sellingPriceText: fields.sellingPriceText,
    unitId: fields.unitId,
    variantGroupText: fields.variantGroupText,
    variantLabelText: fields.variantLabelText,
    stockSourceId: stockSourceId,
    clearStockSource: sourceName.isEmpty,
  );
  if (KrustyBitesStock.usesStockSourcePool(
    built,
    stockSourceName: fields.stockSourceNameText,
  )) {
    return KrustyBitesStock.withZeroOwnStock(built);
  }
  return built;
}

/// Grid row save plus optional post-login style variant refresh.
Future<RawMaterial> saveThroughMenuGrid({
  required RawMaterial existing,
  required List<RawMaterial> menuItems,
  required MenuGridSaveFields fields,
  bool runVariantRefresh = false,
}) async {
  final payload = buildMenuGridSavePayload(
    existing: existing,
    menuItems: menuItems,
    fields: fields,
  );
  final id = existing.id;
  if (id == null) {
    throw StateError('Menu grid save regression tests require an existing id.');
  }

  await Repository.instance.saveRawMaterial(
    payload,
    fromGridSave: true,
  );
  if (runVariantRefresh) {
    await Repository.instance.refreshVariantLinks();
  }
  final reloaded = await Repository.instance.rawMaterialById(id);
  if (reloaded == null) {
    throw StateError('raw_material $id missing after grid save');
  }
  return reloaded;
}
