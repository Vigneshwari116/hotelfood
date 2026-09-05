import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/item_import_service.dart';
import 'package:foodstock/services/repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    });
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

  test('seed menu CSV matches PDF burger and roll naming', () async {
    final csv = await rootBundle.loadString(
      'assets/templates/menu_items_import.csv',
    );

    expect(csv, contains('Burgers,Hungery bird burger,Whole Muscle Patty'));
    expect(csv, contains('Rolls,Tandoori roll,chicken 65'));
    expect(csv, isNot(contains(',Burger,')));
    expect(csv, isNot(contains(',rolls,')));
  });
}
