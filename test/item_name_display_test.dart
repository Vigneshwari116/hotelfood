import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/receipt_layout.dart';

void main() {
  group('name display roles', () {
    test('salesLabel uses item name for POS, cart, and receipts', () {
      final item = RawMaterial(
        name: 'star burger',
        subItem: 'Crispy Chicken Patty',
      );

      expect(item.salesLabel, 'star burger');
      expect(item.staffLabel, 'Crispy Chicken Patty');
    });

    test('cart line displayLabel includes variant when present', () {
      final line = CartLine(
        rawMaterialId: 1,
        name: 'Chicken Popcorn',
        subItem: 'Chicken Popcorn',
        variantLabel: 'popcorn large',
        qty: 1,
        price: 129,
      );

      expect(line.displayLabel, 'Chicken Popcorn — popcorn large');
    });

    test('receipt uses item name for raw material sales', () {
      final lines = expandReceiptLines([
        CartLine(
          rawMaterialId: 1,
          name: 'star burger',
          subItem: 'Crispy Chicken Patty',
          qty: 1,
          price: 120,
        ),
      ]);

      expect(lines.single.label, 'star burger');
    });

    test('combo receipt itemizes component item names not stock names', () {
      final lines = expandReceiptLines([
        CartLine(
          comboId: 1,
          name: 'Star burger combo',
          componentLabels: const [
            'Burger Bun',
            'star burger',
          ],
          qty: 1,
          price: 210,
        ),
      ]);

      expect(lines.first.label, 'Star burger combo');
      expect(lines[1].label, '  Burger Bun');
      expect(lines[2].label, '  star burger');
    });

    test('combo item itemNameLabel prefers stock ingredient name', () {
      final component = ComboItem(
        comboId: 1,
        rawMaterialId: 2,
        qty: 1,
        materialName: 'star burger',
        materialSubItem: 'Crispy Chicken Patty',
      );

      expect(component.itemNameLabel, 'Crispy Chicken Patty');
      expect(component.staffLabel, 'Crispy Chicken Patty');
    });
  });
}
