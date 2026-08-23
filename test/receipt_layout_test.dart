import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/receipt_layout.dart';

void main() {
  test('58mm item line matches sample left/right columns', () {
    final lines = ReceiptLayout.itemLines(
      name: 'Veg Burger',
      qty: '1',
      rate: '478',
    );
    expect(lines, hasLength(1));
    expect(lines.first.length, ReceiptLayout.cols58);
    expect(lines.first.startsWith('Veg Burger x 1'), isTrue);
    expect(lines.first.endsWith('478'), isTrue);
  });

  test('long item name wraps and keeps rate on the first line', () {
    final lines = ReceiptLayout.itemLines(
      name: 'Chicken Burger Deluxe Combo',
      qty: '1',
      rate: '50',
    );
    expect(lines.first.length, ReceiptLayout.cols58);
    expect(lines.first.endsWith('50'), isTrue);
    expect(lines.length, greaterThan(1));
  });

  test('skips extra item line when sub item matches the name', () {
    expect(
      ReceiptLayout.extraDetail('Chicken 65', 'Chicken 65'),
      isFalse,
    );
    expect(
      ReceiptLayout.extraDetail('Chicken 65', 'Boneless'),
      isTrue,
    );
  });

  test('tax label uses percent from totals', () {
    expect(ReceiptLayout.taxLabel(61.40, 1228), 'Tax(5%)');
  });

  test('pair pads bill number and time', () {
    final line = ReceiptLayout.pair('Bill #11', '22/08/2026 11:20 AM');
    expect(line.length, ReceiptLayout.cols58);
    expect(line.startsWith('Bill #11'), isTrue);
    expect(line.endsWith('22/08/2026 11:20 AM'), isTrue);
  });
}
