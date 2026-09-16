import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/combo_material_picker.dart';

void main() {
  test('materialsForComboPicker dedupes listed rows by category and label', () {
    final materials = materialsForComboPicker([
      RawMaterial(id: 1, name: 'Hot Crispy Patty', categoryId: 2, listed: true),
      RawMaterial(id: 2, name: 'Hot Crispy Patty', categoryId: 2, listed: true),
      RawMaterial(id: 3, name: 'Paratha', listed: false),
      RawMaterial(id: 4, name: 'Tea', listed: true),
    ]);

    expect(materials, hasLength(3));
    expect(
      materials.where((item) => item.name == 'Hot Crispy Patty'),
      hasLength(1),
    );
    expect(materials.any((item) => item.name == 'Paratha'), isTrue);
    expect(materials.any((item) => item.name == 'Tea'), isTrue);
  });
}
