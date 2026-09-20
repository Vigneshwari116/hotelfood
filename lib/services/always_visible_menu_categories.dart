import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/item_import_service.dart';

/// Menu groups that are always visible on Sales/POS — no manual hide toggle.
const alwaysVisibleInSalesCategoryNames = <String>{
  'Sauces',
  'Fried Items',
  'Snacks',
  'Uncategorized',
};

bool isAlwaysVisibleInSalesCategoryName(String? categoryName) {
  final canonical =
      ItemImportService.canonicalMenuCategory(categoryName) ??
      categoryName?.trim() ??
      '';
  if (canonical.isEmpty) return false;
  return alwaysVisibleInSalesCategoryNames.contains(canonical);
}

bool isAlwaysVisibleInSalesCategoryId(
  int? categoryId,
  Iterable<Category> categories,
) {
  if (categoryId == null) return false;
  for (final category in categories) {
    if (category.id == categoryId) {
      return isAlwaysVisibleInSalesCategoryName(category.name);
    }
  }
  return false;
}
