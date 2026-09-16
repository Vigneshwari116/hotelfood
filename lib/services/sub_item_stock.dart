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

  /// Maps raw_material row ids to the canonical sub_item label when a family
  /// has case/whitespace duplicates that should share one stock pool.
  static Map<int, String> canonicalLabelUpdatesForRows(
    Iterable<Map<String, dynamic>> rows,
  ) {
    final byKey = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final sub = row['sub_item']?.toString().trim();
      final name = row['name']?.toString().trim() ?? '';
      final label = (sub == null || sub.isEmpty) ? name : sub;
      if (label.isEmpty) continue;
      byKey.putIfAbsent(normalizeGroupKey(label), () => []).add(row);
    }

    final updates = <int, String>{};
    for (final familyRows in byKey.values) {
      if (familyRows.length < 2) continue;

      final family = familyRows
          .map(
            (row) => RawMaterial(
              id: row['id'] as int?,
              name: row['name']?.toString() ?? '',
              subItem: row['sub_item']?.toString(),
            ),
          )
          .toList();
      final canonical = canonicalLabelForFamily(family);
      if (canonical.isEmpty) continue;

      for (final row in familyRows) {
        final id = row['id'] as int?;
        if (id == null) continue;
        final stored = row['sub_item']?.toString() ?? '';
        if (stored != canonical) {
          updates[id] = canonical;
        }
      }
    }

    return updates;
  }

  /// Picks one display label for a pool of items that share a stock key.
  static String canonicalLabelForFamily(List<RawMaterial> family) {
    if (family.isEmpty) return '';

    final stockKeyValue = stockKey(family.first);
    if (stockKeyValue == null || stockKeyValue.isEmpty) {
      return family.first.trimmedSubItem ?? family.first.name.trim();
    }

    final subLabels = <String>{};
    for (final item in family) {
      final sub = item.subItem?.trim();
      if (sub != null &&
          sub.isNotEmpty &&
          normalizeGroupKey(sub) == stockKeyValue) {
        subLabels.add(sub);
      }
    }
    if (subLabels.isNotEmpty) {
      final sorted = subLabels.toList()
        ..sort((a, b) {
          final byLower = a.toLowerCase().compareTo(b.toLowerCase());
          if (byLower != 0) return byLower;
          return a.compareTo(b);
        });
      for (final label in sorted) {
        if (label.toLowerCase() == stockKeyValue) return label;
      }
      return sorted.first;
    }

    for (final item in family) {
      if (normalizeGroupKey(item.name) == stockKeyValue) {
        return item.name.trim();
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

  /// Normalizes a variant label for duplicate detection (case/whitespace).
  static String normalizeVariantLabel(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
