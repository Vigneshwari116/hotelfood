import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/item_import_service.dart';

void main() {
  group('staff labels', () {
    test('prefers sub-item name for staff display', () {
      final item = RawMaterial(
        name: 'star burger',
        subItem: 'Crispy Chicken Patty',
      );
      expect(item.staffLabel, 'Crispy Chicken Patty');
    });

    test('falls back to item name when sub-item missing', () {
      final item = RawMaterial(name: 'Chicken 65');
      expect(item.staffLabel, 'Chicken 65');
    });
  });

  group('import grouping tags', () {
    test('treats sauce/dry stock tag as hidden from sales', () {
      expect(
        ItemImportService.shouldHideFromSales(
          groupingTag: 'SAUCE/DRY STOCK',
          name: 'BBQ Seasoning',
          subItem: 'BBQ Seasoning',
          category: 'Sauces',
        ),
        isTrue,
      );
    });

    test('keeps sellable snacks visible', () {
      expect(
        ItemImportService.shouldHideFromSales(
          groupingTag: 'SNACKS',
          name: 'Chicken 65',
          subItem: 'Chicken 65',
          category: 'Snacks',
        ),
        isFalse,
      );
    });

    test('hides combo components like paratha and bun', () {
      expect(
        ItemImportService.shouldHideFromSales(
          groupingTag: 'COMBO',
          name: 'Paratha',
          subItem: 'Paratha',
          category: '',
        ),
        isTrue,
      );
    });

    test('does not treat numeric barcode as grouping tag', () {
      expect(ItemImportService.isGroupingTag('10'), isFalse);
      expect(ItemImportService.isGroupingTag('SNACKS'), isTrue);
      expect(ItemImportService.isGroupingTag('SAUCE/DRY STOCK'), isTrue);
    });
  });

  group('beverages category alias', () {
    test('maps bevarges typo to Beverages', () {
      expect(
        ItemImportService.canonicalMenuCategory('BEVARGES'),
        'Beverages',
      );
    });
  });

  group('purchase packet amount', () {
    double amount({
      required double packets,
      required double? unitsPerPacket,
      required double quantity,
      required double rate,
    }) {
      if (packets > 0 && unitsPerPacket != null && unitsPerPacket > 0) {
        return packets * rate;
      }
      return quantity * rate;
    }

    test('packet purchase totals packets times rate per packet', () {
      expect(
        amount(
          packets: 10,
          unitsPerPacket: 500,
          quantity: 5000,
          rate: 500,
        ),
        5000,
      );
    });
  });
}
