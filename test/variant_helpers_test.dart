import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/variant_helpers.dart';

void main() {
  group('VariantHelpers.partitionForPos', () {
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

  group('VariantHelpers.applyAutoVariantLinking', () {
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

      final updates = VariantHelpers.applyAutoVariantLinking([
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

    test('does not merge distinct chicken popcorn items in different categories', () {
      final fried = RawMaterial(
        id: 1,
        name: 'Chicken Popcorn',
        subItem: 'Chicken Popcorn Small',
      );
      final snacks = RawMaterial(
        id: 2,
        name: 'chicken popcorn large',
        subItem: 'Chicken Popcorn Large',
      );

      final updates = VariantHelpers.applyAutoVariantLinking([
        fried,
        snacks,
      ]);

      expect(updates, isEmpty);
    });
  });
}
