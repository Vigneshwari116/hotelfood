import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/menu_item_edit_helpers.dart';

void main() {
  group('MenuItemEditHelpers', () {
    test('stockFromPacketsAndUnitsPerPacket multiplies correctly', () {
      expect(
        MenuItemEditHelpers.stockFromPacketsAndUnitsPerPacket(
          packetsText: '6',
          unitsPerPacketText: '15',
        ),
        90,
      );
    });

    test('stockFromPacketsAndUnitsPerPacket adds opening pieces', () {
      expect(
        MenuItemEditHelpers.stockFromPacketsAndUnitsPerPacket(
          packetsText: '1',
          unitsPerPacketText: '20',
          openingPiecesText: '18',
        ),
        38,
      );
    });

    test('packetsTextFromStock subtracts opening pieces before dividing', () {
      expect(
        MenuItemEditHelpers.packetsTextFromStock(
          38,
          20,
          openingPieces: 18,
        ),
        '1',
      );
    });

    test('captureGridRowSnapshot detects stock source link as a change', () {
      final before = MenuItemEditHelpers.captureGridRowSnapshot(
        barcodeText: '',
        itemName: 'Krusty Bites',
        subItemText: 'chicken 65',
        variantGroupText: '',
        variantLabelText: '',
        stockSourceNameText: '',
        qtyPerSaleText: '1',
        packetsText: '',
        openingPiecesText: '',
        unitsPerPacketText: '90',
        stockText: '0',
        costPriceText: '',
        sellingPriceText: '99',
        unitId: null,
      );
      final after = MenuItemEditHelpers.captureGridRowSnapshot(
        barcodeText: '',
        itemName: 'Krusty Bites',
        subItemText: 'chicken 65',
        variantGroupText: '',
        variantLabelText: '',
        stockSourceNameText: 'Chicken 65',
        qtyPerSaleText: '1',
        packetsText: '',
        openingPiecesText: '',
        unitsPerPacketText: '90',
        stockText: '0',
        costPriceText: '',
        sellingPriceText: '99',
        unitId: null,
      );

      expect(before == after, isFalse);
    });

    test('buildForSave keeps qty per sale separate from units per packet', () {
      final existing = RawMaterial(
        id: 1,
        name: 'Chicken 65',
        subItem: 'Chicken 65',
        qtyNeeded: 1,
        unitsPerPacket: 15,
        currentStock: 90,
        openingStock: 90,
      );

      final saved = MenuItemEditHelpers.buildForSave(
        existing: existing,
        barcodeText: '',
        itemName: 'Chicken 65',
        subItemText: 'Chicken 65',
        qtyPerSaleText: '1',
        packetsText: '6',
        unitsPerPacketText: '90',
        openingPiecesText: '',
        stockText: '90',
        costPriceText: '10',
        sellingPriceText: '20',
        unitId: 1,
      );

      expect(saved.qtyNeeded, 1);
      expect(saved.unitsPerPacket, 90);
      expect(saved.currentStock, 540);
    });

    test('buildForSave uses direct stock when packets are blank', () {
      final existing = RawMaterial(
        id: 2,
        name: 'Tea',
        currentStock: 25,
        openingStock: 25,
      );

      final saved = MenuItemEditHelpers.buildForSave(
        existing: existing,
        barcodeText: '',
        itemName: 'Tea',
        subItemText: 'Tea',
        qtyPerSaleText: '1',
        packetsText: '',
        unitsPerPacketText: '',
        openingPiecesText: '5',
        stockText: '25',
        costPriceText: '',
        sellingPriceText: '15',
        unitId: null,
      );

      expect(saved.currentStock, 5);
      expect(saved.openingPieces, 5);
      expect(saved.unitsPerPacket, isNull);
    });
  });
}
