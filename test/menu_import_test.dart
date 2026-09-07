import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const locationMenuFiles = [
    'Gt world mall',
    'Magadi road',
    'Subbanna garden',
  ];

  group('menu category normalization', () {
    test('maps legacy burger and bun names to Burgers', () {
      expect(ItemImportService.canonicalMenuCategory('Burger'), 'Burgers');
      expect(ItemImportService.canonicalMenuCategory('burger'), 'Burgers');
      expect(ItemImportService.canonicalMenuCategory('Bun'), 'Burgers');
      expect(ItemImportService.canonicalMenuCategory('BURGERS'), 'Burgers');
    });

    test('maps snacks and sauces to title case', () {
      expect(ItemImportService.canonicalMenuCategory('snacks'), 'Snacks');
      expect(ItemImportService.canonicalMenuCategory('SAUCES'), 'Sauces');
      expect(ItemImportService.canonicalMenuCategory('FRIED ITEMS'), 'Fried Items');
      expect(ItemImportService.canonicalMenuCategory('rolls'), 'Rolls');
      expect(ItemImportService.canonicalMenuCategory('BEVARGES'), 'Beverages');
    });
  });

  test('hiddenByDefaultNames has no duplicate entries', () {
    const names = ItemImportService.hiddenByDefaultNames;
    expect(names.length, names.toSet().length);
  });

  test('groupingTags has no duplicate entries', () {
    const tags = ItemImportService.groupingTags;
    expect(tags.length, tags.toSet().length);
  });

  test('hiddenGroupingTags has no duplicate entries', () {
    const tags = ItemImportService.hiddenGroupingTags;
    expect(tags.length, tags.toSet().length);
  });

  group('barcode normalization', () {
    test('strips decimal suffix from whole numbers', () {
      expect(ItemImportService.normalizeBarcode('10'), '10');
      expect(ItemImportService.normalizeBarcode('10.0'), '10');
      expect(ItemImportService.normalizeBarcode(' 69 '), '69');
    });

    test('lookup candidates include normalized values', () {
      final candidates = Repository.barcodeLookupCandidates('10.0');
      expect(candidates, contains('10'));
      expect(candidates, contains('10.0'));
    });
  });

  test('static location menu templates exist for manual first import', () async {
    for (final name in locationMenuFiles) {
      final bytes = await rootBundle.load(
        'assets/templates/locations/$name.xlsx',
      );
      expect(bytes.lengthInBytes, greaterThan(100));
    }
  });

  test('seed menu CSV includes beverages and stock items from PDF', () async {
    final csv = await rootBundle.loadString(
      'assets/templates/menu_items_import.csv',
    );

    expect(csv, contains('BURGERS,Hungery bird burger,Whole Muscle Patty'));
    expect(csv, contains('ROLLS,Tandoori roll,chicken 65'));
    expect(csv, contains('BEVARGES,pepsi 300 ml,pepsi'));
    expect(csv, contains('STOCK,Paratha,Paratha'));
    expect(csv, contains('ROLLS,Chicken Roll,chicken roll'));
  });
}
