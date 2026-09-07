import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/receipt_layout.dart';

void main() {
  test('combo receipt shows combo line at combo price with kitchen detail', () {
    final lines = expandReceiptLines([
      CartLine(
        comboId: 1,
        name: 'Star burger combo',
        componentLabels: const [
          'Burger Bun With Sesame',
          'Crispy Chicken Patty',
        ],
        qty: 1,
        price: 210,
      ),
    ]);

    expect(lines.length, 3);
    expect(lines.first.label, 'Star burger combo');
    expect(lines.first.amount, 210);
    expect(lines[1].label, '  Burger Bun With Sesame');
    expect(lines[1].amount, isNull);
    expect(lines[2].label, '  Crispy Chicken Patty');
    expect(lines[2].amount, isNull);
  });

  test('raw material receipt keeps staff label and amount', () {
    final lines = expandReceiptLines([
      CartLine(
        rawMaterialId: 5,
        name: 'Chicken 65',
        subItem: 'Chicken 65',
        qty: 2,
        price: 85,
      ),
    ]);

    expect(lines.length, 1);
    expect(lines.single.label, 'Chicken 65');
    expect(lines.single.amount, 170);
  });
}
