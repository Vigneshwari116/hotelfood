import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/variant_helpers.dart';

void main() {
  group('stock_source_id preservation', () {
    test('syncVariantLinks keeps manual same-location stock_source_id', () {
      final gtChicken = RawMaterial(
        id: 4,
        name: 'Chicken 65',
        subItem: 'chicken 65',
        locationId: 1,
        categoryId: 1,
      );
      final localChicken = RawMaterial(
        id: 843,
        name: 'Chicken 65',
        subItem: 'chicken 65',
        locationId: 3,
        categoryId: 1,
      );
      final krusty = RawMaterial(
        id: 856,
        name: 'Krusty Bites',
        subItem: 'chicken 65',
        locationId: 3,
        categoryId: 2,
        stockSourceId: 843,
      );

      final updates = VariantHelpers.syncVariantLinks(
        [gtChicken, localChicken, krusty],
        categoryNameById: {1: 'Snacks', 2: 'Fried Items'},
      );

      expect(updates, isEmpty);
    });

    test('syncVariantLinks does not assign cross-location stock_source_id', () {
      final gtChicken = RawMaterial(
        id: 4,
        name: 'Chicken 65',
        subItem: 'chicken 65',
        locationId: 1,
        categoryId: 1,
      );
      final krusty = RawMaterial(
        id: 856,
        name: 'Krusty Bites',
        subItem: 'chicken 65',
        locationId: 3,
        categoryId: 2,
      );
      final localChicken = RawMaterial(
        id: 843,
        name: 'Chicken 65',
        subItem: 'chicken 65',
        locationId: 3,
        categoryId: 1,
      );

      final updates = VariantHelpers.syncVariantLinks(
        [gtChicken, localChicken, krusty],
        categoryNameById: {1: 'Snacks', 2: 'Fried Items'},
      );

      final krustyUpdate = updates.firstWhere((item) => item.id == 856);
      expect(krustyUpdate.stockSourceId, 843);
      expect(krustyUpdate.stockSourceId, isNot(4));
    });

    test('syncVariantLinks still auto-links when stock_source_id is null', () {
      final chicken65 = RawMaterial(
        id: 795,
        name: 'Chicken 65',
        subItem: 'chicken 65',
        locationId: 2,
        categoryId: 1,
      );
      final krusty = RawMaterial(
        id: 808,
        name: 'Krusty Bites',
        subItem: 'chicken 65',
        locationId: 2,
        categoryId: 2,
      );

      final updates = VariantHelpers.syncVariantLinks(
        [chicken65, krusty],
        categoryNameById: {1: 'Snacks', 2: 'Fried Items'},
      );

      final krustyUpdate = updates.firstWhere((item) => item.id == 808);
      expect(krustyUpdate.stockSourceId, 795);
    });
  });
}
