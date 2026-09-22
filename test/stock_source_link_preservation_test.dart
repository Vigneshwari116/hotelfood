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
        listed: true,
      );
      final krusty = RawMaterial(
        id: 856,
        name: 'Krusty Bites',
        subItem: 'chicken 65',
        locationId: 3,
        categoryId: 2,
        stockSourceId: 843,
        listed: true,
      );

      final updates = VariantHelpers.syncVariantLinks(
        [gtChicken, localChicken, krusty],
        categoryNameById: {1: 'Snacks', 2: 'Fried Items'},
      );

      expect(updates, isEmpty);
    });

    test(
      'syncVariantLinks keeps Krusty link when POS group would elect it holder',
      () {
        final localChicken = RawMaterial(
          id: 843,
          name: 'Chicken 65',
          subItem: 'chicken 65',
          locationId: 3,
          categoryId: 1,
          listed: true,
        );
        final krusty = RawMaterial(
          id: 856,
          name: 'Krusty Bites',
          subItem: 'chicken 65',
          locationId: 3,
          categoryId: 2,
          stockSourceId: 843,
          listed: true,
        );
        final friedPeer = RawMaterial(
          id: 883,
          name: 'Fried peer A',
          subItem: 'chicken 65',
          locationId: 3,
          categoryId: 2,
          stockSourceId: 848,
          listed: true,
        );
        final friedPeerB = RawMaterial(
          id: 880,
          name: 'Fried peer B',
          subItem: 'chicken 65',
          locationId: 3,
          categoryId: 2,
          stockSourceId: 849,
          listed: true,
        );
        final holder848 = RawMaterial(
          id: 848,
          name: 'Holder848',
          subItem: 'x',
          locationId: 3,
          categoryId: 1,
          listed: true,
        );
        final holder849 = RawMaterial(
          id: 849,
          name: 'Holder849',
          subItem: 'y',
          locationId: 3,
          categoryId: 1,
          listed: true,
        );

        final items = [
          localChicken,
          krusty,
          friedPeer,
          friedPeerB,
          holder848,
          holder849,
        ];

        final updates = VariantHelpers.syncVariantLinks(
          items,
          categoryNameById: {1: 'Snacks', 2: 'Fried Items'},
        );

        final krustyUpdate = updates.where((item) => item.id == 856).toList();
        expect(krustyUpdate, isEmpty);

        final linked = VariantHelpers.withSyncedLinks(items);
        final byId = {
          for (final item in linked)
            if (item.id != null) item.id!: item,
        };
        expect(byId[856]?.stockSourceId, 843);
        expect(byId[883]?.stockSourceId, 848);
        expect(byId[880]?.stockSourceId, 849);
      },
    );

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
