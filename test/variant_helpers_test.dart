import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/variant_helpers.dart';

void main() {
  group('VariantHelpers.partitionForPos', () {
    test('groups popcorn variants in memory even without stored variant_group', () {
      final base = RawMaterial(
        id: 1,
        name: 'Chicken Popcorn',
        sellingPrice: 75,
      );
      final small = RawMaterial(
        id: 2,
        name: 'Chicken Popcorn small',
        subItem: 'Chicken Popcorn',
        sellingPrice: 150,
      );
      final large = RawMaterial(
        id: 3,
        name: 'chicken popcorn large',
        subItem: 'Chicken Popcorn',
        sellingPrice: 200,
      );

      final result = VariantHelpers.partitionForPos([base, small, large]);

      expect(result.singles, isEmpty);
      expect(result.groups.length, 1);
      expect(result.groups.first.variants.length, 3);
      expect(result.groups.first.posTitle, 'Chicken Popcorn');
    });

    test('groups items with the same variant_group', () {
      final pieces = RawMaterial(
        id: 1,
        name: 'Thai Crispy',
        subItem: 'Thai Crispy',
        variantGroup: 'Thai Crispy',
        variantLabel: 'Pieces',
        sellingPrice: 70,
      );
      final mini = RawMaterial(
        id: 2,
        name: 'Mini Bucket',
        subItem: 'Thai Crispy',
        variantGroup: 'Thai Crispy',
        variantLabel: 'Mini Bucket',
        qtyNeeded: 5,
        sellingPrice: 150,
        stockSourceId: 1,
      );

      final result = VariantHelpers.partitionForPos([pieces, mini]);

      expect(result.singles, isEmpty);
      expect(result.groups.length, 1);
      expect(result.groups.first.variants.length, 2);
      expect(result.groups.first.posTitle, 'Thai Crispy');
    });

    test('keeps invalid burger groups as separate singles', () {
      final hotCrispy = RawMaterial(
        id: 1,
        name: 'Hot Crispy burger',
        subItem: 'Hot Crispy Patty',
        variantGroup: 'Hot Crispy Patty',
        sellingPrice: 110,
      );
      final bigJuicy = RawMaterial(
        id: 2,
        name: 'Big juicy burger',
        subItem: 'Hot Crispy Patty',
        variantGroup: 'Hot Crispy Patty',
        sellingPrice: 129,
        stockSourceId: 1,
      );

      final result = VariantHelpers.partitionForPos([hotCrispy, bigJuicy]);

      expect(result.groups, isEmpty);
      expect(result.singles.length, 2);
    });

    test('keeps ungrouped items as singles', () {
      final item = RawMaterial(
        id: 3,
        name: 'Chicken 65',
        sellingPrice: 85,
      );

      final result = VariantHelpers.partitionForPos([item]);

      expect(result.groups, isEmpty);
      expect(result.singles.length, 1);
    });
  });

  group('VariantHelpers stock pooling', () {
    test('sellable units use shared stock and variant qty_needed', () {
      final source = RawMaterial(
        id: 1,
        name: 'Thai Crispy',
        currentStock: 50,
        qtyNeeded: 1,
      );
      final bucket = RawMaterial(
        id: 2,
        name: 'Mini Bucket',
        qtyNeeded: 5,
        stockSourceId: 1,
      );
      final byId = {1: source, 2: bucket};

      expect(VariantHelpers.sellableUnits(bucket, byId), 10);
      expect(VariantHelpers.stockMaterialId(bucket), 1);
    });
  });

  group('VariantHelpers.syncVariantLinks', () {
    test('links bucket variants to the base item by shared sub_item', () {
      final pieces = RawMaterial(
        id: 1,
        name: 'Thai Crispy',
        subItem: 'Thai Crispy',
      );
      final mini = RawMaterial(
        id: 2,
        name: 'Mini Bucket',
        subItem: 'Thai Crispy',
      );
      final big = RawMaterial(
        id: 3,
        name: 'Big Buckets',
        subItem: 'Thai Crispy',
      );

      final updates = VariantHelpers.syncVariantLinks([
        pieces,
        mini,
        big,
      ]);

      expect(updates.length, 3);
      final miniUpdate = updates.firstWhere((item) => item.id == 2);
      expect(miniUpdate.variantGroup, 'Thai Crispy');
      expect(miniUpdate.stockSourceId, 1);
      expect(miniUpdate.variantLabel, 'Mini Bucket');

      final piecesUpdate = updates.firstWhere((item) => item.id == 1);
      expect(piecesUpdate.stockSourceId, isNull);
      expect(piecesUpdate.variantGroup, 'Thai Crispy');
    });

    test('links popcorn when base item has no sub_item', () {
      final base = RawMaterial(
        id: 1,
        name: 'Chicken Popcorn',
      );
      final large = RawMaterial(
        id: 2,
        name: 'chicken popcorn large',
        subItem: 'Chicken Popcorn',
      );
      final small = RawMaterial(
        id: 3,
        name: 'Chicken Popcorn small',
        subItem: 'Chicken Popcorn',
      );

      final updates = VariantHelpers.syncVariantLinks([base, large, small]);

      expect(updates.length, 3);
      expect(
        updates.where((item) => item.variantGroup == 'Chicken Popcorn').length,
        3,
      );
    });

    test('links chicken popcorn small/large under the base popcorn item', () {
      final base = RawMaterial(
        id: 1,
        name: 'Chicken Popcorn',
        subItem: 'Chicken Popcorn',
      );
      final large = RawMaterial(
        id: 2,
        name: 'chicken popcorn large',
        subItem: 'Chicken Popcorn',
      );
      final small = RawMaterial(
        id: 3,
        name: 'Chicken Popcorn small',
        subItem: 'Chicken Popcorn Small',
      );

      final updates = VariantHelpers.syncVariantLinks([base, large, small]);

      expect(updates.length, 3);
      expect(
        updates.where((item) => item.variantGroup == 'Chicken Popcorn').length,
        3,
      );
      expect(
        updates.firstWhere((item) => item.id == 3).stockSourceId,
        1,
      );
    });

    test('clears burger groups that only share a patty sub_item', () {
      final hotCrispy = RawMaterial(
        id: 1,
        name: 'Hot Crispy burger',
        subItem: 'Hot Crispy Patty',
        variantGroup: 'Hot Crispy Patty',
      );
      final bigJuicy = RawMaterial(
        id: 2,
        name: 'Big juicy burger',
        subItem: 'Hot Crispy Patty',
        variantGroup: 'Hot Crispy Patty',
        stockSourceId: 1,
      );

      final updates = VariantHelpers.syncVariantLinks([hotCrispy, bigJuicy]);

      expect(updates.length, 2);
      expect(updates.every((item) => item.variantGroup == null), isTrue);
      expect(updates.every((item) => item.stockSourceId == null), isTrue);
    });

    test('does not merge distinct chicken popcorn items in different categories', () {
      final fried = RawMaterial(
        id: 1,
        name: 'Chicken Popcorn',
        subItem: 'Chicken Popcorn Small',
        categoryId: 1,
      );
      final snacks = RawMaterial(
        id: 2,
        name: 'chicken popcorn large',
        subItem: 'Chicken Popcorn Large',
        categoryId: 2,
      );

      final updates = VariantHelpers.syncVariantLinks([
        fried,
        snacks,
      ]);

      expect(updates, isEmpty);
    });
  });
}
