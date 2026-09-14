import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/item_import_service.dart';

void main() {
  group('import item key collision', () {
    final service = ItemImportService();

    test('keeps SNACKS and FRIED ITEMS chicken popcorn distinct', () {
      final snacksKey = service.itemKeyFor(
        'chicken popcorn large',
        'Chicken Popcorn Large',
        category: 'SNACKS',
      );
      final friedKey = service.itemKeyFor(
        'Chicken Popcorn',
        'Chicken Popcorn Small',
        category: 'FRIED ITEMS',
      );

      expect(snacksKey, isNot(equals(friedKey)));
    });

    test('case differences in item_name create distinct keys within category', () {
      final lower = service.itemKeyFor(
        'chicken popcorn large',
        'Chicken Popcorn Large',
        category: 'SNACKS',
      );
      final upper = service.itemKeyFor(
        'Chicken popcorn large',
        'Chicken Popcorn',
        category: 'FRIED ITEMS',
      );

      expect(lower, isNot(equals(upper)));
    });
  });
}
