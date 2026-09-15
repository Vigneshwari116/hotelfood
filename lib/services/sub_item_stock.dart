import 'package:foodstock/model/models.dart';

/// Stock pooling and POS grouping keyed by [RawMaterial.subItem].
class SubItemStock {
  SubItemStock._();

  static String? stockKey(RawMaterial item) {
    final sub = item.subItem?.trim();
    if (sub == null || sub.isEmpty) return null;
    return sub.toLowerCase();
  }

  /// Patty/component references on burger rows are not shared product pools.
  static bool isComponentReference(RawMaterial item, String? categoryName) {
    final sub = item.subItem?.trim().toLowerCase() ?? '';
    if (sub.contains('patty')) return true;
    if (sub.contains('bun')) return true;
    final category = categoryName?.trim().toLowerCase() ?? '';
    return category == 'burgers' || category == 'burger';
  }

  static RawMaterial? canonicalHolder(
    List<RawMaterial> family, {
    required String stockKey,
  }) {
    if (family.isEmpty) return null;

    for (final item in family) {
      if (item.name.trim().toLowerCase() == stockKey) {
        return item;
      }
    }

    for (final item in family) {
      final sub = item.subItem?.trim().toLowerCase();
      if (sub == stockKey) {
        return item;
      }
    }

    family.sort((a, b) {
      final orderA = a.menuSortOrder ?? 1 << 30;
      final orderB = b.menuSortOrder ?? 1 << 30;
      final byOrder = orderA.compareTo(orderB);
      if (byOrder != 0) return byOrder;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return family.first;
  }

  static String posGroupKey(RawMaterial item) {
    final sub = item.subItem?.trim();
    if (sub != null && sub.isNotEmpty) {
      return 'sub:${sub.toLowerCase()}:cat:${item.categoryId ?? -1}';
    }
    return 'solo:${item.id}';
  }

  /// Items that share sub_item within the same category appear on one POS card.
  static bool shouldGroupOnPos(List<RawMaterial> family) {
    if (family.length < 2) return false;
    final keys = family.map(stockKey).toSet();
    if (keys.length != 1 || keys.first == null) return false;
    final categoryIds = family.map((item) => item.categoryId).toSet();
    return categoryIds.length == 1;
  }
}
