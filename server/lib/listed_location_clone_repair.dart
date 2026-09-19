import 'menu_catalog_match.dart';

const listedLocationCloneRepairV1 = 'listed_location_clone_repair_v1';

const postgresListedMaterialsRepairBody = '''
UPDATE raw_materials target
SET listed = source.listed
FROM raw_materials source
WHERE source.location_id = (SELECT MIN(id) FROM locations)
  AND target.location_id IS NOT NULL
  AND target.location_id != source.location_id
  AND lower(trim(target.name)) = lower(trim(source.name))
  AND lower(trim(coalesce(nullif(trim(target.sub_item), ''), target.name)))
    = lower(trim(coalesce(nullif(trim(source.sub_item), ''), source.name)))
  AND (
    source.barcode IS NULL
    OR trim(source.barcode::text) = ''
    OR target.barcode IS NOT DISTINCT FROM source.barcode
  )
  AND (
    source.category_id IS NULL
    OR target.category_id = source.category_id
  )
  AND target.listed IS DISTINCT FROM source.listed
''';

const postgresListedCombosIsActiveRepairBody = '''
UPDATE combos target
SET is_active = source.is_active
FROM combos source
WHERE source.location_id = (SELECT MIN(id) FROM locations)
  AND target.location_id IS NOT NULL
  AND target.location_id != source.location_id
  AND lower(trim(target.name)) = lower(trim(source.name))
  AND target.is_active IS DISTINCT FROM source.is_active
''';

const postgresListedDistributionAuditSql = '''
SELECT location_id, listed, COUNT(*)::int AS row_count
FROM raw_materials
WHERE location_id IS NOT NULL
GROUP BY location_id, listed
ORDER BY location_id, listed
''';
