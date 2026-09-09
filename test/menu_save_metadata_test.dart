import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';

void main() {
  test('RawMaterial.toMap omits menu export metadata columns', () {
    final map = RawMaterial(
      id: 1,
      name: 'Chicken 65',
      subItem: 'Chicken 65',
      qtyNeeded: 1,
      unitsPerPacket: 90,
      currentStock: 540,
    ).toMap();

    expect(map.containsKey('menu_export_row'), isFalse);
    expect(map.containsKey('menu_sort_order'), isFalse);
  });
}
