/// Catalog identity for matching cloned menu rows across [locations].
library;

/// Dart-side key (tests and client logic).
String rawMaterialCatalogMatchKey({
  required String name,
  String? subItem,
  String? barcode,
  int? categoryId,
}) {
  final normalizedName = name.trim().toLowerCase();
  final sub = (subItem ?? '').trim();
  final effectiveSub = sub.isEmpty ? normalizedName : sub.toLowerCase();
  final normalizedBarcode = (barcode ?? '').trim().toLowerCase();
  final category = categoryId?.toString() ?? '';
  return '$category|$normalizedBarcode|$normalizedName|$effectiveSub';
}

/// SQL join condition: [targetAlias] row matches [sourceAlias] template row.
String rawMaterialCatalogMatchSql({
  required String targetAlias,
  required String sourceAlias,
}) {
  return '''
lower(trim($targetAlias.name)) = lower(trim($sourceAlias.name))
AND lower(trim(coalesce(nullif(trim($targetAlias.sub_item), ''), $targetAlias.name)))
  = lower(trim(coalesce(nullif(trim($sourceAlias.sub_item), ''), $sourceAlias.name)))
AND (
  $sourceAlias.barcode IS NULL
  OR trim($sourceAlias.barcode) = ''
  OR $targetAlias.barcode IS $sourceAlias.barcode
)
AND (
  $sourceAlias.category_id IS NULL
  OR $targetAlias.category_id = $sourceAlias.category_id
)
''';
}

/// Postgres variant using IS NOT DISTINCT FROM for barcode.
String postgresRawMaterialCatalogMatchSql({
  required String targetAlias,
  required String sourceAlias,
}) {
  return '''
lower(trim($targetAlias.name)) = lower(trim($sourceAlias.name))
AND lower(trim(coalesce(nullif(trim($targetAlias.sub_item), ''), $targetAlias.name)))
  = lower(trim(coalesce(nullif(trim($sourceAlias.sub_item), ''), $sourceAlias.name)))
AND (
  $sourceAlias.barcode IS NULL
  OR trim($sourceAlias.barcode::text) = ''
  OR $targetAlias.barcode IS NOT DISTINCT FROM $sourceAlias.barcode
)
AND (
  $sourceAlias.category_id IS NULL
  OR $targetAlias.category_id = $sourceAlias.category_id
)
''';
}

String comboCatalogMatchSql({
  required String targetAlias,
  required String sourceAlias,
}) {
  return 'lower(trim($targetAlias.name)) = lower(trim($sourceAlias.name))';
}
