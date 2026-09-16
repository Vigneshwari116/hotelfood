import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/pos_free_addons.dart';

void main() {
  group('PosFreeAddons', () {
    test('treats Sauces category as free POS add-on', () {
      final mayo = RawMaterial(
        id: 1,
        name: 'Tandoori Mayonnaise',
        subItem: 'Tandoori Mayonnaise',
        categoryId: 5,
      );

      expect(
        PosFreeAddons.isFreeAddOn(
          mayo,
          categoryNameFor: (_) => 'Sauces',
        ),
        isTrue,
      );
    });

    test('does not treat snacks as free add-on', () {
      final snack = RawMaterial(
        id: 2,
        name: 'Chicken 65',
        categoryId: 3,
      );

      expect(
        PosFreeAddons.isFreeAddOn(
          snack,
          categoryNameFor: (_) => 'Snacks',
        ),
        isFalse,
      );
    });
  });

  group('import visibility for sauces', () {
    test('lists sauce/dry stock rows for POS', () {
      expect(
        ItemImportService.shouldHideFromSales(
          groupingTag: 'SAUCE/DRY STOCK',
          name: 'BBQ Seasoning',
          subItem: 'BBQ Seasoning',
          category: 'Sauces',
        ),
        isFalse,
      );
    });

    test('still hides combo components like paratha by name', () {
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
  });
}
