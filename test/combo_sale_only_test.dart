import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/combo_only_categories.dart';

void main() {
  group('combo-sale-only categories', () {
    test('Burgers and Rolls are combo-sale-only by name', () {
      expect(ComboOnlyCategories.isComboSaleOnlyCategoryName('Burgers'), isTrue);
      expect(ComboOnlyCategories.isComboSaleOnlyCategoryName('rolls'), isTrue);
      expect(ComboOnlyCategories.isComboSaleOnlyCategoryName('Snacks'), isFalse);
    });

    test('POS hides Burgers and Rolls standalone materials by category name', () {
      final burger = RawMaterial(
        id: 10,
        name: 'Hot Crispy burger',
        categoryId: 1,
        listed: true,
      );

      expect(
        ComboOnlyCategories.isPosStandaloneMaterial(
          burger,
          comboOnlyCategoryIds: const {},
          categoryNameFor: (_) => 'Burgers',
        ),
        isFalse,
      );
    });

    test('POS hides standalone materials in Rolls but keeps combo chips', () {
      final materials = [
        RawMaterial(id: 1, name: 'Krisper roll', categoryId: 3, listed: true),
        RawMaterial(id: 2, name: 'Chicken roll', categoryId: 3, listed: true),
        RawMaterial(id: 3, name: 'Popcorn', categoryId: 4, listed: true),
      ];
      final combos = [
        Combo(
          id: 1,
          name: 'Tandoori roll combo',
          price: 99,
          categoryId: 3,
          items: [
            ComboItem(comboId: 1, rawMaterialId: 1, qty: 1),
          ],
        ),
      ];

      String? nameFor(int? id) {
        switch (id) {
          case 3:
            return 'Rolls';
          case 4:
            return 'Snacks';
          default:
            return null;
        }
      }

      expect(
        materials.where(
          (m) => ComboOnlyCategories.isPosStandaloneMaterial(
            m,
            comboOnlyCategoryIds: const {},
            categoryNameFor: nameFor,
          ),
        ).map((m) => m.id).toList(),
        [3],
      );

      final visible = ComboOnlyCategories.posVisibleCategoryIds(
        materials: materials,
        combos: combos,
        categoryNameFor: nameFor,
      );
      expect(visible, {3, 4});
    });
  });
}
