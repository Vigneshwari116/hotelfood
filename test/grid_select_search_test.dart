import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/inventory_search.dart';

void main() {
  group('grid select search filtering', () {
    final options = [
      'BBQ Seasoning',
      'Big Buckets',
      'Big juciy burger',
      'Breader',
      'Chicken 65',
      'Crunchy Masala',
    ];

    List<String> filter(String query) {
      if (query.trim().isEmpty) return options;
      return options.where((value) {
        return matchesInventorySearchQuery(value.toLowerCase(), query);
      }).toList();
    }

    test('filters by partial name', () {
      expect(filter('chick'), ['Chicken 65']);
      expect(filter('big'), ['Big Buckets', 'Big juciy burger']);
    });

    test('filters by multiple words', () {
      expect(filter('big buck'), ['Big Buckets']);
    });

    test('returns empty when nothing matches', () {
      expect(filter('zzzz'), isEmpty);
    });
  });
}
