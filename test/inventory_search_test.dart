import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/inventory_search.dart';

void main() {
  RawMaterial material({
    required int id,
    required String name,
    String? subItem,
    String? barcode,
    String? variantGroup,
    String? variantLabel,
  }) {
    return RawMaterial.fromMap({
      'id': id,
      'name': name,
      'sub_item': subItem,
      'barcode': barcode,
      'variant_group': variantGroup,
      'variant_label': variantLabel,
      'opening_stock': 0,
      'current_stock': 10,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  group('matchesInventorySearchQuery', () {
    test('matches every word in any order', () {
      const haystack = 'popcorn large snack 123';
      expect(matchesInventorySearchQuery(haystack, 'pop large'), isTrue);
      expect(matchesInventorySearchQuery(haystack, 'large pop'), isTrue);
      expect(matchesInventorySearchQuery(haystack, 'pop xl'), isFalse);
    });

    test('empty query matches everything', () {
      expect(matchesInventorySearchQuery('anything', ''), isTrue);
      expect(matchesInventorySearchQuery('anything', '   '), isTrue);
    });
  });

  group('filterInventorySearchEntries', () {
    test('limits dropdown results', () {
      final entries = List.generate(
        20,
        (i) => InventorySearchEntry.fromMaterial(
          material(id: i, name: 'Item $i'),
        ),
      );
      expect(filterInventorySearchEntries(entries, '').length, 12);
    });

    test('finds material by sub item and variant', () {
      final popcorn = material(
        id: 1,
        name: 'Popcorn',
        variantGroup: 'Popcorn',
        variantLabel: 'Large',
      );
      final entries = [InventorySearchEntry.fromMaterial(popcorn)];
      final matches = filterInventorySearchEntries(entries, 'pop large');
      expect(matches, hasLength(1));
      expect(matches.first.primaryLabel, popcorn.staffLabel);
    });

    test('finds material by category name on haystack', () {
      final roll = material(id: 2, name: 'Krisper roll', subItem: 'chicken strips');
      final haystack = inventoryMaterialHaystack(roll, categoryName: 'Rolls');
      expect(matchesInventorySearchQuery(haystack, 'krisper roll'), isTrue);
      expect(matchesInventorySearchQuery(haystack, 'rolls krisper'), isTrue);
    });
  });

  group('inventorySearchEntriesFromMaterials', () {
    test('uses staff label as primary label', () {
      final item = material(
        id: 1,
        name: 'Patty',
        subItem: 'Crispy Chicken Patty',
      );
      final entry = inventorySearchEntriesFromMaterials([item]).single;
      expect(entry.primaryLabel, item.staffLabel);
      expect(entry.primaryLabel, 'Crispy Chicken Patty');
    });
  });

  group('inventoryPurchaseEntriesFromMaterials', () {
    test('collapses variant group to one purchase row', () {
      final regular = material(
        id: 1,
        name: 'Chicken popcorn',
        subItem: 'Chicken Popcorn',
        variantGroup: 'Chicken Popcorn',
        variantLabel: 'Regular',
      );
      final large = material(
        id: 2,
        name: 'Chicken popcorn large',
        subItem: 'Chicken Popcorn',
        variantGroup: 'Chicken Popcorn',
        variantLabel: 'Large',
      );

      final entries = inventoryPurchaseEntriesFromMaterials([regular, large]);
      expect(entries, hasLength(1));
      expect(entries.single.primaryLabel.toLowerCase(), contains('popcorn'));
      expect(entries.single.material?.id, isNotNull);
    });

    test('sorts purchase entries alphabetically', () {
      final zebra = material(id: 1, name: 'Zebra chips', subItem: 'Zebra chips');
      final apple = material(id: 2, name: 'Apple pie', subItem: 'Apple pie');
      final entries = inventoryPurchaseEntriesFromMaterials([zebra, apple]);
      expect(entries.map((e) => e.primaryLabel).toList(), ['Apple pie', 'Zebra chips']);
    });
  });
}
