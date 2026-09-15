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
