import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/services/pos_stock.dart';

void main() {
  test('POS allows adding items regardless of stock level', () {
    expect(posIsStocked(0), isTrue);
    expect(posIsStocked(-3), isTrue);
    expect(posAllowsAdd(stock: 0, cartQty: 0), isTrue);
    expect(posAllowsAdd(stock: -2, cartQty: 5), isTrue);
    expect(posMaxQty(0), isNull);
    expect(posMaxQty(-4), isNull);
  });
}
