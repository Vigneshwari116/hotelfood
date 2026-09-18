import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/combo_material_picker.dart';

void main() {
  test('materialsForComboPicker dedupes ingredient pools across categories', () {
    final materials = materialsForComboPicker([
      RawMaterial(id: 1, name: 'Hot Crispy Patty', categoryId: 2, listed: true),
      RawMaterial(id: 2, name: 'Hot Crispy Patty', categoryId: 2, listed: true),
      RawMaterial(
        id: 3,
        name: 'Paratha',
        subItem: 'Paratha',
        listed: false,
      ),
      RawMaterial(
        id: 5,
        name: 'Paratha',
        subItem: 'Paratha',
        categoryId: 9,
        listed: true,
      ),
      RawMaterial(id: 4, name: 'Tea', listed: true),
    ]);

    expect(materials, hasLength(2));
    expect(
      materials.where((item) => item.name == 'Hot Crispy Patty'),
      hasLength(1),
    );
    expect(materials.where((item) => item.name == 'Paratha'), hasLength(1));
    expect(materials.any((item) => item.name == 'Tea'), isFalse);
  });

  test('materialsForComboPicker shows one row per duplicate stock ingredient', () {
    final materials = materialsForComboPicker([
      RawMaterial(
        id: 10,
        name: 'Thai Crispy',
        subItem: 'Thai Crispy',
        categoryId: 3,
        listed: false,
      ),
      RawMaterial(
        id: 11,
        name: 'Thai Crispy',
        subItem: 'Thai Crispy',
        categoryId: 3,
        listed: true,
      ),
      RawMaterial(
        id: 12,
        name: 'Thai Crispy',
        subItem: 'Thai Crispy',
        categoryId: 9,
        listed: true,
      ),
      RawMaterial(
        id: 20,
        name: 'Crunchy Masala',
        subItem: 'Crunchy Masala',
        categoryId: 3,
        listed: false,
      ),
      RawMaterial(
        id: 21,
        name: 'Crunchy Masala',
        subItem: 'Crunchy Masala',
        categoryId: 3,
        listed: true,
      ),
    ]);

    expect(materials, hasLength(2));
    expect(
      materials.map((item) => item.staffLabel).toSet(),
      {'Thai Crispy', 'Crunchy Masala'},
    );
  });
}
