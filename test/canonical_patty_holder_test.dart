import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/sub_item_stock.dart';

void main() {
  test('Hot Crispy Patty pool picks row with stock when no dedicated holder', () {
    final materials = [
      RawMaterial(
        id: 16,
        name: 'Hot Crispy burger',
        subItem: 'Hot Crispy Patty',
        listed: false,
        currentStock: 0,
      ),
      RawMaterial(
        id: 55,
        name: 'Big juciy burger',
        subItem: 'Hot Crispy Patty',
        listed: false,
        currentStock: 5,
      ),
    ];
    final byId = {for (final m in materials) m.id!: m};
    final map = SubItemStock.buildCanonicalStockIdMap(materials);

    expect(map[16], 55);
    expect(map[55], 55);
    expect(
      SubItemStock.resolveCanonicalStockHolderId(byId[16]!, byId),
      55,
    );
  });

  test('Hot Crispy Patty pool follows stock_source_id to holder', () {
    final materials = [
      RawMaterial(
        id: 16,
        name: 'Hot Crispy burger',
        subItem: 'Hot Crispy Patty',
        listed: false,
        currentStock: 0,
        stockSourceId: 55,
      ),
      RawMaterial(
        id: 55,
        name: 'Big juciy burger',
        subItem: 'Hot Crispy Patty',
        listed: false,
        currentStock: 5,
      ),
    ];
    final byId = {for (final m in materials) m.id!: m};
    final map = SubItemStock.buildCanonicalStockIdMap(materials);

    expect(map[16], 55);
    expect(map[55], 55);
  });
}
