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

  test('materialsForComboPicker excludes finished menu rows and combo names', () {
    final materials = materialsForComboPicker(
      [
        RawMaterial(
          id: 1,
          name: 'Big juicy burger',
          subItem: 'Hot Crispy Patty',
          listed: true,
        ),
        RawMaterial(
          id: 2,
          name: 'Hot Crispy Patty',
          subItem: 'Hot Crispy Patty',
          listed: false,
        ),
        RawMaterial(
          id: 3,
          name: 'Chicken roll',
          subItem: 'spicy fingers',
          listed: true,
        ),
        RawMaterial(
          id: 4,
          name: 'spicy fingers',
          subItem: 'spicy fingers',
          listed: false,
        ),
      ],
      comboNames: ['Big juicy burger', 'Chicken roll'],
    );

    expect(materials.map((item) => item.id).toSet(), {2, 4});
  });

  test('comboDropdownMaterials keeps selected orphan and avoids duplicate ids', () {
    final picker = [
      RawMaterial(id: 2, name: 'Hot Crispy Patty', subItem: 'Hot Crispy Patty'),
      RawMaterial(id: 3, name: 'Burger Bun With Sesame', subItem: 'Burger Bun With Sesame'),
    ];
    final allById = {
      1: RawMaterial(
        id: 1,
        name: 'Big juicy burger',
        subItem: 'Hot Crispy Patty',
        listed: true,
      ),
      2: picker[0],
      3: picker[1],
    };

    final options = comboDropdownMaterials(
      pickerMaterials: picker,
      allMaterialsById: allById,
      selectedMaterialId: 1,
      usedMaterialIds: const [],
    );

    expect(options.map((item) => item.id).toSet(), {1, 2, 3});
    expect(options.where((item) => item.id == 1), hasLength(1));
  });

  test('isValidComboIngredient rejects self-reference and menu rows', () {
    final menuRow = RawMaterial(
      id: 1,
      name: 'Big juicy burger',
      subItem: 'Hot Crispy Patty',
      listed: true,
    );
    final patty = RawMaterial(
      id: 2,
      name: 'Hot Crispy Patty',
      subItem: 'Hot Crispy Patty',
      listed: false,
    );

    expect(
      isValidComboIngredient(
        menuRow,
        comboName: 'Big juicy burger',
        comboNames: ['Big juicy burger'],
      ),
      isFalse,
    );
    expect(
      isValidComboIngredient(
        patty,
        comboName: 'Big juicy burger',
        comboNames: ['Big juicy burger'],
      ),
      isTrue,
    );
  });
}
