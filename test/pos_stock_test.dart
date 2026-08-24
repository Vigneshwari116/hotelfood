import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/pos_stock.dart';

void main() {
  test('items with no stock recorded can still be tapped onto the cart', () {
    expect(posAllowsAdd(stock: 0, cartQty: 0), isTrue);
    expect(posAllowsAdd(stock: 0, cartQty: 3), isTrue);
  });

  test('recorded stock is the maximum that can be added', () {
    expect(posAllowsAdd(stock: 2, cartQty: 0), isTrue);
    expect(posAllowsAdd(stock: 2, cartQty: 1), isTrue);
    expect(posAllowsAdd(stock: 2, cartQty: 2), isFalse);
    expect(posMaxQty(2), 2);
    expect(posMaxQty(0), isNull);
  });
}
