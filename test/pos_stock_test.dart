import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/pos_stock.dart';

void main() {
  test('unstocked items are not sold on POS', () {
    expect(posIsStocked(0), isFalse);
    expect(posAllowsAdd(stock: 0, cartQty: 0), isFalse);
    expect(posMaxQty(0), 0);
  });

  test('stocked items can be added up to remaining stock', () {
    expect(posAllowsAdd(stock: 2, cartQty: 0), isTrue);
    expect(posAllowsAdd(stock: 2, cartQty: 1), isTrue);
    expect(posAllowsAdd(stock: 2, cartQty: 2), isFalse);
    expect(posMaxQty(2), 2);
  });
}
