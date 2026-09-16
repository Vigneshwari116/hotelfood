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
  });

  group('inventorySearchEntriesFromMaterials', () {
    test('uses staff label as primary label', () {
      final item = material(id: 1, name: 'Patty', subItem: 'Crispy Chicken');
      final entry = inventorySearchEntriesFromMaterials([item]).single;
      expect(entry.primaryLabel, 'Crispy Chicken Patty');
    });
  });
}
