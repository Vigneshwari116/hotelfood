import 'package:flutter_test/flutter_test.dart';
import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/menu_grid_save_harness.dart';
import 'support/stock_test_db.dart';

/// Fields the Menu Items Grid can change via [MenuItemEditHelpers.buildForSave].
const _gridWritableFields = {
  'barcode',
  'name',
  'subItem',
  'qtyNeeded',
  'unitId',
  'openingStock',
  'openingPieces',
  'currentStock',
  'unitsPerPacket',
  'costPrice',
  'sellingPrice',
  'variantGroup',
  'variantLabel',
  'stockSourceId',
};

/// Carried from [existing] in buildForSave — not shown as grid columns but must persist.
const _gridPreservedFromExistingFields = {
  'categoryId',
  'reorderLevel',
  'shelfLifeDays',
  'entryPasswordHash',
  'imagePath',
  'listed',
  'createdAt',
  'menuSortOrder',
  'locationId',
};

const _allCatalogFieldsUnderTest = {
  ..._gridWritableFields,
  ..._gridPreservedFromExistingFields,
};

void expectCatalogFieldsPreserved({
  required RawMaterial before,
  required RawMaterial after,
  Set<String> allowedChanges = const {},
}) {
  void check(String field, Object? expected, Object? actual) {
    if (allowedChanges.contains(field)) return;
    expect(actual, expected, reason: 'field $field');
  }

  check('barcode', before.barcode, after.barcode);
  check('name', before.name, after.name);
  check('subItem', before.subItem, after.subItem);
  check('qtyNeeded', before.qtyNeeded, after.qtyNeeded);
  check('categoryId', before.categoryId, after.categoryId);
  check('unitId', before.unitId, after.unitId);
  check('reorderLevel', before.reorderLevel, after.reorderLevel);
  check('shelfLifeDays', before.shelfLifeDays, after.shelfLifeDays);
  check('unitsPerPacket', before.unitsPerPacket, after.unitsPerPacket);
  check('entryPasswordHash', before.entryPasswordHash, after.entryPasswordHash);
  check('costPrice', before.costPrice, after.costPrice);
  check('sellingPrice', before.sellingPrice, after.sellingPrice);
  check('imagePath', before.imagePath, after.imagePath);
  check('listed', before.listed, after.listed);
  check('menuSortOrder', before.menuSortOrder, after.menuSortOrder);
  check('variantGroup', before.variantGroup, after.variantGroup);
  check('variantLabel', before.variantLabel, after.variantLabel);
  check('stockSourceId', before.stockSourceId, after.stockSourceId);
  check('locationId', before.locationId, after.locationId);
  check('openingPieces', before.openingPieces, after.openingPieces);

  if (!allowedChanges.contains('createdAt')) {
    expect(
      after.createdAt?.toIso8601String(),
      before.createdAt?.toIso8601String(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Menu Items Grid save regression', () {
    late Database database;
    late DateTime createdAt;
    late List<RawMaterial> menuCatalog;

    Future<RawMaterial> seedFullyPopulatedItem({int id = 10}) async {
      createdAt = DateTime(2024, 6, 1, 12, 0, 0);
      await database.insert('categories', {
        'id': 2,
        'name': 'Fried Items',
        'type': 'raw_material',
      });

      await database.insert('raw_materials', {
        'id': id,
        'barcode': 'GRID-TEST-001',
        'name': 'Grid Save Item',
        'sub_item': 'grid sub',
        'qty_needed': 2,
        'category_id': 2,
        'unit_id': 2,
        'image_path': '/tmp/grid-item.png',
        'opening_stock': 100,
        'opening_pieces': 3,
        'current_stock': 100,
        'reorder_level': 12.5,
        'shelf_life_days': 14,
        'units_per_packet': 20,
        'entry_password_hash': 'hash-grid',
        'cost_price': 40,
        'selling_price': 99,
        'listed': 1,
        'menu_sort_order': 42,
        'variant_group': 'Grid Group',
        'variant_label': 'Regular',
        'stock_source_id': null,
        'location_id': 1,
        'created_at': createdAt.toIso8601String(),
      });
      await seedLocationStock(
        database,
        id,
        stock: 100,
        openingStock: 100,
      );

      final loaded = await Repository.instance.rawMaterialById(id);
      expect(loaded, isNotNull);
      return loaded!;
    }

    setUp(() async {
      database = await openStockTestDatabase();
      bindStockTestSession(database);
      menuCatalog = [];
    });

    tearDown(() async {
      await tearDownStockTestSession(database);
    });

    test('full preservation: grid save without edits keeps every catalog field', () async {
      final before = await seedFullyPopulatedItem();
      menuCatalog = [before];

      final fields = MenuGridSaveFields.fromMaterial(before, menuItems: menuCatalog);
      final after = await saveThroughMenuGrid(
        existing: before,
        menuItems: menuCatalog,
        fields: fields,
        runVariantRefresh: true,
      );

      expectCatalogFieldsPreserved(before: before, after: after);
      expect(after.openingStock, before.openingStock);
      expect(after.currentStock, before.currentStock);
    });

    test('single-field edit: only sellingPrice changes; others preserved', () async {
      final before = await seedFullyPopulatedItem();
      menuCatalog = [before];

      final fields = MenuGridSaveFields.fromMaterial(before, menuItems: menuCatalog)
          .copyWith(sellingPriceText: '125');

      final after = await saveThroughMenuGrid(
        existing: before,
        menuItems: menuCatalog,
        fields: fields,
        runVariantRefresh: true,
      );

      expect(after.sellingPrice, 125);
      expectCatalogFieldsPreserved(
        before: before,
        after: after,
        allowedChanges: {'sellingPrice'},
      );
    });

    test(
      'single-field edit: reorder_level not in grid UI stays unchanged when sellingPrice edits',
      () async {
        final before = await seedFullyPopulatedItem();
        expect(before.reorderLevel, 12.5);
        menuCatalog = [before];

        final fields = MenuGridSaveFields.fromMaterial(
          before,
          menuItems: menuCatalog,
        ).copyWith(sellingPriceText: '110');

        final after = await saveThroughMenuGrid(
          existing: before,
          menuItems: menuCatalog,
          fields: fields,
        );

        expect(after.sellingPrice, 110);
        expect(after.reorderLevel, 12.5);
      },
    );

    test('NULL safety: nullable catalog fields are not cleared on no-op grid save', () async {
      final before = await seedFullyPopulatedItem();
      menuCatalog = [before];

      expect(before.barcode, isNotNull);
      expect(before.variantGroup, isNotNull);
      expect(before.variantLabel, isNotNull);
      expect(before.imagePath, isNotNull);
      expect(before.menuSortOrder, isNotNull);
      expect(before.shelfLifeDays, isNotNull);
      expect(before.entryPasswordHash, isNotNull);

      final after = await saveThroughMenuGrid(
        existing: before,
        menuItems: menuCatalog,
        fields: MenuGridSaveFields.fromMaterial(before, menuItems: menuCatalog),
      );

      expect(after.barcode, before.barcode);
      expect(after.variantGroup, before.variantGroup);
      expect(after.variantLabel, before.variantLabel);
      expect(after.imagePath, before.imagePath);
      expect(after.menuSortOrder, before.menuSortOrder);
      expect(after.shelfLifeDays, before.shelfLifeDays);
      expect(after.entryPasswordHash, before.entryPasswordHash);
    });

    test('stock source 856→843 survives grid save and refreshVariantLinks', () async {
      await database.insert('categories', {
        'id': 1,
        'name': 'Snacks',
        'type': 'raw_material',
      });
      await database.insert('categories', {
        'id': 2,
        'name': 'Fried Items',
        'type': 'raw_material',
      });

      final now = DateTime(2024, 1, 1).toIso8601String();
      await database.insert('raw_materials', {
        'id': 843,
        'name': 'Chicken 65',
        'sub_item': 'chicken 65',
        'category_id': 1,
        'unit_id': 2,
        'qty_needed': 1,
        'opening_stock': 50,
        'current_stock': 50,
        'listed': 1,
        'location_id': 1,
        'created_at': now,
      });
      await seedLocationStock(database, 843, stock: 50, openingStock: 50);

      await database.insert('raw_materials', {
        'id': 856,
        'name': 'Krusty Bites',
        'sub_item': 'chicken 65',
        'category_id': 2,
        'unit_id': 2,
        'qty_needed': 1,
        'opening_stock': 0,
        'current_stock': 0,
        'selling_price': 99,
        'listed': 1,
        'stock_source_id': 843,
        'location_id': 1,
        'created_at': now,
      });
      await seedLocationStock(database, 856, stock: 0, openingStock: 0);

      final chicken = (await Repository.instance.rawMaterialById(843))!;
      final krustyBefore = (await Repository.instance.rawMaterialById(856))!;
      menuCatalog = [chicken, krustyBefore];

      final fields = MenuGridSaveFields.fromMaterial(
        krustyBefore,
        menuItems: menuCatalog,
      ).copyWith(sellingPriceText: '100');

      final krustyAfter = await saveThroughMenuGrid(
        existing: krustyBefore,
        menuItems: menuCatalog,
        fields: fields,
        runVariantRefresh: true,
      );

      expect(krustyAfter.stockSourceId, 843);
      expect(krustyAfter.sellingPrice, 100);
      final row = (await database.query(
        'raw_materials',
        where: 'id = ?',
        whereArgs: [856],
      ))
          .single;
      expect(row['stock_source_id'], 843);
    });

    test('documents fields covered by this suite', () {
      expect(_allCatalogFieldsUnderTest, containsAll([
        'barcode',
        'name',
        'subItem',
        'qtyNeeded',
        'categoryId',
        'unitId',
        'reorderLevel',
        'shelfLifeDays',
        'unitsPerPacket',
        'entryPasswordHash',
        'costPrice',
        'sellingPrice',
        'imagePath',
        'listed',
        'menuSortOrder',
        'variantGroup',
        'variantLabel',
        'stockSourceId',
        'locationId',
        'openingPieces',
        'createdAt',
        'openingStock',
        'currentStock',
      ]));
    });
  });
}
