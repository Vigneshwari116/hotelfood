import 'package:foodstock/model/models.dart';
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

  factory InventorySearchEntry.fromCombo(Combo combo) {
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
      haystack: inventoryComboHaystack(combo),
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
  final name = material.staffLabel.toLowerCase();
  final parts = <String>[];
  final variant = VariantHelpers.variantSelectorLabel(material).trim();
  if (variant.isNotEmpty) {
    parts.add(variant);
  }
  final sub = material.trimmedSubItem;
  if (sub != null && sub.toLowerCase() != name) {
    parts.add(sub);
  }
  final barcode = material.barcode?.trim();
  if (barcode != null && barcode.isNotEmpty) {
    parts.add(barcode);
  }
  if (parts.isEmpty) return null;
  return parts.join('  •  ');
}

String inventoryComboHaystack(Combo combo) {
  return [
    combo.name,
    combo.barcode ?? '',
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
