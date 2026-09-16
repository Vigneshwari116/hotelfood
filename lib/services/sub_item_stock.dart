import 'package:foodstock/model/models.dart';

/// Stock pooling and POS grouping keyed by [RawMaterial.subItem].
class SubItemStock {
  SubItemStock._();

  static String? stockKey(RawMaterial item) {
    final sub = item.subItem?.trim();
    if (sub == null || sub.isEmpty) return null;
    return normalizeGroupKey(sub);
  }

  /// Case-insensitive, trimmed comparison key for stock pools.
  static String normalizeGroupKey(String value) {
    return value.trim().toLowerCase();
  }

  /// Returns the existing label when [input] matches a group case-insensitively.
  static String resolveCanonicalLabel(
    String input,
    Iterable<String> existingLabels,
  ) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;

    final key = normalizeGroupKey(trimmed);
    for (final label in existingLabels) {
      final candidate = label.trim();
      if (candidate.isEmpty) continue;
      if (normalizeGroupKey(candidate) == key) return candidate;
    }
    return trimmed;
  }

  /// Unique grouping labels sorted A–Z (case-insensitive dedupe).
  static List<String> distinctGroupLabels(Iterable<String?> values) {
    final byKey = <String, String>{};
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed == null || trimmed.isEmpty) continue;
      final key = normalizeGroupKey(trimmed);
      byKey.putIfAbsent(key, () => trimmed);
    }

    final labels = byKey.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return labels;
  }

  /// Picks one display label for a pool of items that share a stock key.
  static String canonicalLabelForFamily(List<RawMaterial> family) {
    if (family.isEmpty) return '';

    final stockKeyValue = stockKey(family.first);
    if (stockKeyValue == null || stockKeyValue.isEmpty) {
      return family.first.trimmedSubItem ?? family.first.name.trim();
    }

    for (final item in family) {
      if (normalizeGroupKey(item.name) == stockKeyValue) {
        return item.name.trim();
      }
    }

    for (final item in family) {
      final sub = item.subItem?.trim();
      if (sub != null &&
          sub.isNotEmpty &&
          normalizeGroupKey(sub) == stockKeyValue) {
        return sub;
      }
    }

    final holder = canonicalHolder(family, stockKey: stockKeyValue);
    if (holder != null) {
      return holder.trimmedSubItem ?? holder.name.trim();
    }

    return family.first.trimmedSubItem ?? family.first.name.trim();
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
