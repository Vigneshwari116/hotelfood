import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/receipt_layout.dart';

void main() {
  test('combo receipt shows combo line at combo price with item names', () {
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

    expect(lines.length, 3);
    expect(lines.first.label, 'Star burger combo');
    expect(lines.first.amount, 210);
    expect(lines[1].label, '  Burger Bun');
    expect(lines[1].amount, isNull);
    expect(lines[2].label, '  star burger');
    expect(lines[2].amount, isNull);
  });

  test('raw material receipt shows item name not stock name', () {
    final lines = expandReceiptLines([
      CartLine(
        rawMaterialId: 5,
        name: 'star burger',
        subItem: 'Crispy Chicken Patty',
        qty: 2,
        price: 85,
      ),
    ]);

    expect(lines.length, 1);
    expect(lines.single.label, 'star burger');
    expect(lines.single.amount, 170);
  });
}
