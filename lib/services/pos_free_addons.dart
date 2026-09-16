import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/item_import_service.dart';

/// POS items that appear on the menu but are not charged on the bill.
class PosFreeAddons {
  PosFreeAddons._();

  static const _freeAddOnCategoryNames = {'sauces'};

  static bool isFreeAddOnCategoryName(String? name) {
    final canonical = ItemImportService.canonicalMenuCategory(name) ?? name?.trim();
    if (canonical == null || canonical.isEmpty) return false;
    return _freeAddOnCategoryNames.contains(canonical.toLowerCase());
  }

  static bool isFreeAddOn(
    RawMaterial material, {
    required String? Function(int? categoryId) categoryNameFor,
  }) {
    return isFreeAddOnCategoryName(categoryNameFor(material.categoryId));
  }

  static bool isFreeAddOnCartLine(
    CartLine line, {
    required Map<int, RawMaterial> materialsById,
    required String? Function(int? categoryId) categoryNameFor,
  }) {
    final id = line.rawMaterialId;
    if (id == null) return false;
    final material = materialsById[id];
    if (material == null) return false;
    return isFreeAddOn(material, categoryNameFor: categoryNameFor);
  }
}
