import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/sub_item_stock.dart';
import 'package:foodstock/services/variant_helpers.dart';

void main() {
  group('SubItemStock', () {
    test('pools stock for items sharing sub_item across names', () {
      final chicken65 = RawMaterial(
        id: 1,
        name: 'Chicken 65',
        subItem: 'chicken 65',
        categoryId: 1,
      );
      final krusty = RawMaterial(
        id: 2,
        name: 'Krusty Bites',
        subItem: 'chicken 65',
        categoryId: 1,
      );

      final updates = VariantHelpers.syncVariantLinks(
        [chicken65, krusty],
        categoryNameById: {1: 'Snacks'},
      );

      expect(updates.length, 2);
      final krustyUpdate = updates.firstWhere((item) => item.id == 2);
      expect(krustyUpdate.stockSourceId, 1);
    });

    test('normalizeIngredientKey fixes panner and plural fingers', () {
      expect(
        SubItemStock.normalizeIngredientKey('panner patty'),
        SubItemStock.normalizeIngredientKey('Paneer Patty'),
      );
      expect(
        SubItemStock.normalizeIngredientKey('veg fingers'),
        SubItemStock.normalizeIngredientKey('Veg Finger'),
      );
    });

    test('isMergeableIngredientRow keeps sellable burgers separate from patties', () {
      final burger = RawMaterial(
        id: 1,
        name: 'Hot Crispy burger',
        subItem: 'Hot Crispy Patty',
        listed: true,
      );
      final patty = RawMaterial(
        id: 2,
        name: 'Hot Crispy Patty',
        subItem: 'Hot Crispy Patty',
        listed: true,
      );

      expect(
        SubItemStock.isMergeableIngredientRow(
          burger,
          comboComponentIds: const {},
        ),
        isFalse,
      );
      expect(
        SubItemStock.isMergeableIngredientRow(
          patty,
          comboComponentIds: const {},
        ),
        isTrue,
      );
    });

    test('keeps stock-linked sellable items visible without variant label', () {
      final chicken65 = RawMaterial(
        id: 1,
        name: 'Chicken 65',
        subItem: 'chicken 65',
        listed: true,
      );
      final krusty = RawMaterial(
        id: 2,
        name: 'Krusty Bites',
        subItem: 'chicken 65',
        stockSourceId: 1,
        listed: true,
      );
      final byId = {1: chicken65, 2: krusty};

      expect(SubItemStock.isListedStockShadow(krusty, byId), isFalse);
    });

    test('keeps explicit POS variants visible even when name matches sub_item pool', () {
      final holder = RawMaterial(
        id: 1,
        name: 'Thai Crispy',
        subItem: 'Thai Crispy',
        variantGroup: 'Thai Crispy',
        listed: true,
      );
      final mini = RawMaterial(
        id: 2,
        name: 'Mini Bucket',
        subItem: 'Thai Crispy',
        variantGroup: 'Thai Crispy',
        variantLabel: 'Mini Bucket',
        stockSourceId: 1,
        listed: true,
      );
      final big = RawMaterial(
        id: 3,
        name: 'Big Buckets',
        subItem: 'Big Buckets',
        variantGroup: 'Thai Crispy',
        variantLabel: 'Big Buckets',
        stockSourceId: 1,
        listed: true,
      );
      final byId = {1: holder, 2: mini, 3: big};

      expect(SubItemStock.isListedStockShadow(big, byId), isFalse);
      expect(SubItemStock.isListedStockShadow(mini, byId), isFalse);
    });

    test('does not group patty references on POS', () {
      final burger = RawMaterial(
        id: 1,
        name: 'Hot Crispy burger',
        subItem: 'Hot Crispy Patty',
        categoryId: 2,
        sellingPrice: 110,
      );
      final juicy = RawMaterial(
        id: 2,
        name: 'Big juicy burger',
        subItem: 'Hot Crispy Patty',
        categoryId: 2,
        sellingPrice: 129,
      );

      final result = VariantHelpers.partitionForPos([burger, juicy]);

      expect(result.groups, isEmpty);
      expect(result.singles.length, 2);
      expect(
        SubItemStock.isComponentReference(burger, 'Burgers'),
        isTrue,
      );
    });
  });
}
