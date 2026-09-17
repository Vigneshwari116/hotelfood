import 'package:foodstock/model/models.dart';
import 'package:foodstock/services/sub_item_stock.dart';
import 'package:foodstock/services/variant_helpers.dart';

/// One row in the purchase or POS item search dropdown.
class InventorySearchEntry {
  const InventorySearchEntry({
    required this.primaryLabel,
    required this.haystack,
    this.secondaryLabel,
    this.material,
    this.combo,
  }) : assert(
          (material != null) ^ (combo != null),
          'Entry must be either a material or a combo',
        );

  final String primaryLabel;
  final String? secondaryLabel;
  final String haystack;
  final RawMaterial? material;
  final Combo? combo;

  factory InventorySearchEntry.fromMaterial(
    RawMaterial material, {
    String? categoryName,
  }) {
    return InventorySearchEntry(
      primaryLabel: material.staffLabel,
      secondaryLabel: inventoryMaterialExtra(material),
      haystack: inventoryMaterialHaystack(
        material,
        categoryName: categoryName,
      ),
      material: material,
    );
  }

  factory InventorySearchEntry.fromCombo(
    Combo combo, {
    String? categoryName,
  }) {
    final parts = <String>[];
    for (final item in combo.items) {
      final label = item.itemNameLabel.trim();
      if (label.isNotEmpty) {
        parts.add(label);
      }
    }
    final secondary = parts.isEmpty ? null : parts.join('  •  ');
    return InventorySearchEntry(
      primaryLabel: combo.name,
      secondaryLabel: secondary,
      haystack: inventoryComboHaystack(
        combo,
        categoryName: categoryName,
      ),
      combo: combo,
    );
  }

  bool get isMaterial => material != null;

  bool get isCombo => combo != null;
}

String inventoryMaterialHaystack(
  RawMaterial material, {
  String? categoryName,
}) {
  return [
    material.name,
    material.trimmedSubItem ?? '',
    material.barcode ?? '',
    material.variantGroup ?? '',
    material.variantLabel ?? '',
    material.staffLabel,
    material.salesLabel,
    categoryName ?? '',
  ].join(' ').toLowerCase();
}

String? inventoryMaterialExtra(RawMaterial material) {
  final staff = material.staffLabel.toLowerCase();
  final parts = <String>[];
  final variant = VariantHelpers.variantSelectorLabel(material).trim();
  if (variant.isNotEmpty && variant.toLowerCase() != staff) {
    parts.add(variant);
  }
  final sub = material.trimmedSubItem;
  if (sub != null && sub.toLowerCase() != staff) {
    parts.add(sub);
  }
  final barcode = material.barcode?.trim();
  if (barcode != null && barcode.isNotEmpty) {
    parts.add(barcode);
  }
  if (parts.isEmpty) return null;
  return parts.join('  •  ');
}

String inventoryComboHaystack(
  Combo combo, {
  String? categoryName,
}) {
  return [
    combo.name,
    combo.barcode ?? '',
    categoryName ?? '',
    for (final item in combo.items) ...[
      item.materialName ?? '',
      item.materialSubItem ?? '',
      item.itemNameLabel,
    ],
  ].join(' ').toLowerCase();
}

/// Purchase-style multi-word search: every word must appear in [haystack].
bool matchesInventorySearchQuery(String haystack, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    return true;
  }
  final words = q.split(RegExp(r'\s+'));
  return words.every((word) => haystack.contains(word));
}

List<InventorySearchEntry> filterInventorySearchEntries(
  List<InventorySearchEntry> entries,
  String query, {
  int limit = 12,
}) {
  final q = query.trim();
  if (q.isEmpty) {
    return entries.take(limit).toList();
  }
  return entries
      .where((entry) => matchesInventorySearchQuery(entry.haystack, q))
      .take(limit)
      .toList();
}

List<InventorySearchEntry> inventorySearchEntriesFromMaterials(
  Iterable<RawMaterial> materials, {
  String? Function(int? categoryId)? categoryNameFor,
}) {
  return [
    for (final material in materials)
      InventorySearchEntry.fromMaterial(
        material,
        categoryName: categoryNameFor?.call(material.categoryId),
      ),
  ];
}

/// One dropdown row per purchasable stock pool (variants and duplicate
/// ingredient rows collapsed to the canonical holder).
List<InventorySearchEntry> inventoryPurchaseEntriesFromMaterials(
  Iterable<RawMaterial> materials, {
  String? Function(int? categoryId)? categoryNameFor,
}) {
  final linked = VariantHelpers.withSyncedLinks(materials.toList());
  final holders = SubItemStock.deduplicateToCanonicalStockHolders(linked);
  final stockMap = SubItemStock.buildCanonicalStockIdMap(linked);
  final poolMembers = <int, List<RawMaterial>>{};
  for (final material in linked) {
    final id = material.id;
    if (id == null) continue;
    final holderId = stockMap[id] ?? id;
    poolMembers.putIfAbsent(holderId, () => []).add(material);
  }

  final entries = <InventorySearchEntry>[];
  for (final holder in holders) {
    final holderId = holder.id;
    if (holderId == null) continue;
    final pool = poolMembers[holderId] ?? [holder];
    final partition = VariantHelpers.partitionForPos(pool);
    final primaryLabel = partition.groups.isNotEmpty
        ? partition.groups.first.posTitle
        : SubItemStock.canonicalLabelForFamily(pool).isNotEmpty
            ? SubItemStock.canonicalLabelForFamily(pool)
            : holder.staffLabel;

    entries.add(
      InventorySearchEntry(
        primaryLabel: primaryLabel,
        haystack: [
          primaryLabel,
          holder.name,
          holder.trimmedSubItem ?? '',
          holder.barcode ?? '',
          for (final variant in pool) ...[
            variant.name,
            variant.variantLabel ?? '',
            variant.staffLabel,
          ],
          categoryNameFor?.call(holder.categoryId) ?? '',
        ].join(' ').toLowerCase(),
        material: holder,
      ),
    );
  }

  entries.sort(
    (a, b) => a.primaryLabel.toLowerCase().compareTo(b.primaryLabel.toLowerCase()),
  );
  return entries;
}
