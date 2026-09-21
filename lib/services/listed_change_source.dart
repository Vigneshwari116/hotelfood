/// Declared intent for every programmatic change to [RawMaterial.listed].
class ListedChangeSource {
  ListedChangeSource._();

  static const userHide = 'user_hide';
  static const userToggle = 'user_toggle';

  static const importCatalogPrune = 'import_catalog_prune';
  static const importVariantDedup = 'import_variant_dedup';
  static const importCatalogDedupCategory = 'import_catalog_dedup_category';
  static const importCatalogDedupName = 'import_catalog_dedup_name';
  static const importCatalogDedupPopcorn = 'import_catalog_dedup_popcorn';
  static const importCatalogMergeStock = 'import_catalog_merge_stock';

  static void requireDeclared(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('listed change source must be non-empty');
    }
  }
}
