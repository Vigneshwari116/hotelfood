import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/menu_item_edit_helpers.dart';
import 'package:foodstock/services/variant_helpers.dart';

RawMaterial _krustyForGridSave({
  required int? stockSourceId,
}) {
  return RawMaterial(
    id: 856,
    name: 'Krusty Bites',
    subItem: 'chicken 65',
    locationId: 3,
    categoryId: 2,
    stockSourceId: stockSourceId,
    listed: true,
    qtyNeeded: 1,
    unitId: 2,
  );
}

RawMaterial _buildKrustyViaGridClear(RawMaterial existing) {
  return MenuItemEditHelpers.buildForSave(
    existing: existing,
    barcodeText: '',
    itemName: 'Krusty Bites',
    subItemText: 'chicken 65',
    qtyPerSaleText: '1',
    packetsText: '0',
    unitsPerPacketText: '90',
    openingPiecesText: '',
    stockText: '0',
    costPriceText: '',
    sellingPriceText: '99',
    unitId: 2,
    variantGroupText: '',
    variantLabelText: '',
    stockSourceId: null,
    clearStockSource: true,
  );
}

void main() {
  group('stock_source_id preservation', () {
    test('CASE A: syncVariantLinks keeps manual 856→843', () {
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

      final linked = VariantHelpers.withSyncedLinks([localChicken, krusty]);
      final byId = {
        for (final item in linked)
          if (item.id != null) item.id!: item,
      };
      expect(byId[856]?.stockSourceId, 843);
    });

    test(
      'grid save path keeps 856→NULL when user clears stock source field',
      () {
        final cleared = _buildKrustyViaGridClear(
          _krustyForGridSave(stockSourceId: 843),
        );
        expect(cleared.stockSourceId, isNull);
      },
    );

    test(
      'CASE B: syncVariantLinks cannot keep intentional clear as NULL',
      () {
        // RawMaterial has no persisted flag for "user cleared stock source".
        // stockSourceId == null is identical to "never linked" and to a true
        // pool holder (holder rows also use null). syncVariantLinks therefore
        // re-applies sub_item pooling and proposes Chicken 65 again.
        final localChicken = RawMaterial(
          id: 843,
          name: 'Chicken 65',
          subItem: 'chicken 65',
          locationId: 3,
          categoryId: 1,
          listed: true,
        );
        final krustyCleared = _buildKrustyViaGridClear(
          _krustyForGridSave(stockSourceId: 843),
        );
        expect(krustyCleared.stockSourceId, isNull);

        final updates = VariantHelpers.syncVariantLinks(
          [localChicken, krustyCleared],
          categoryNameById: {1: 'Snacks', 2: 'Fried Items'},
        );

        final krustyUpdate = updates.firstWhere((item) => item.id == 856);
        expect(krustyUpdate.stockSourceId, 843);
      },
    );

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

        for (final row in updates.where((item) => item.id == 856)) {
          expect(row.stockSourceId, 843);
        }

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
